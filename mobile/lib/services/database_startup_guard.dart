import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqlite3/sqlite3.dart';

import '../utils/debug_log.dart';

/// نتيجة فحص حارس الإقلاع لقاعدة البيانات.
enum StartupGuardStatus {
  /// لا يوجد ملف قاعدة بيانات بعد (تثبيت جديد) — لا شيء للفحص.
  freshInstall,

  /// الملف موجود وسليم (quick_check = ok).
  healthy,

  /// الملف تالف — نُسخ للعزل الحكمي ثم حُذف، وسيُعاد إنشاؤه فارغاً
  /// وسيعيد التطبيق مزامنة كل البيانات من Appwrite (المصدر الموثوق).
  recovered,

  /// تعذّر تنفيذ الفحص (مثلاً فشل حل المسار) — لا نعيق الإقلاع أبداً.
  unknown,
}

/// نتيجة quick_check الداخلية.
class _QuickCheckResult {
  _QuickCheckResult._(this.isHealthy, this.errorSummary);
  final bool isHealthy;
  final String errorSummary;
}

class StartupGuardResult {
  const StartupGuardResult._({
    required this.status,
    this.quarantinePath,
    this.details,
  });

  final StartupGuardStatus status;
  final String? quarantinePath;
  final String? details;

  bool get recovered => status == StartupGuardStatus.recovered;
}

/// ✅ حارس تلف قاعدة البيانات عند الإقلاع (SqliteException code 11).
///
/// الخلفية (تقرير إنتاج 2026-09): `database disk image is malformed` على
/// جداول outbox و inventory_items. الفحص الصحي الحالي
/// (DatabaseHealthChecker → `SELECT 1`) لا يكشف تلف الصفحات — SQLite
/// يقرأ الترويسة فقط للاستعلامات البسيطة، بينما التلف الفعلي يظهر عند
/// قراءة صفحات بيانات فاسدة. كما أن الوضع WAL
/// (local_db.dart `PRAGMA journal_mode = WAL`) قد يترك ملف -wal غير متسق
/// مع الملف الرئيسي إذا انقطعت الطاقة أو قُتل التطبيق أثناء كتابة.
///
/// الاستراتيجية:
/// 1. الفحص يعمل **قبل** أول فتح لـ Drift (يُستدعى من main مباشرة بعد
///    `WidgetsFlutterBinding.ensureInitialized`) عبر حزمة sqlite3 مباشرة
///    على الملف — بلا تداخل مع Drift.
/// 2. `PRAGMA quick_check` (النسخة السريعة من integrity_check — تكشف
///    الصفحات المفقودة/الفاسدة دون فحص اتساق الفهارس الكامل).
/// 3. عند التلف: نسخة forensics للعزل (db + -wal + -shm) ثم حذف الملفات
///    الثلاثة. SQLite ينشئ ملفاً فارغاً سليماً عند الفتح التالي، ومخطط
///    Drift يُطبَّق عبر migrations كالمعتاد، ودورة المزامنة التالية
///    تعيد سحب كل البيانات من Appwrite (نفس مسار bootstrap الجهاز
///    الجديد — outbox فارغ وcheckpoints صفرية → full pull).
/// 4. الحارس لا يرمي استثناءات أبداً (fail-open): أي فشل في الفحص نفسه
///    يُسجَّل ولا يعيق إقلاع التطبيق.
class DatabaseStartupGuard {
  DatabaseStartupGuard._();

  /// اسم ملف القاعدة — مطابق لـ `_dbFileName` في local_db.dart
  /// (لا يمكن استيراد الثابت مباشرة لأن local_db.dart يستورد Druid
  /// الثقيل؛ هنا نحتاج الملف فقط قبل فتح Drift).
  static const String kDefaultDbFileName = 'marina_hotel.db';

  /// أقصى عدد صفوف يُقرأ من نتيجة quick_check (قد تطول عند التلف الشديد).
  static const int _maxCheckRows = 10;

  /// فحص القاعدة واستردادها عند التلف. آمن للاستدعاء من main.
  static Future<StartupGuardResult> verifyAndRecover() async {
    final Directory dbDir;
    try {
      dbDir = await _resolveDbDir();
    } catch (e, st) {
      dwarn(
        () =>
            '⚠️ DatabaseStartupGuard فشل حل المجلد (لا يعيق الإقلاع): $e\n$st',
      );
      return StartupGuardResult._(
        status: StartupGuardStatus.unknown,
        details: e.toString(),
      );
    }
    return verifyAndRecoverIn(dbDir);
  }

  /// النسخة القابلة للاختبار: تعمل على أي مجلد (الإنتاج يمرر مجلد sqflite).
  static Future<StartupGuardResult> verifyAndRecoverIn(Directory dbDir) async {
    try {
      final dbPath = p.join(dbDir.path, kDefaultDbFileName);
      final dbFile = File(dbPath);
      if (!dbFile.existsSync()) {
        return const StartupGuardResult._(
          status: StartupGuardStatus.freshInstall,
        );
      }

      final check = await _runQuickCheck(dbPath);
      if (check.isHealthy) {
        dlog(
          '✅ DatabaseStartupGuard: quick_check ok '
          '(${dbFile.lengthSync()} bytes)',
        );
        return const StartupGuardResult._(status: StartupGuardStatus.healthy);
      }

      // ─── القاعدة تالفة: عزل حكمي ثم إعادة إنشاء ───
      dwarn(
        () =>
            '🛨️ DatabaseStartupGuard: قاعدة البيانات تالفة! '
            '${check.errorSummary}\n'
            '→ نسخ forensics ثم حذف وإعادة إنشاء + إعادة مزامنة من السحابة',
      );

      final quarantinePath = await _quarantineAndRecreate(dbFile, dbDir);

      // ✅ تحقق نهائي فقط إن بقي الملف (فشل حذف best-effort) —
      // ملاحظة: sqlite3.open() ينشئ الملف إن كان غائباً، لذا لا نفتح
      // إلا عند الوجود لتفادي إعادة إنشاء ملف بعد حذفه بنجاح.
      if (File(dbPath).existsSync()) {
        final recheck = await _runQuickCheck(dbPath);
        if (!recheck.isHealthy) {
          dwarn(
            () =>
                '⚠️ DatabaseStartupGuard: الملف بقي بعد الحذف وما زال '
                'تالفاً — Drift سيفشل عند الفتح وسيُعاد الفحص الإقلاع القادم',
          );
        }
      }

      return StartupGuardResult._(
        status: StartupGuardStatus.recovered,
        quarantinePath: quarantinePath,
        details: check.errorSummary,
      );
    } catch (e, st) {
      dwarn(() => '⚠️ DatabaseStartupGuard فشل (لا يعيق الإقلاع): $e\n$st');
      return StartupGuardResult._(
        status: StartupGuardStatus.unknown,
        details: e.toString(),
      );
    }
  }

  /// حل مجلد القاعدة — مطابق لمنطق `_open()` في local_db.dart:
  /// Desktop → ApplicationDocuments، Mobile → sqflite.getDatabasesPath().
  static Future<Directory> _resolveDbDir() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return getApplicationDocumentsDirectory();
    }
    final sqfliteDir = await sqflite.getDatabasesPath();
    return Directory(sqfliteDir);
  }

  /// فتح الملف بـ sqlite3 وتشغيل quick_check.
  /// أي استثناء عند الفتح (مثل "file is not a database" أو "malformed")
  /// يُعامَل كتلف — لأن Drift سيفشل بنفس الطريقة لاحقاً.
  static Future<_QuickCheckResult> _runQuickCheck(String dbPath) async {
    Database? db;
    try {
      db = sqlite3.open(dbPath);
      final rows = db.select('PRAGMA quick_check($_maxCheckRows)');
      final first = rows.isEmpty
          ? 'ok'
          : (rows.first.values.first?.toString() ?? 'ok');
      if (first == 'ok') {
        return _QuickCheckResult._(true, 'ok');
      }
      final messages = rows
          .map((r) => r.values.map((v) => '$v').join(' | '))
          .take(_maxCheckRows)
          .join(' ; ');
      return _QuickCheckResult._(false, 'quick_check: $messages');
    } catch (e) {
      return _QuickCheckResult._(
        false,
        'فشل فتح القاعدة للفحص (يُعامَل كتلف): $e',
      );
    } finally {
      try {
        db?.close();
      } catch (_) {}
    }
  }

  /// نسخ الملفات الثلاثة (db + wal + shm) إلى مجلد عزل داخل مجلد القاعدة
  /// نفسه (نظام ملفات واحد — نسخة فورية) ثم حذفها من مكانها الأصلي —
  /// يعيد SQLite إنشاء ملف سليم فارغ عند الفتح التالي.
  static Future<String> _quarantineAndRecreate(
    File dbFile,
    Directory dbDir,
  ) async {
    final dbPath = dbFile.path;

    // 1) مجلد العزل الحكمي — داخل مجلد القاعدة نفسه
    final timestamp = _timestamp();
    final quarantineDir = Directory(p.join(dbDir.path, 'db_quarantine'));
    if (!quarantineDir.existsSync()) {
      quarantineDir.createSync(recursive: true);
    }
    final quarantineBase = p.join(
      quarantineDir.path,
      '${kDefaultDbFileName}_$timestamp',
    );

    // 2) نسخ forensics — best-effort لكل ملف على حدة
    for (final src in [dbPath, '$dbPath-wal', '$dbPath-shm']) {
      try {
        final f = File(src);
        if (f.existsSync()) {
          final suffix = src == dbPath ? '' : src.substring(dbPath.length);
          final dest = '$quarantineBase$suffix';
          f.copySync(dest);
          dlog(() => '🗄️ نسخة forensics: $dest');
        }
      } catch (e) {
        dwarn(() => '⚠️ فشل نسخ $src إلى العزل: $e');
      }
    }

    // 3) حذف الملفات الثلاثة — إعادة الإنشاء تتم عند فتح Drift التالي
    await _deleteDbFiles(dbPath);
    return quarantineBase;
  }

  static Future<void> _deleteDbFiles(String dbPath) async {
    for (final target in [dbPath, '$dbPath-wal', '$dbPath-shm']) {
      try {
        final f = File(target);
        if (f.existsSync()) {
          await f.delete();
          dlog(() => '🧹 حذف الملف التالف: $target');
        }
      } catch (e) {
        dwarn(() => '⚠️ فشل حذف $target: $e');
      }
    }
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
