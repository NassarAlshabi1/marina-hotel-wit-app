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

  /// التحقق من وجود نسخة .pre_restore من استعادة فاشلة سابقة
  /// إذا وُجدت، يتم استعادتها تلقائياً
  static Future<bool> recoverFromPreviousRestore() async {
    try {
      final dstPath = await _resolveDefaultDbPath();
      final preRestorePath = '$dstPath.pre_restore';
      final preRestoreFile = File(preRestorePath);
      
      if (!preRestoreFile.existsSync()) {
        return false; // لا توجد نسخة سابقة للاستعادة
      }
      
      // التحقق مما إذا كان DB الفعلي تالفاً أو غير موجود
      final dstFile = File(dstPath);
      String? validationError;
      if (dstFile.existsSync()) {
        try {
          await _validateSqliteFile(dstPath);
        } catch (e) {
          validationError = e.toString();
        }
      }
      
      if (!dstFile.existsSync() || validationError != null) {
        debugPrint(
          '🔄 استرجاع من pre_restore: DB الحالي غير صالح ($validationError)',
        );
        // حذف DB التالف إن وجد
        if (dstFile.existsSync()) {
          await dstFile.delete();
        }
        // استعادة من pre_restore
        await preRestoreFile.rename(dstPath);
        debugPrint('✅ تم استرجاع DB من النسخة الاحتياطية (pre_restore)');
        return true;
      }
      
      // DB الحالي سليم — نحذف pre_restore
      await preRestoreFile.delete();
      debugPrint('🧹 تم حذف pre_restore (DB الحالي سليم)');
      return false;
    } catch (e, st) {
      debugPrint('❌ فشل استرجاع pre_restore: $e\n$st');
      return false;
    }
  }

  /// التحقق من صحة ملف SQLite
  static Future<void> _validateSqliteFile(String dbPath) async {
    // لا يمكن استخدام sqflite مباشرة لأنه قد لا يكون معرفاً في هذا السياق
    // نستخدم check بسيط: الملف موجود وحجمه أكبر من 100 بايت
    final file = File(dbPath);
    if (!file.existsSync()) {
      throw Exception('الملف غير موجود');
    }
    final size = await file.length();
    if (size < 100) {
      throw Exception('الملف صغير جداً ($size بايت) — ليس قاعدة بيانات صالحة');
    }
    // نتحقق من توقيع SQLite (الأول 16 بايت)
    final raf = await file.open();
    try {
      final header = await raf.read(16);
      // SQLite magic bytes: "SQLite format 3\0"
      final sqliteMagic = [0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
                           0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00];
      bool isValid = header.length == sqliteMagic.length;
      if (isValid) {
        for (int i = 0; i < sqliteMagic.length; i++) {
          if (header[i] != sqliteMagic[i]) {
            isValid = false;
            break;
          }
        }
      }
      if (!isValid) {
        throw Exception('الملف ليس قاعدة بيانات SQLite صالحة (توقيع غير متطابق)');
      }
    } finally {
      await raf.close();
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

      // ✅ إصلاح: استبدال ذري باستخدام ملف مؤقت مع استرجاع آمن
      // نسخ الاحتياطي إلى ملف مؤقت أولاً، ثم إعادة تسميته إلى اسم DB الفعلي
      final tmpPath = '$dstPath.tmp';
      final tmpFile = File(tmpPath);
      
      // حذف أي ملف مؤقت سابق
      if (tmpFile.existsSync()) {
        await tmpFile.delete();
      }
      
      // نسخ الاحتياطي إلى الملف المؤقت
      await srcFile.copy(tmpPath);
      
      // ✅ التحقق من صحة ملف SQLite المؤقت قبل استبدال DB الفعلي
      try {
        await _validateSqliteFile(tmpPath);
      } catch (e) {
        // حذف الملف المؤقت غير الصالح قبل إعادة الرمي
        await tmpFile.delete();
        throw Exception('ملف النسخة الاحتياطية غير صالح: $e');
      }
      
      // استبدال ذري مع استرجاع تلقائي في حال الفشل
      if (dstFile.existsSync()) {
        final backupPath = '$dstPath.pre_restore';
        final backupFile = File(backupPath);
        // الاحتفاظ بنسخة أمان من DB الحالي قبل الحذف
        if (backupFile.existsSync()) {
          await backupFile.delete();
        }
        await dstFile.rename(backupPath);
      }
      
      // إعادة تسمية الملف المؤقت إلى اسم DB الفعلي
      try {
        await tmpFile.rename(dstPath);
      } catch (e) {
        // ❌ فشلت إعادة التسمية — نعيد نسخة الأمان
        if (dstFile.existsSync()) {
          final backupPath = '$dstPath.pre_restore';
          final backupFile = File(backupPath);
          if (backupFile.existsSync()) {
            await backupFile.rename(dstPath);
          }
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
