import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'local_db.dart';

/// File-based SQLite backup/restore utilities.
///
/// Dependencies: sqflite, path, path_provider (add to pubspec and run `flutter pub get`).
///
/// These helpers operate on the on-device SQLite file that Drift/sqflite uses.
/// They are intended for "full" backups where you copy/restore the actual
/// database file instead of exporting/importing JSON.
///
/// How to use from UI:
/// - Call `backupDatabase()` لإنشاء نسخة .db في مجلد يمكن للمستخدم الوصول إليه
///   (Android: /storage/emulated/0/Documents/MarinaHotelBackups, iOS: تطبيق الملفات).
///   شارك المسار الناتج مع المستخدم ليتمكن من نسخه أو مشاركته.
/// - To restore, obtain a `.db` file path (picked via a file chooser) and call
///   `restoreDatabase(sourcePath)`. After restore, reopen the database instance
///   so providers/streams reattach. You can pass a custom `reopenCallback` if
///   you maintain your own singleton.
///
/// NOTE: For selecting a .db file interactively, integrate `file_picker` in the
/// UI layer and pass the chosen path to `restoreDatabase`.
class SqliteBackupRestore {
  /// Default database file name used by Drift/sqflite. Change if the DB name differs.
  /// The current app uses 'marina_hotel.db' in `SqfliteQueryExecutor.inDatabaseFolder`.
  static const String kDefaultDbFileName = 'marina_hotel.db';
  static const String kAndroidDocumentsBackupPath =
      '/storage/emulated/0/Documents/MarinaHotelBackups';

  static Future<String> _resolveDefaultDbPath() async {
    final dbDir = await sqflite.getDatabasesPath();
    return p.join(dbDir, kDefaultDbFileName);
  }

  static String _ts() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}_${two(now.month)}_${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static Future<Directory> _resolveUserAccessibleDir() async {
    Directory? dir;

    try {
      if (Platform.isAndroid) {
        try {
          final documentsTarget = Directory(kAndroidDocumentsBackupPath);
          if (!documentsTarget.existsSync()) {
            await documentsTarget.create(recursive: true);
          }
          return documentsTarget;
        } catch (e) {
          debugPrint(
            '⚠️ Failed to access default backup dir, falling back: $e',
          );
        }
        final fallbackDirs = await getExternalStorageDirectories(
          type: StorageDirectory.documents,
        );
        if (fallbackDirs != null && fallbackDirs.isNotEmpty) {
          final fallbackTarget = Directory(
            p.join(fallbackDirs.first.path, 'MarinaHotelBackups'),
          );
          if (!fallbackTarget.existsSync()) {
            await fallbackTarget.create(recursive: true);
          }
          return fallbackTarget;
        }
        dir = await getApplicationDocumentsDirectory();
      } else if (Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        final downloadsDir = await getDownloadsDirectory();
        dir = downloadsDir ?? await getApplicationDocumentsDirectory();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to resolve user dir, falling back to app docs: $e');
    }

    dir ??= await getApplicationDocumentsDirectory();

    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  /// Create a timestamped copy of the SQLite database file in a user-accessible folder.
  /// Returns the absolute path of the created backup file.
  static Future<String> backupDatabase() async {
    try {
      final srcPath = await _resolveDefaultDbPath();
      final srcFile = File(srcPath);
      if (!srcFile.existsSync()) {
        throw Exception('Database not found at $srcPath');
      }

      final destDir = await _resolveUserAccessibleDir();
      final backupName = 'backup_${_ts()}.db';
      final destPath = p.join(destDir.path, backupName);

      await srcFile.copy(destPath);

      debugPrint('✅ SQLite backup created at: $destPath');
      return destPath;
    } catch (e, st) {
      debugPrint('❌ Failed to backup database: $e\n$st');
      rethrow;
    }
  }

  /// Restore the on-device database from a provided .db file path.
  ///
  /// - Ensures the file exists and has a .db extension.
  /// - Closes the current Drift database before replacing the file to avoid locks.
  /// - Copies the file to the default database path and reopens the database.
  /// - Optionally accepts a `reopenCallback` for custom reinitialization flows.
  static Future<void> restoreDatabase(
    String sourcePath, {
    Future<void> Function()? reopenCallback,
  }) async {
    try {
      if (sourcePath.isEmpty) {
        throw ArgumentError('sourcePath must not be empty');
      }
      if (!sourcePath.endsWith('.db')) {
        throw ArgumentError('Selected file must be a .db database file');
      }

      final srcFile = File(sourcePath);
      if (!srcFile.existsSync()) {
        throw Exception('Backup file not found: $sourcePath');
      }

      final dstPath = await _resolveDefaultDbPath();
      final dstFile = File(dstPath);

      // Ensure parent directory exists
      await dstFile.parent.create(recursive: true);

      // Close any open connections to avoid file locking
      await DatabaseManager.close();

      // ✅ إصلاح: استبدال ذري باستخدام ملف مؤقت
      // نسخ الاحتياطي إلى ملف مؤقت أولاً، ثم إعادة تسميته إلى اسم DB الفعلي
      final tmpPath = '$dstPath.tmp';
      final tmpFile = File(tmpPath);
      
      // حذف أي ملف مؤقت سابق
      if (tmpFile.existsSync()) {
        await tmpFile.delete();
      }
      
      // نسخ الاحتياطي إلى الملف المؤقت
      await srcFile.copy(tmpPath);
      
      // حذف ملف DB الحالي (بعد التأكد من وجود نسخة مؤقتة صالحة)
      if (dstFile.existsSync()) {
        final backupPath = '$dstPath.pre_restore';
        final backupFile = File(backupPath);
        // الاحتفاظ بنسخة أمان من DB الحالي قبل الحذف
        if (backupFile.existsSync()) {
          await backupFile.delete();
        }
        await dstFile.rename(backupPath);
      }
      
      // إعادة تسمية الملف المؤقت إلى اسم DB
      // BUG-4 FIX: rollback to pre_restore backup on failure
      try {
        await tmpFile.rename(dstPath);
      } catch (renameError) {
        final backupFile = File('$dstPath.pre_restore');
        if (backupFile.existsSync()) {
          await backupFile.rename(dstPath);
          debugPrint('⚠️ تم استعادة DB الأصلي بعد فشل الاستعادة: $renameError');
        }
        rethrow;
      }

      // Reopen the database so the app can continue working
      if (reopenCallback != null) {
        await reopenCallback();
      } else {
        await DatabaseManager.reopen();
      }

      debugPrint('✅ SQLite database restored from: $sourcePath');
    } catch (e, st) {
      debugPrint('❌ Failed to restore database: $e\n$st');
      rethrow;
    }
  }
}
