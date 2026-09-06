import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../utils/debug_log.dart';
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
          dlog(
            () => '⚠️ Failed to access default backup dir, falling back: $e',
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
      dlog(() => '⚠️ Failed to resolve user dir, falling back to app docs: $e');
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

      // ✅ WAL Checkpoint قبل النسخ — يضمن دمج كل التغييرات من ملف WAL (-wal)
      // إلى قاعدة البيانات الرئيسية قبل النسخ. عند النجاح (busy=0) يحتوي ملف
      // .db وحده على 100% من المعاملات الملتزمة → النسخة كاملة بملف واحد.
      // إذا كان هناك قارئ نشط يمنع اكتمال checkpoint نرفض إنشاء النسخة
      // بدلاً من إنتاج نسخة ناقصة بصمت (نسخة كاملة أو لا نسخة).
      final checkpointBusy = await _performWalCheckpoint();
      if (checkpointBusy) {
        throw StateError(
          'لا يمكن إنشاء نسخة SQLite متسقة أثناء وجود قارئ نشط لملف WAL',
        );
      }

      final destDir = await _resolveUserAccessibleDir();
      final backupName = 'backup_${_ts()}.db';
      final destPath = p.join(destDir.path, backupName);

      await srcFile.copy(destPath);

      // ✅ لا ننسخ -wal/-shm إلى مجلد النسخ. بعد wal_checkpoint(TRUNCATE)
      // الناجح (busy=0) يكون ملف WAL فارغاً وكل البيانات في .db نفسه، فالنسخ
      // بملف واحد هو الصيغة الكاملة والآمنة. نسخ sidecars في لحظة لاحقة من
      // لحظة نسخ .db قد يُنتج زوجاً غير متطابق زمنياً ويُفسد الاستعادة
      // ("database disk image is malformed").

      // ✅ التحقق من سلامة النسخة بعد النسخ — يضمن أن الملف المنتج نسخة
      // كاملة قابلة للفتح (يرصد النسخ المبتورة بسبب امتلاء التخزين مثلاً)
      // بدلاً من اكتشاف التلف وقت الاستعادة وهو أسوأ وقت ممكن.
      await verifyBackupIntegrity(File(destPath));

      dlog(() => '✅ SQLite backup created at: $destPath');
      return destPath;
    } catch (e, st) {
      dlog(() => '❌ Failed to backup database: $e\n$st');
      rethrow;
    }
  }

  /// تنفيذ PRAGMA wal_checkpoint(TRUNCATE) عبر اتصال sqflite مستقل.
  /// يدمج كل الصفحات المعدّلة من ملف WAL إلى قاعدة البيانات الرئيسية ثم يصفّر
  /// ملف WAL. يعيد true إذا كان الـ checkpoint مشغولاً (busy=1: قارئ نشط
  /// يمنع دمج كل الصفحات) — في هذه الحالة يجب على المتصل رفض إنشاء النسخة.
  static Future<bool> _performWalCheckpoint() async {
    final dbPath = await _resolveDefaultDbPath();
    // نفتح اتصالاً مباشراً على نفس ملف قاعدة البيانات وننفّذ checkpoint.
    // sqflite يدير اتصالًا مستقلاً عن Drift، لكن PRAGMA wal_checkpoint آمن
    // للتشغيل المتزامن لأنه داخلياً يأخذ lock على WAL.
    final db = await sqflite.openDatabase(dbPath, singleInstance: false);
    try {
      // النتيجة صف واحد: (busy, log, checkpointed)
      final result = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final busyValue = result.isNotEmpty ? result.first['busy'] : null;
      final busy = busyValue is num ? busyValue != 0 : false;
      if (busy) {
        dlog('⚠️ WAL checkpoint busy (active reader blocks completeness)');
      } else {
        dlog('✅ WAL checkpoint (TRUNCATE) completed before backup');
      }
      return busy;
    } finally {
      await db.close();
    }
  }

  /// التحقق من أن ملف SQLite نسخة كاملة وسليمة عبر PRAGMA integrity_check.
  /// عام (public) ليُعاد استخدامه بعد إنشاء أي نسخة .db — يضمن اكتشاف
  /// النسخ المبتورة/التالفة وقت الإنشاء بدلاً من وقت الاستعادة.
  static Future<void> verifyBackupIntegrity(File backupFile) async {
    sqflite.Database? backupDb;
    try {
      backupDb = await sqflite.openDatabase(
        backupFile.path,
        readOnly: true,
        singleInstance: false,
      );
      final result = await backupDb.rawQuery('PRAGMA integrity_check');
      final integrity = result.isEmpty ? null : result.first.values.first;
      if (integrity != 'ok') {
        throw StateError(
          'SQLite integrity_check failed for ${backupFile.path}: $integrity',
        );
      }
    } finally {
      await backupDb?.close();
    }
  }

  /// Restore the on-device database from a provided SQLite backup path.
  ///
  /// - Ensures the file exists and has a .db or .sqlite extension.
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
      final extension = p.extension(sourcePath).toLowerCase();
      if (extension != '.db' && extension != '.sqlite') {
        throw ArgumentError('Selected file must be a .db or .sqlite database');
      }

      final srcFile = File(sourcePath);
      if (!srcFile.existsSync()) {
        throw Exception('Backup file not found: $sourcePath');
      }

      // لا نلمس قاعدة البيانات الحالية قبل التأكد من قابلية فتح النسخة
      // ومن اجتياز SQLite integrity_check.
      await verifyBackupIntegrity(srcFile);

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
          dlog(() => '⚠️ تم استعادة DB الأصلي بعد فشل الاستعادة: $renameError');
        }
        rethrow;
      }

      // ✅ إصلاح حرج: حذف ملفات -wal و -shm القديمة قبل إعادة فتح DB
      //
      // Marina's DB uses PRAGMA journal_mode = WAL. في وضع WAL، يوجد ملفان
      // جانبيان بجانب .db الرئيسي:
      //   - .db-wal: يحتوي على المعاملات الحديثة غير المدمجة بعد في .db
      //   - .db-shm: فهرس ذاكرة مشتركة للوصول المتزامن لـ -wal
      //
      // عند الاستعادة، استبدلنا .db بملف جديد، لكن -wal و -shm القديمين
      // لا يزالان موجودين. عند فتح DB، SQLite يحاول إعادة تشغيل WAL القديم
      // على .db الجديد، مما قد يسبب:
      //   1. "database disk image is malformed"
      //   2. إعادة تطبيق معاملات قديمة على البيانات الجديدة (data corruption)
      //   3. سلوك غير محدد لأن -wal و -shm غير متوافقين مع .db الجديد
      //
      // الحل: حذف -wal و -shm بعد استبدال .db، قبل إعادة الفتح.
      // SQLite سينشئ ملفات -wal/-shm جديدة فارغة عند الحاجة.
      for (final suffix in const ['-wal', '-shm']) {
        final sidecar = File('$dstPath$suffix');
        if (sidecar.existsSync()) {
          try {
            await sidecar.delete();
            dlog(() => '🧹 حذف ملف $suffix القديم قبل إعادة الفتح');
          } catch (e) {
            dlog(
              () => '⚠️ فشل حذف $suffix القديم: $e — قد يسبب مشاكل عند الفتح',
            );
          }
        }
      }

      // Reopen the database so the app can continue working
      if (reopenCallback != null) {
        await reopenCallback();
      } else {
        await DatabaseManager.reopen();
      }

      dlog(() => '✅ SQLite database restored from: $sourcePath');
    } catch (e, st) {
      dlog(() => '❌ Failed to restore database: $e\n$st');
      rethrow;
    }
  }
}
