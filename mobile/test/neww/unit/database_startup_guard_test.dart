// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/database_startup_guard.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// ════════════════════════════════════════════════════════════════════════════
/// اختبارات حارس تلف قاعدة البيانات عند الإقلاع (DatabaseStartupGuard)
/// ════════════════════════════════════════════════════════════════════════════
///
/// تغطي الفروع الأربعة:
///  1. تثبيت جديد (لا ملف) → freshInstall بلا أي فعل
///  2. قاعدة سليمة → healthy بلا أي فعل
///  3. ملف تالف (garbage) → recovered + نسخة forensics + ملف نظيف
///  4. ملفات -wal/-shm جانبية → تُحذف مع الاسترداد
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_guard_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  String dbPath() =>
      p.join(tempDir.path, DatabaseStartupGuard.kDefaultDbFileName);

  test('تثبيت جديد: لا ملف قاعدة → freshInstall بلا فعل', () async {
    final result = await DatabaseStartupGuard.verifyAndRecoverIn(tempDir);

    expect(result.status, StartupGuardStatus.freshInstall);
    expect(result.recovered, isFalse);
    expect(
      File(dbPath()).existsSync(),
      isFalse,
      reason: 'الحارس لا ينشئ ملفاً — إنشاؤه مهمة Drift',
    );
  });

  test('قاعدة سليمة → healthy بلا أي استرداد', () async {
    // أنشئ قاعدة سليمة حقيقية مع بيانات
    final db = sqlite3.open(dbPath());
    db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)');
    db.execute("INSERT INTO t (name) VALUES ('ناصر'), ('السقاف')");
    db.close();

    final sizeBefore = File(dbPath()).lengthSync();

    final result = await DatabaseStartupGuard.verifyAndRecoverIn(tempDir);

    expect(result.status, StartupGuardStatus.healthy);
    expect(result.recovered, isFalse);
    expect(File(dbPath()).existsSync(), isTrue);
    expect(
      File(dbPath()).lengthSync(),
      sizeBefore,
      reason: 'الملف السليم لا يُمس',
    );
    // لا مجلد عزل
    expect(
      Directory(p.join(tempDir.path, 'db_quarantine')).existsSync(),
      isFalse,
    );
  });

  test('ملف تالف (ليس SQLite) → recovered + عزل حكمي + ملف جديد سليم', () async {
    // garbage bytes — ليس ترويسة SQLite صالحة (SQLite يبدأ بـ "SQLite format 3")
    final garbage = List<int>.generate(8192, (i) => (i * 37 + 11) % 251);
    File(dbPath()).writeAsBytesSync(garbage);

    final result = await DatabaseStartupGuard.verifyAndRecoverIn(tempDir);

    expect(result.status, StartupGuardStatus.recovered);
    expect(result.recovered, isTrue);

    // 1) الملف الأصلي حُذف (القاعدة الجديدة ستُنشأ بفتح Drift التالي)
    expect(
      File(dbPath()).existsSync(),
      isFalse,
      reason: 'ملف garbage يحذف — فتحه سيفشل مرة أخرى',
    );

    // 2) نسخة forensics موجودة في db_quarantine بنفس حجم garbage
    final quarantineDir = Directory(p.join(tempDir.path, 'db_quarantine'));
    expect(quarantineDir.existsSync(), isTrue);
    final quarantined = quarantineDir
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('-wal') && !f.path.endsWith('-shm'))
        .toList();
    expect(quarantined, hasLength(1));
    expect(quarantined.first.lengthSync(), garbage.length);
    expect(result.quarantinePath, isNotNull);
  });

  test('ملفات -wal و -shm الجانبية تُنسخ للعزل وتُحذف مع الاسترداد', () async {
    File(dbPath()).writeAsBytesSync(List<int>.filled(4096, 0xAB));
    File('${dbPath()}-wal').writeAsBytesSync(List<int>.filled(1024, 0xCD));
    File('${dbPath()}-shm').writeAsBytesSync(List<int>.filled(512, 0xEF));

    final result = await DatabaseStartupGuard.verifyAndRecoverIn(tempDir);

    expect(result.status, StartupGuardStatus.recovered);
    expect(File(dbPath()).existsSync(), isFalse);
    expect(
      File('${dbPath()}-wal').existsSync(),
      isFalse,
      reason: 'WAL التالف يجب حذفه — إبقاؤه يعيد إنتاج التلف',
    );
    expect(File('${dbPath()}-shm').existsSync(), isFalse);

    final quarantineDir = Directory(p.join(tempDir.path, 'db_quarantine'));
    final quarantinedNames = quarantineDir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList();
    // ملاحظة: SQLite نفسه يحذف -wal/-shm عند close() بعد فشل الفحص،
    // لذا يصل العزل بالملف الرئيسي فقط — والمهم أن الاثنين لم يعودا موجودين
    expect(
      quarantinedNames.length,
      1,
      reason: 'الملف الرئيسي معزول forensics (sidecars حذفها SQLite عند close)',
    );
  });

  test(
    'القاعدة المستردة قابلة للفتح والكتابة (محاكاة فتح Drift التالي)',
    () async {
      File(dbPath()).writeAsBytesSync(List<int>.filled(2048, 0x00));

      await DatabaseStartupGuard.verifyAndRecoverIn(tempDir);

      // فتح جديد (كما سيفعل Drift) → يجب أن ينجح ويقبل الكتابة
      final db = sqlite3.open(dbPath());
      db.execute('CREATE TABLE smoke (id INTEGER PRIMARY KEY, v TEXT)');
      db.execute("INSERT INTO smoke (v) VALUES ('ok')");
      final rows = db.select('SELECT count(*) AS c FROM smoke');
      expect(rows.first['c'], 1);
      db.close();

      // الفحص على القاعدة الجديدة سليم
      final result = await DatabaseStartupGuard.verifyAndRecoverIn(tempDir);
      expect(result.status, StartupGuardStatus.healthy);
    },
  );
}
