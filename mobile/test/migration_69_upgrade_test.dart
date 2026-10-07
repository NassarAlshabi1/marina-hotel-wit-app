// ✅ (migration 69 — المرحلة F) اختبار الترقية الفعلية 68 → 69 على قاعدة
// واقعية تحتوي بيانات (لا قاعدة فارغة فقط) — بأسلوب قاعدة ملف مؤقت:
//   1. بناء مخطط v68 مبسط + بيانات رواتب حقيقية.
//   2. السيناريو أ: قاعدة لم تفتح بعد بـ v68 (لا cycle_uuid خام) → الترقية
//      تضيف كل الأعمدة وتردّم cycle_uuid حتمياً من FK وتنشئ الفهرس الفريد.
//   3. السيناريو ب (الفخ المُكتشف في التدقيق): قاعدة سبق فتحها بـ v68 —
//      beforeOpen أضاف cycle_uuid خاماً. الترقية يجب ألا تفشل بـ
//      "duplicate column name" (حارس PRAGMA table_info) وأن تحفظ البيانات.
//   4. السيناريو ج: مرايا مكررة لنفس expense_uuid → لا يُنشأ الفهرس الفريد
//      ولا تُسقط البيانات (تسوية يدوية) — بوابات D1 0013.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('m69_test');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  /// بناء مخطط v68 مبسّط (الجداول المعنية فقط) + بيانات جاهزة.
  /// [withRawCycleUuid] يحاكي قاعدة فُتحت سابقاً بـ v68 فأضاف beforeOpen
  /// عمود cycle_uuid الخام (بدون فهارس/بدون ختم روابط).
  String buildV68Database(
    String path, {
    required bool withRawCycleUuid,
    required bool withDuplicateMirrors,
  }) {
    final db = sqlite3.sqlite3.open(path);
    db.execute('''
      CREATE TABLE employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        basic_salary REAL NOT NULL,
        position TEXT NOT NULL DEFAULT 'موظف',
        phone TEXT NOT NULL DEFAULT '',
        hire_date TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        local_uuid TEXT NOT NULL,
        server_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        last_modified INTEGER NOT NULL,
        created_at_iso TEXT,
        updated_at_iso TEXT,
        deleted_at_iso TEXT,
        created_at_epoch INTEGER NOT NULL,
        last_modified_epoch INTEGER NOT NULL,
        version INTEGER NOT NULL,
        origin TEXT NOT NULL,
        vector_clock TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        sync_timestamp INTEGER,
        idempotency_key TEXT
      );
      CREATE TABLE salary_cycles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL REFERENCES employees (id),
        employee_uuid TEXT,
        cycle_key TEXT NOT NULL,
        expected_amount INTEGER NOT NULL DEFAULT 0,
        actual_paid INTEGER NOT NULL DEFAULT 0,
        remaining_amount INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'draft',
        local_uuid TEXT NOT NULL,
        server_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        last_modified INTEGER NOT NULL,
        created_at_epoch INTEGER NOT NULL,
        last_modified_epoch INTEGER NOT NULL,
        version INTEGER NOT NULL,
        origin TEXT NOT NULL,
        vector_clock TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        sync_timestamp INTEGER
      );
      CREATE TABLE salary_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cycle_id INTEGER NOT NULL REFERENCES salary_cycles (id),
        employee_uuid TEXT,
        amount INTEGER NOT NULL DEFAULT 0,
        hotel_day_key TEXT,
        payment_date_iso TEXT NOT NULL,
        method TEXT,
        is_auto_generated INTEGER NOT NULL DEFAULT 0,
        local_uuid TEXT NOT NULL,
        server_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        last_modified INTEGER NOT NULL,
        created_at_epoch INTEGER NOT NULL,
        last_modified_epoch INTEGER NOT NULL,
        version INTEGER NOT NULL,
        origin TEXT NOT NULL,
        vector_clock TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        sync_timestamp INTEGER
      );
      CREATE TABLE salary_withdrawals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL REFERENCES employees (id),
        employee_uuid TEXT,
        amount REAL NOT NULL,
        withdraw_date TEXT NOT NULL,
        reason TEXT,
        hotel_day_key TEXT,
        withdrawal_type TEXT,
        description TEXT,
        expense_id INTEGER,
        expense_uuid TEXT,
        recorder_name TEXT,
        local_uuid TEXT NOT NULL,
        server_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        last_modified INTEGER NOT NULL,
        created_at_epoch INTEGER NOT NULL,
        last_modified_epoch INTEGER NOT NULL,
        version INTEGER NOT NULL,
        origin TEXT NOT NULL,
        vector_clock TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        sync_timestamp INTEGER
      );
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_type TEXT NOT NULL,
        related_id INTEGER,
        description TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        cash_transaction_id INTEGER,
        hotel_day_key TEXT,
        category_uuid TEXT,
        cash_flow_uuid TEXT,
        is_auto_generated INTEGER NOT NULL DEFAULT 0,
        employee_uuid TEXT,
        withdrawal_uuid TEXT,
        local_uuid TEXT NOT NULL,
        server_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        last_modified INTEGER NOT NULL,
        created_at_epoch INTEGER NOT NULL,
        last_modified_epoch INTEGER NOT NULL,
        version INTEGER NOT NULL,
        origin TEXT NOT NULL,
        vector_clock TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        sync_timestamp INTEGER
      );
    ''');

    // بيانات v68: موظف + دورة + دفعة مرتبطة رقمياً + مرآة نشطة + مرآة محذوفة
    db.execute(
      "INSERT INTO employees (id, name, basic_salary, status, "
      "local_uuid, created_at, updated_at, last_modified, created_at_epoch, "
      "last_modified_epoch, version, origin, vector_clock) "
      "VALUES (1, 'موظف ترقية', 1000, 'نشط', 'emp-uuid-69', 0, 0, 0, 0, 0, 1, 'local', '{}')",
    );
    db.execute(
      "INSERT INTO salary_cycles (id, employee_id, employee_uuid, "
      "cycle_key, local_uuid, created_at, updated_at, last_modified, "
      "created_at_epoch, last_modified_epoch, version, origin, vector_clock) "
      "VALUES (1, 1, 'emp-uuid-69', '2026-01', 'cycle-uuid-69', 0, 0, 0, 0, 0, 1, 'local', '{}')",
    );
    db.execute(
      "INSERT INTO salary_payments (id, cycle_id, employee_uuid, "
      "amount, payment_date_iso, local_uuid, created_at, updated_at, "
      "last_modified, created_at_epoch, last_modified_epoch, version, origin, "
      "vector_clock) VALUES (1, 1, 'emp-uuid-69', 100, '2026-01-05', "
      "'pay-uuid-69', 0, 0, 0, 0, 0, 1, 'local', '{}')",
    );
    db.execute(
      "INSERT INTO salary_withdrawals (id, employee_id, employee_uuid, "
      "amount, withdraw_date, expense_id, expense_uuid, local_uuid, "
      "created_at, updated_at, last_modified, created_at_epoch, "
      "last_modified_epoch, version, origin, vector_clock) "
      "VALUES (1, 1, 'emp-uuid-69', 50, '2026-01-05', NULL, 'exp-uuid-69', "
      "'wd-uuid-69', 0, 0, 0, 0, 0, 1, 'local', '{}')",
    );
    if (withDuplicateMirrors) {
      // مرآة ثانية نشطة بنفس expense_uuid — تمنع الفهرس الفريد
      db.execute(
        "INSERT INTO salary_withdrawals (id, employee_id, "
        "employee_uuid, amount, withdraw_date, expense_id, expense_uuid, "
        "local_uuid, created_at, updated_at, last_modified, created_at_epoch, "
        "last_modified_epoch, version, origin, vector_clock) "
        "VALUES (2, 1, 'emp-uuid-69', 50, '2026-01-05', NULL, 'exp-uuid-69', "
        "'wd-uuid-69-dup', 0, 0, 0, 0, 0, 1, 'local', '{}')",
      );
    } else {
      // مرآة ثانية لكن محذوفة ناعماً — لا تمنع الفهرس (فهرس جزئي)
      db.execute(
        "INSERT INTO salary_withdrawals (id, employee_id, "
        "employee_uuid, amount, withdraw_date, expense_id, expense_uuid, "
        "local_uuid, created_at, updated_at, deleted_at, last_modified, "
        "created_at_epoch, last_modified_epoch, version, origin, vector_clock) "
        "VALUES (2, 1, 'emp-uuid-69', 50, '2026-01-05', NULL, 'exp-uuid-69', "
        "'wd-uuid-69-del', 0, 0, 777, 0, 0, 0, 1, 'local', '{}')",
      );
    }
    db.execute(
      "INSERT INTO expenses (id, expense_type, description, amount, "
      "date, employee_uuid, withdrawal_uuid, local_uuid, created_at, "
      "updated_at, last_modified, created_at_epoch, last_modified_epoch, "
      "version, origin, vector_clock) VALUES (1, 'سحب راتب', 'مرآة', 50, "
      "'2026-01-05', 'emp-uuid-69', 'wd-uuid-69', 'exp-uuid-69', 0, 0, 0, "
      "0, 0, 1, 'local', '{}')",
    );

    if (withRawCycleUuid) {
      // ما كان يفعله beforeOpen (G-1) على v68: عمود خام بلا ختم روابط
      db.execute('ALTER TABLE salary_payments ADD COLUMN "cycle_uuid" TEXT');
    }
    db.execute('PRAGMA user_version = 68');
    db.close();
    return path;
  }

  /// يفتح قاعدة v68 عبر AppDatabase الفعلي → يُشغّل الترقية 69 الحقيقية.
  Future<AppDatabase> openAndMigrate(String path) async {
    // forTesting مجرد مُنشئ يقبل Executor — القاعدة والترحيلات الحقيقية
    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    // أول استعلام يفتح القاعدة ويستدعي onUpgrade(from=68, to=69) + beforeOpen
    await db.customSelect('SELECT 1').get();
    return db;
  }

  test(
    'السيناريو أ — v68 بلا عمود خام: ترقية كاملة + ردّم حتمي + فهرس فريد',
    () async {
      final path = buildV68Database(
        '${tmpDir.path}/a.db',
        withRawCycleUuid: false,
        withDuplicateMirrors: false,
      );
      final db = await openAndMigrate(path);

      // 1) أعمدة العقد موجودة
      final cols = await db.customSelect('PRAGMA table_info(expenses)').get();
      final colNames = cols.map((r) => r.data['name'].toString()).toSet();
      expect(colNames, containsAll(['expense_kind', 'employee_link_cleared']));
      final payCols = await db
          .customSelect('PRAGMA table_info(salary_payments)')
          .get();
      expect(
        payCols.map((r) => r.data['name'].toString()),
        contains('cycle_uuid'),
      );

      // 2) الأعمدة الجديدة بلا قيم تخمينية: NULL للتصنيف القديم، 0 للعلامة
      final exp = await db
          .customSelect(
            'SELECT expense_kind, employee_link_cleared '
            'FROM expenses WHERE id = 1',
          )
          .getSingle();
      expect(exp.data['expense_kind'], isNull);
      expect(exp.data['employee_link_cleared'], 0);

      // 3) ردّم cycle_uuid حتمي من FK (cycle_id=1 → الدورة local_uuid)
      final pay = await db
          .customSelect('SELECT cycle_uuid FROM salary_payments WHERE id = 1')
          .getSingle();
      expect(pay.data['cycle_uuid'], 'cycle-uuid-69');

      // 4) الفهرس الفريد الجزئي أُنشئ (لا تكرارات نشطة)
      final idx = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name='idx_salary_withdrawals_active_expense'",
          )
          .getSingleOrNull();
      expect(idx, isNotNull, reason: 'الفهرس الفريد يجب أن يُنشأ بعد الترقية');

      // 5) بيانات سليمة: لا فقد ولا تعديل مبالغ
      final wd = await db
          .customSelect('SELECT COUNT(*) AS n FROM salary_withdrawals')
          .getSingle();
      expect(wd.data['n'], 2); // النشطة + المحذوفة ناعماً
      await db.close();
    },
  );

  test(
    'السيناريو ب — الفخ: v68 بعمود cycle_uuid خام سابق ⇒ الترقية لا تفشل',
    () async {
      final path = buildV68Database(
        '${tmpDir.path}/b.db',
        withRawCycleUuid: true,
        withDuplicateMirrors: false,
      );
      // قبل الإصلاح كان هذا السيناريو يفشل بـ duplicate column name —
      // حارس PRAGMA table_info في الترحيل 69 يمنع ذلك
      final db = await openAndMigrate(path);

      final pay = await db
          .customSelect('SELECT cycle_uuid FROM salary_payments WHERE id = 1')
          .getSingle();
      // العمود الخام كان موجوداً (NULL) — الردّم الحتمي اختَمه من FK
      expect(pay.data['cycle_uuid'], 'cycle-uuid-69');
      await db.close();
    },
  );

  test(
    'السيناريو ج — مرايا مكررة نشطة: لا فهرس فريد ولا إسقاط بيانات',
    () async {
      final path = buildV68Database(
        '${tmpDir.path}/c.db',
        withRawCycleUuid: false,
        withDuplicateMirrors: true,
      );
      final db = await openAndMigrate(path);

      // الترقية اكتملت (لم تتوقف عند الفهرس) والبيانات كلها محفوظة
      final wd = await db
          .customSelect('SELECT COUNT(*) AS n FROM salary_withdrawals')
          .getSingle();
      expect(wd.data['n'], 2);

      // الفهرس الفريد لم يُنشأ — بانتظار تسوية يدوية (تفشل برسالة لا بإسقاط)
      final idx = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name='idx_salary_withdrawals_active_expense'",
          )
          .getSingleOrNull();
      expect(
        idx,
        isNull,
        reason: 'مع التكرارات يُؤجَّل الفهرس لا تُسقط البيانات',
      );

      // الأعمدة أُضيفت بالرغم من ذلك
      final pay = await db
          .customSelect('SELECT cycle_uuid FROM salary_payments WHERE id = 1')
          .getSingle();
      expect(pay.data['cycle_uuid'], 'cycle-uuid-69');
      await db.close();
    },
  );
}
