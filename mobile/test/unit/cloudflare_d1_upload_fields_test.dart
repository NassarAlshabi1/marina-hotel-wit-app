// test/unit/cloudflare_d1_upload_fields_test.dart
//
// ✅ اختبار انحدار لتثبيت خرائط الحقول في قسم الرفع إلى Cloudflare D1
// (شاشة الإعدادات → النسخ الاحتياطي والاستعادة → تبويب Cloudflare D1).
//
// مسار الرفع (CloudflareD1Tab → CloudflareD1Service) يقرأ الجداول المحلية
// بـ SELECT * ويرفع أسماء الأعمدة كما هي (بلا تحويل) — لذا صحة الخريطة
// camelCase → snake_case تعتمد كلياً على أعمدة مخطط drift المولّد.
// هذا الاختبار يفتح قاعدة drift حقيقية في الذاكرة ويقرأ أسماء الأعمدة
// الفعلية عبر PRAGMA table_info لكل جدول مزامنة (نفس الجداول التي يرفعها
// التبويب افتراضياً — kAppwriteSyncedTables) ويثبّت الحقول الـ 17:
//
//   localUuid → local_uuid            serverId → server_id
//   createdAt → created_at            updatedAt → updated_at
//   deletedAt → deleted_at            lastModified → last_modified
//   origin → origin                   createdAtIso → created_at_iso
//   updatedAtIso → updated_at_iso     deletedAtIso → deleted_at_iso
//   createdAtEpoch → created_at_epoch
//   lastModifiedEpoch → last_modified_epoch
//   version → version                 vectorClock → vector_clock
//   idempotencyKey → idempotency_key  syncTimestamp → sync_timestamp
//   deviceId → device_id
//
// إذا أعاد أحد توليد drift بصياغة أعمدة مختلفة (مثلاً camelCase) فسيفشل
// هذا الاختبار قبل وصول أعمدة خاطئة إلى قاعدة D1.
//
// الاستخدام: flutter test test/unit/cloudflare_d1_upload_fields_test.dart

import 'dart:convert';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/screens/settings/backup/tabs/cloudflare_d1_tab.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_app_users_source.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// الخريطة المرجعية — اسم الحقل بصيغة Dart/Appwrite (camelCase) إلى اسم
/// عمود SQLite/D1 المتوقع (snake_case). أي انحراف = فشل الاختبار.
const Map<String, String> kExpectedSyncFieldMapping = <String, String>{
  'localUuid': 'local_uuid',
  'serverId': 'server_id',
  'createdAt': 'created_at',
  'updatedAt': 'updated_at',
  'deletedAt': 'deleted_at',
  'lastModified': 'last_modified',
  'origin': 'origin',
  'createdAtIso': 'created_at_iso',
  'updatedAtIso': 'updated_at_iso',
  'deletedAtIso': 'deleted_at_iso',
  'createdAtEpoch': 'created_at_epoch',
  'lastModifiedEpoch': 'last_modified_epoch',
  'version': 'version',
  'vectorClock': 'vector_clock',
  'idempotencyKey': 'idempotency_key',
  'syncTimestamp': 'sync_timestamp',
  'deviceId': 'device_id',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  /// استخراج قائمة الأعمدة من عبارة INSERT OR REPLACE الملتقطة
  /// (بين أول '(' و ') VALUES').
  List<String> insertColsOf(String sql) => sql
      .substring(sql.indexOf('(') + 1, sql.indexOf(') VALUES'))
      .split(',');

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// قراءة أسماء أعمدة جدول كما هي فعلياً في SQLite (نفس ما يصل D1).
  Future<Set<String>> tableColumns(String table) async {
    final rows = await db
        .customSelect("SELECT name FROM pragma_table_info('$table')")
        .get();
    return rows.map((r) => r.data['name'].toString()).toSet();
  }

  test('خريطة الحقول الـ 17 مكتملة وصحيحة كمرجع للاختبار', () {
    // حماية من التعديل العارض للخريطة المرجعية نفسها.
    expect(kExpectedSyncFieldMapping, hasLength(17));
    for (final entry in kExpectedSyncFieldMapping.entries) {
      final snake = entry.value;
      // كل اسم هدف يجب أن يكون snake_case خالصاً (بلا أحرف كبيرة).
      expect(
        snake,
        equals(snake.toLowerCase()),
        reason: '${entry.key} → $snake: الاسم المستهدف يجب أن يكون snake_case',
      );
      // والمصدر camelCase (بلا شرطة سفلية) — عدا origin/version أحادية الكلمة.
      expect(
        entry.key.contains('_'),
        isFalse,
        reason:
            '${entry.key}: اسم حقل Dart/Appwrite يجب أن يكون camelCase بلا "_"',
      );
    }
  });

  test(
    'كل جدول مزامنة يحمل الأعمدة الـ 17 بصيغة snake_case (مسار رفع D1)',
    () async {
      // kAppwriteSyncedTables هي نفسها الجداول المحددة افتراضياً في تبويب
      // Cloudflare D1 بالشاشة — تحقق أن المجموعة غير فارغة قبل الفحص.
      expect(kAppwriteSyncedTables, isNotEmpty);

      final failures = <String>[];
      for (final table in kAppwriteSyncedTables) {
        final columns = await tableColumns(table);

        for (final entry in kExpectedSyncFieldMapping.entries) {
          final dartField = entry.key;
          final expectedColumn = entry.value;
          if (!columns.contains(expectedColumn)) {
            failures.add(
              '$table: عمود "$expectedColumn" (من $dartField) غير موجود. '
              'الأعمدة الفعلية: ${columns.toList()..sort()}',
            );
          }
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'خرائط حقول المزامنة مكسورة في ${failures.length} موضعاً — '
            'هذه الأعمدة هي ما يرفعه تبويب Cloudflare D1 حرفياً إلى D1 '
            '(SELECT * بلا تحويل):\n${failures.join('\n')}',
      );
    },
  );

  test(
    'لا يوجد عمود camelCase في جداول المزامنة (منع ازدواج الأعمدة في D1)',
    () async {
      final camelRegExp = RegExp(r'[A-Z]');
      final offenders = <String>[];

      for (final table in kAppwriteSyncedTables) {
        final columns = await tableColumns(table);
        for (final column in columns) {
          if (camelRegExp.hasMatch(column)) {
            offenders.add('$table.$column');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'أعمدة camelCase في القاعدة المحلية سترفع إلى D1 كما هي وتنشئ '
            'أعمدة موازية للأعمدة snake_case (ازدواجية بيانات عبر '
            '_reconcileSchema): ${offenders.join('، ')}',
      );
    },
  );

  test(
    'الرفع الفعلي يرسل أسماء snake_case (إدراج ثم قراءة بنمط SELECT *)',
    () async {
      // محاكاة المسار الكامل: الإدراج عبر drift ثم القراءة بنفس استعلام
      // CloudflareD1Tab._upload (SELECT * FROM "table" LIMIT ? OFFSET ?)
      // والتحقق أن مفاتيح الخريطة هي أسماء snake_case الـ 17 نفسها.
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              localUuid: 'room-101-uuid',
              createdAt: 1735689600000,
              updatedAt: 1735776000000,
              lastModified: 1735776001000,
              roomNumber: '101',
              type: 'double',
              price: 100,
              status: 'شاغرة',
              serverId: const Value(7),
              createdAtIso: const Value('2026-01-01T00:00:00.000Z'),
              updatedAtIso: const Value('2026-01-02T00:00:00.000Z'),
              createdAtEpoch: const Value(1735689600),
              lastModifiedEpoch: const Value(1735776000),
              version: const Value(3),
              origin: const Value('local'),
              vectorClock: const Value('{"dev-a":1}'),
              deviceId: const Value('dev-a'),
              syncTimestamp: const Value(1735776001),
              idempotencyKey: const Value('idem-key-1'),
            ),
          );

      // نفس قراءة التبويب: SELECT * — مفاتيح r.data هي ما يُرفع حرفياً إلى D1.
      final rows = await db.customSelect('SELECT * FROM "rooms"').get();
      expect(rows, hasLength(1));
      final uploaded = rows.first.data;

      for (final entry in kExpectedSyncFieldMapping.entries) {
        expect(
          uploaded.containsKey(entry.value),
          isTrue,
          reason:
              'الصف المرفوع لا يحتوي عمود "${entry.value}" (المتوقع من '
              '${entry.key}) — المفاتيح الفعلية: ${uploaded.keys.toList()..sort()}',
        );
      }
      // عينة قيم للتأكد من أن الأعمدة ليست موجودة فحسب بل تحمل بياناتنا.
      expect(uploaded['local_uuid'], 'room-101-uuid');
      expect(uploaded['server_id'], 7);
      expect(uploaded['last_modified'], 1735776001000);
      expect(uploaded['created_at_iso'], '2026-01-01T00:00:00.000Z');
      expect(uploaded['updated_at_iso'], '2026-01-02T00:00:00.000Z');
      expect(uploaded['created_at_epoch'], 1735689600);
      expect(uploaded['last_modified_epoch'], 1735776000);
      expect(uploaded['sync_timestamp'], 1735776001);
      expect(uploaded['vector_clock'], '{"dev-a":1}');
      expect(uploaded['device_id'], 'dev-a');
      expect(uploaded['origin'], 'local');
      expect(uploaded['version'], 3);
      expect(uploaded['idempotency_key'], 'idem-key-1');
    },
  );

  test(
    'uploadData الفعلي: SQL بأسامي snake_case وقيم محفوظة حرفياً + إعادة رفع مطابقة',
    () async {
      // إدراج صف بقيم مميزة قابلة للتتبع في نص SQL.
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              localUuid: 'room-102-uuid',
              createdAt: 1735603200000,
              updatedAt: 1735689600000,
              lastModified: 1735776123456,
              roomNumber: '102',
              type: 'suite',
              price: 250,
              status: 'شاغرة',
              serverId: const Value(77),
              createdAtIso: const Value('2025-12-31T00:00:00.000Z'),
              updatedAtIso: const Value('2026-01-01T00:00:00.000Z'),
              createdAtEpoch: const Value(1735603200),
              lastModifiedEpoch: const Value(1735689600),
              version: const Value(42),
              origin: const Value('remote'),
              vectorClock: const Value('{"dev-b":9}'),
              deviceId: const Value('dev-b'),
              syncTimestamp: const Value(1735776999),
              idempotencyKey: const Value('idem-rooms-102'),
            ),
          );

      // نفس readChunk الذي يستخدمه CloudflareD1Tab._upload حرفياً.
      Future<List<Map<String, Object?>>> readChunk(
        int limit,
        int offset,
      ) async {
        final rows = await db
            .customSelect(
              'SELECT * FROM "rooms" LIMIT ? OFFSET ?',
              variables: [Variable.withInt(limit), Variable.withInt(offset)],
            )
            .get();
        return rows.map((r) => r.data).toList();
      }

      // مرآة لـ _sqlLiteral في CloudflareD1Service (نفس المنطق حرفياً).
      String lit(Object? v) {
        if (v == null) return 'NULL';
        if (v is int) return v.toString();
        if (v is double) return v.toString();
        if (v is bool) return v ? '1' : '0';
        return "'${v.toString().replaceAll("'", "''")}'";
      }

      Future<List<String>> runUpload() async {
        final captured = <String>[];
        final client = MockClient((request) async {
          captured.add(request.body);
          return http.Response('{"success": true, "result": []}', 200);
        });
        final service = CloudflareD1Service(
          const CloudflareD1Config(
            accountId: 'a',
            databaseId: 'b',
            apiToken: 't',
          ),
          client: client,
        );
        final result = await service.uploadData(
          tables: [
            CloudflareD1SourceTable(
              name: 'rooms',
              rowCount: 1,
              createSqlList: const [],
              readChunk: readChunk,
            ),
          ],
          deviceLabel: 'test-device',
        );
        expect(result.ok, isTrue, reason: result.errors.join('؛ '));
        expect(result.rowsUploaded, 1);

        // استخراج عبارات INSERT الخاصة بـ rooms من أجسام النداءات.
        final inserts = captured
            .map(
              (b) => (jsonDecode(b) as Map<String, dynamic>)['sql'] as String,
            )
            .expand((sql) => sql.split(';\n'))
            .map((s) => s.trim())
            .where((s) => s.startsWith('INSERT OR REPLACE INTO "rooms"'))
            .toList();
        expect(
          inserts,
          hasLength(1),
          reason: 'المتوقع عبارة INSERT واحدة لـ rooms',
        );
        return inserts;
      }

      final firstRun = await runUpload();
      final sql = firstRun.single;

      // 1) أسماء الأعمدة الـ 17 بصيغة snake_case داخل نص SQL
      //    (الإنتاج يكتب قائمة الأعمدة بدون اقتباس — أسماء صالحة لـ SQLite).
      final colList = sql
          .substring(sql.indexOf('(') + 1, sql.indexOf(') VALUES'))
          .split(',');
      expect(colList.toSet(), containsAll(kExpectedSyncFieldMapping.values));
      expect(colList, isNot(contains('localUuid')));
      expect(colList, isNot(contains('idempotencyKey')));
      expect(colList, isNot(contains('syncTimestamp')));
      expect(sql, isNot(contains('localUuid')));

      // 2) القيم محفوظة حرفياً — timestamps/version/idempotency_key لم تُعد إنشاؤها.
      final row =
          (await db.customSelect('SELECT * FROM "rooms"').get()).first.data;
      final cols = row.keys.toList();
      final expectedSql =
          'INSERT OR REPLACE INTO "rooms" '
          '(${cols.join(',')}) '
          'VALUES (${cols.map((c) => lit(row[c])).join(',')})';
      expect(
        sql,
        expectedSql,
        reason: 'العبارة المرسلة لا تطابق القيم الحرفية للصف',
      );
      // تحقق صريح بأثر واضح:
      expect(sql, contains('1735776123456')); // last_modified
      expect(sql, contains('1735776999')); // sync_timestamp
      expect(sql, contains('42')); // version — ليس 1
      expect(sql, contains("'idem-rooms-102'"));

      // 3) إعادة الرفع: نفس العبارة حرفياً — لا تُولَّد قيم جديدة.
      final secondRun = await runUpload();
      expect(
        secondRun.single,
        sql,
        reason: 'إعادة الرفع غيّرت العبارة — يتم إعادة إنشاء قيم بشكل خاطئ',
      );
    },
  );

  // ════════════════════════════════════════════════════════════════
  // ✅ D1-path audit fixes (2026-10-04) — الفجوات F1/F2/F3
  // ════════════════════════════════════════════════════════════════

  test(
    'الفجوة F3: حقول Phase 0 تصل D1 بالاسم — employee_uuid على '
    'salary_cycles/salary_withdrawals/expenses عبر مسار uploadData الحقيقي',
    () async {
      // موظف مرجعي (FK مفروض: PRAGMA foreign_keys = ON في beforeOpen).
      final empId = await db.into(db.employees).insert(
            EmployeesCompanion.insert(
              localUuid: 'emp-uuid-9',
              createdAt: 1735689600000,
              updatedAt: 1735689600000,
              lastModified: 1735689600000,
              name: 'موظف الاختبار',
              basicSalary: 1000,
              status: 'نشط',
            ),
          );
      expect(empId, isNotNull);

      // دورة راتب — employeeUuid هوية الربط عبر الأجهزة (Phase 0).
      await db.into(db.salaryCycles).insert(
            SalaryCyclesCompanion.insert(
              localUuid: 'cycle-uuid-1',
              createdAt: 1735689600000,
              updatedAt: 1735689600001,
              lastModified: 1735689600001,
              employeeId: empId,
              cycleKey: '2026-09',
              employeeUuid: const Value('emp-uuid-9'),
            ),
          );

      // مسحوبة راتب — employeeUuid + expenseId (P0.2/P0.3).
      await db.into(db.salaryWithdrawals).insert(
            SalaryWithdrawalsCompanion.insert(
              localUuid: 'wd-uuid-1',
              createdAt: 1735689600000,
              updatedAt: 1735689600002,
              lastModified: 1735689600002,
              employeeId: empId,
              amount: 250,
              withdrawDate: '2026-09-05',
              employeeUuid: const Value('emp-uuid-9'),
              expenseId: const Value(null),
            ),
          );

      // مصروف رواتب — P0.4: related_id يُحفظ صراحةً NULL مع employee_uuid.
      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              localUuid: 'exp-uuid-1',
              createdAt: 1735689600000,
              updatedAt: 1735689600003,
              lastModified: 1735689600003,
              expenseType: 'سلفة',
              description: 'سلفة موظف — مسار Phase 0',
              amount: 250,
              date: '2026-09-05',
              employeeUuid: const Value('emp-uuid-9'),
              relatedId: const Value(null),
            ),
          );

      final captured = <String>[];
      final client = MockClient((request) async {
        captured.add(request.body);
        return http.Response('{"success": true, "result": []}', 200);
      });
      final service = CloudflareD1Service(
        const CloudflareD1Config(accountId: 'a', databaseId: 'b', apiToken: 't'),
        client: client,
      );

      Future<List<Map<String, Object?>>> chunk(
        String table,
        int limit,
        int offset,
      ) async {
        final rows = await db
            .customSelect(
              'SELECT * FROM "$table" LIMIT ? OFFSET ?',
              variables: [Variable.withInt(limit), Variable.withInt(offset)],
            )
            .get();
        return rows.map((r) => r.data).toList();
      }

      final result = await service.uploadData(
        tables: [
          CloudflareD1SourceTable(
            name: 'salary_cycles',
            rowCount: 1,
            readChunk: (l, o) => chunk('salary_cycles', l, o),
          ),
          CloudflareD1SourceTable(
            name: 'salary_withdrawals',
            rowCount: 1,
            readChunk: (l, o) => chunk('salary_withdrawals', l, o),
          ),
          CloudflareD1SourceTable(
            name: 'expenses',
            rowCount: 1,
            readChunk: (l, o) => chunk('expenses', l, o),
          ),
        ],
      );
      expect(result.ok, isTrue, reason: result.errors.join('؛ '));
      expect(result.rowsUploaded, 3);

      final inserts = captured
          .map(
            (b) => (jsonDecode(b) as Map<String, dynamic>)['sql'] as String,
          )
          .expand((sql) => sql.split(';\n'))
          .map((s) => s.trim())
          // جدول app_backup_meta تُكتبه الخدمة تلقائياً بعد اكتمال الرفع —
          // نستثنيه (اسمه غير مقتبس بعلامات تنصيص).
          .where((s) => s.startsWith('INSERT OR REPLACE INTO "'))
          .toList();
      expect(inserts, hasLength(3));

      String insertFor(String table) => inserts
          .firstWhere((s) => s.startsWith('INSERT OR REPLACE INTO "$table"'));

      // 1) salary_cycles: عمود employee_uuid موجود وقيمته الحرفية تصل.
      final cyclesSql = insertFor('salary_cycles');
      final cyclesCols = insertColsOf(cyclesSql);
      expect(cyclesCols, contains('employee_uuid'));
      expect(cyclesSql, contains("'emp-uuid-9'"),
          reason: 'قيمة employee_uuid لم تصل حرفياً إلى D1');

      // 2) salary_withdrawals: نفس التثبيت.
      final wdSql = insertFor('salary_withdrawals');
      expect(insertColsOf(wdSql), contains('employee_uuid'));
      expect(wdSql, contains("'emp-uuid-9'"));

      // 3) expenses: employee_uuid يصل وrelated_id يصل NULL صراحةً (P0.4).
      final expSql = insertFor('expenses');
      expect(insertColsOf(expSql), contains('employee_uuid'));
      expect(expSql, contains("'emp-uuid-9'"));
      // التحقق الحرفي: الصف المحلي related_id == NULL ويجب أن يُرسل NULL
      // (لا 0 ولا نص فارغ) — نطابق العبارة كاملة بمرآة _sqlLiteral.
      final row =
          (await db.customSelect('SELECT * FROM "expenses"').get()).first.data;
      expect(row['related_id'], isNull);
      expect(row['employee_uuid'], 'emp-uuid-9');
      final cols = row.keys.toList();
      String lit(Object? v) {
        if (v == null) return 'NULL';
        if (v is int) return v.toString();
        if (v is double) return v.toString();
        if (v is bool) return v ? '1' : '0';
        return "'${v.toString().replaceAll("'", "''")}'";
      }

      expect(
        expSql,
        'INSERT OR REPLACE INTO "expenses" '
        '(${cols.join(',')}) VALUES (${cols.map((c) => lit(row[c])).join(',')})',
        reason: 'عبارة expenses المرسلة لا تطابق القيم الحرفية للصف',
      );
    },
  );

  test(
    'الفجوة F1: صفوف blacklist (created_by) مستبعدة من رفع shift_notes '
    'إلى D1 في كلا القيْم والعدّ — مع بقاءها محلياً',
    () async {
      // ملاحظة عادية createdBy='user' (الافتراضي).
      await db.into(db.shiftNotes).insert(
            ShiftNotesCompanion.insert(
              localUuid: 'note-user-1',
              createdAt: 1735689600000,
              updatedAt: 1735689600000,
              lastModified: 1735689600000,
              title: 'ملاحظة نوبة',
              content: 'محتوى عادي',
            ),
          );
      // صف قائمة سوداء — كما تكتبه `_syncBlacklist` حرفياً.
      await db.into(db.shiftNotes).insert(
            ShiftNotesCompanion.insert(
              localUuid: 'bl-uuid-1',
              createdAt: 1735689600000,
              updatedAt: 1735689600001,
              lastModified: 1735689600001,
              title: 'ضيف محظور',
              content: '{"nationalId":"N1","reason":"تهريب"}',
              createdBy: const Value('blacklist'),
            ),
          );

      // نفس بناء التبويب: العدّ مُفلتر + القراءة مُفلترة.
      final countRows = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM "shift_notes" '
            'WHERE $kShiftNotesD1ExclusionWhere',
          )
          .get();
      final count = countRows.first.data['n'] as int;
      expect(count, 1, reason: 'العدّ يجب أن يستبعد صف blacklist');

      final rows = await db
          .customSelect(
            'SELECT * FROM "shift_notes" WHERE $kShiftNotesD1ExclusionWhere '
            'LIMIT ? OFFSET ?',
            variables: [Variable.withInt(100), Variable.withInt(0)],
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.first.data['local_uuid'], 'note-user-1');

      // الرفع الفعلي عبر المسار المُفلتر نفسه.
      final captured = <String>[];
      final client = MockClient((request) async {
        captured.add(request.body);
        return http.Response('{"success": true, "result": []}', 200);
      });
      final service = CloudflareD1Service(
        const CloudflareD1Config(accountId: 'a', databaseId: 'b', apiToken: 't'),
        client: client,
      );
      final result = await service.uploadData(
        tables: [
          CloudflareD1SourceTable(
            name: 'shift_notes',
            rowCount: count,
            readChunk: (limit, offset) async {
              final chunk = await db
                  .customSelect(
                    'SELECT * FROM "shift_notes" '
                    'WHERE $kShiftNotesD1ExclusionWhere LIMIT ? OFFSET ?',
                    variables: [
                      Variable.withInt(limit),
                      Variable.withInt(offset),
                    ],
                  )
                  .get();
              return chunk.map((r) => r.data).toList();
            },
          ),
        ],
      );
      expect(result.ok, isTrue, reason: result.errors.join('؛ '));
      expect(result.rowsUploaded, 1,
          reason: 'صف blacklist تسلل إلى الرفع');

      final sqlBlob = captured.join('\n');
      expect(sqlBlob, contains("'note-user-1'"));
      expect(sqlBlob, isNot(contains("'bl-uuid-1'")),
          reason: 'هوية صف blacklist ظهرت في SQL الرفع');
      expect(sqlBlob, isNot(contains('تهريب')),
          reason: 'محتوى blacklist تسرب إلى مرآة D1');

      // والأهم: الاستبعاد عرضي — البيانات تبقى محلياً وسليمة.
      final localAll = await db.select(db.shiftNotes).get();
      expect(localAll, hasLength(2));
      expect(
        localAll.where((r) => r.createdBy == 'blacklist').map((r) => r.localUuid),
        ['bl-uuid-1'],
      );
    },
  );

  test('ثوابت الفجوات F1/F2: الفلتر الصحيح والجدول التركيبي مُعرّفان', () {
    // الفلتر يسمح بـ NULL ويستبعد 'blacklist' حرفياً.
    expect(kShiftNotesD1ExclusionWhere, contains('created_by IS NULL'));
    expect(kShiftNotesD1ExclusionWhere, contains("created_by <> 'blacklist'"));
    // app_users تركيبي وليس جدول Drift ضمن القائمة العادية.
    expect(kD1SyntheticTables, contains('app_users'));
    expect(kAppwriteSyncedTables, isNot(contains('app_users')));
  });

  test(
    'الفجوة F2: بناء صفوف app_users التركيبية — الدمج والأمان والثبات',
    () {
      const localHash = 'pbkdf2_sha256\$100000\$localSalt\$localHash==';
      const cloudHash = 'pbkdf2_sha256\$100000\$cloudSalt\$cloudHash==';
      final rows = buildAppUsersBackupRows(
        AppUsersBackupInputs(
          localAccounts: {
            'yasser': {
              'password': localHash,
              'full_name': 'ياسر',
              'user_type': 'employee',
              'id': 2,
            },
            'محلي_فقط': {
              'password': localHash,
              'full_name': 'حساب لم يُرفع بعد',
              'user_type': 'employee',
              'id': 3,
            },
          },
          cloudAccounts: {
            'yasser': {
              'password': cloudHash,
              'full_name': 'ياسر (سحابي)',
              'user_type': 'manager',
              'role': 'manager',
              'permissions_json': '["bookings","payments"]',
              'active': false,
              'is_locked': true,
              'credentials_version': 4,
              'version': 7,
              'lastModified': 1234567,
              'doc_id': 'user_abc123',
              'cloud_user_id': 'user_abc123',
              'is_cloud': true,
            },
          },
          permissionsByUser: {
            'yasser': ['dashboard', 'rooms'],
            'admin': ['all'],
          },
          fixedAccounts: {
            'admin': {
              // كلمة مرور كودية — يجب ألا تصل المرآة بأي صيغة.
              'password': 'plain-secret-never-export',
              'user_type': 'admin',
              'full_name': 'مدير النظام',
              'id': 1,
            },
          },
          exportedAtIso: '2026-10-04T00:00:00.000Z',
        ),
      );

      // admin + yasser (مُدمج) + محلي_فقط + (لا يوجد حساب سحابي آخر هنا).
      expect(rows, hasLength(3));
      // ترتيب مستقر بالاسم.
      expect(
        rows.map((r) => r['username']).toList(),
        ['admin', 'yasser', 'محلي_فقط'],
      );
      // الأعمدة بترتيبها الثابت حرفياً.
      expect(rows.first.keys.toList(), kAppUsersD1Columns);

      // 1) الحساب الثابت: بلا تجزئة كلمة مرور إطلاقاً.
      final admin = rows.first;
      expect(admin['username'], 'admin');
      expect(admin['doc_id'], 'local_admin');
      expect(admin['password_hash'], isNull,
          reason: 'بيانات اعتماد الحسابات الكودية لا تُصدَّر');
      expect(admin['permissions'], '["all"]');
      expect(admin['is_cloud'], 0);
      expect(admin['user_type'], 'admin');

      // 2) السحابة تغلب المحلي بنفس اسم المستخدم.
      final yasser = rows.firstWhere((r) => r['username'] == 'yasser');
      expect(yasser['doc_id'], 'user_abc123');
      expect(yasser['password_hash'], cloudHash);
      expect(yasser['is_cloud'], 1);
      expect(yasser['active'], 0);
      expect(yasser['is_locked'], 1);
      expect(yasser['permissions'], '["bookings","payments"]');
      expect(yasser['credentials_version'], 4);
      expect(yasser['version'], 7);
      expect(yasser['last_modified'], 1234567);
      expect(yasser['user_type'], 'manager');
      expect(yasser['role'], 'manager');

      // 3) الحساب المحلي الصرف: تجزئة محلية + صلاحيات من الخريطة.
      final localOnly = rows.last;
      expect(localOnly['doc_id'], 'local_محلي_فقط');
      expect(localOnly['password_hash'], localHash);
      expect(localOnly['is_cloud'], 0);
      expect(localOnly['permissions'], '[]',
          reason: 'بلا صلاحيات في الخريطة → مصفوفة فارغة JSON');

      // 4) الأمان: لا نص صريح لأي كلمة مرور في الصفوف كله.
      final blob = jsonEncode(rows);
      expect(blob, isNot(contains('plain-secret-never-export')));
      // والتجزئات فقط تظهر.
      expect(blob, contains(cloudHash));
      expect(blob, contains(localHash));
    },
  );

  test('sliceRows يطابق دلالات LIMIT/OFFSET المستخدمة في readChunk', () {
    final rows = List<Map<String, Object?>>.generate(
      5,
      (i) => {'i': i},
    );
    expect(sliceRows(rows, 2, 0).map((r) => r['i']), [0, 1]);
    expect(sliceRows(rows, 2, 2).map((r) => r['i']), [2, 3]);
    expect(sliceRows(rows, 2, 4).map((r) => r['i']), [4]);
    expect(sliceRows(rows, 10, 0), hasLength(5));
    expect(sliceRows(rows, 2, 5), isEmpty, reason: 'OFFSET بعد النهاية');
    expect(sliceRows(rows, 0, 0), isEmpty, reason: 'LIMIT=0 آمن');
  });
}
