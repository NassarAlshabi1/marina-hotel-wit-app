// test/unit/cf_sync_uuid_cache_quarantine_test.dart
//
// ✅ اختبارات انحدار إصلاحات 2026-10-05 (فجوات الفرع الثاني —
// feat/cloudflare-sync-execution):
//
//   أ) fk_rules: ذاكرة employee_uuid لسجلات ترحيل الراتب + ذاكرة
//      cycle_uuid لدفعات الدورة — والمفتاحان أعمدة حقيقية في مخطط
//      D1 الفعلي (worker/schema.sql) — عقد التطابق لا التمني.
//   ب) السحب عبر الأجهزة: صف ترحيل/دفعة بلا مؤشر رقمي محلول (رقم
//      محلي لجهاز المصدر) يُطبَّق على جهاز ناظر عبر ذاكرة UUID —
//      عبر applyPulledRecords الحقيقي (نفس نقطة الإنتاج).
//   ج) الحجر الصحي بدل التخطي الصامت: صف بلا local_uuid (كاتب
//      أجنبي) يُؤجَّل ويُعزل بعد العتبة بهوية مستقرة من id الصف
//      الخادمي — ولا صفان بلا uuid ينهاران على هوية واحدة.
//   د) عقد المنتج: حمولة الترحيل الحقيقية تحمل employeeUuid وتصل
//      السلك employee_uuid عبر buildPushOperation/PayloadNormalizer.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync/fk_rules.dart';
import 'package:marina_hotel_mobile/services/sync/payload_normalizer.dart';
import 'package:marina_hotel_mobile/services/sync/pull_quarantine.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── قراءة مخطط D1 الفعلي من worker/schema.sql ──────────────────

Map<String, Set<String>>? _d1Columns;

Map<String, Set<String>> _loadD1Columns() {
  if (_d1Columns != null) return _d1Columns!;
  final file = [
    for (final p in [
      '../worker/schema.sql',
      'worker/schema.sql',
      '../../worker/schema.sql',
    ])
      if (File(p).existsSync()) File(p),
  ].first;
  final tables = <String, Set<String>>{};
  String? current;
  for (final line in file.readAsLinesSync()) {
    final create = RegExp(
      r'CREATE TABLE IF NOT EXISTS (\w+)',
    ).firstMatch(line);
    if (create != null) {
      current = create.group(1)!;
      tables[current] = <String>{};
      continue;
    }
    if (current == null) continue;
    if (line.startsWith(')')) {
      current = null;
      continue;
    }
    if (line.isEmpty) continue;
    final l = line.trim();
    if (l.startsWith('--')) continue;
    final m = RegExp(r'^"?(\w+)"?\s+(TEXT|INTEGER|REAL|BLOB)').firstMatch(l);
    if (m != null) tables[current]!.add(m.group(1)!);
  }
  return _d1Columns = tables;
}

// ─── صفوف السلك ─────────────────────────────────────────────────

Map<String, dynamic> _syncFields(String uuid, int updatedAt) => {
  'id': 900000,
  'local_uuid': uuid,
  'created_at': updatedAt,
  'updated_at': updatedAt,
  'last_modified': updatedAt,
  'created_at_epoch': 0,
  'last_modified_epoch': 0,
  'version': 1,
  'origin': 'cloud',
  'vector_clock': '{}',
  'device_id': 'source-device',
};

Map<String, dynamic> _carryOverRow({
  required String uuid,
  required int employeeId,
  String? employeeUuid,
  int id = 424242,
}) => {
  ..._syncFields(uuid, 1700000500),
  'id': id,
  'employee_id': employeeId,
  if (employeeUuid != null) 'employee_uuid': employeeUuid,
  'amount': 250.0,
  'previous_cycle_start': '2026-08-01',
  'previous_cycle_end': '2026-08-31',
  'new_cycle_start': '2026-09-01',
  'new_cycle_end': '2026-09-30',
  'reason': 'ترحيل تلقائي — اختبار',
  'carried_at': 1700000400,
};

Map<String, dynamic> _paymentRow({
  required String uuid,
  required int cycleId,
  String? cycleUuid,
  String? employeeUuid,
}) => {
  ..._syncFields(uuid, 1700000600),
  'id': 424243,
  'cycle_id': cycleId,
  if (cycleUuid != null) 'cycle_uuid': cycleUuid,
  if (employeeUuid != null) 'employee_uuid': employeeUuid,
  'amount': 500,
  'hotel_day_key': '2026-09-05',
  'payment_date_iso': '2026-09-05',
  'method': 'cash',
  'is_auto_generated': 0,
};

Map<String, dynamic> _roomRowNoUuid({
  required int id,
  required String number,
}) => {
  // ✅ مقصود: بلا local_uuid — كاتب أجنبي/نسخة استشارية بلا هوية.
  'id': id,
  'created_at': 1700000700,
  'updated_at': 1700000700,
  'last_modified': 1700000700,
  'created_at_epoch': 0,
  'last_modified_epoch': 0,
  'version': 1,
  'origin': 'cloud',
  'vector_clock': '{}',
  'device_id': 'foreign-tool',
  'room_number': number,
  'type': 'double',
  'price': 100.0,
  'status': 'available',
  'cleaning_status': 'clean',
  'requires_maintenance': 0,
};

Map<String, dynamic> _emptyPullPage() => {
  'changes': <dynamic>[],
  'cursor': '0',
  'has_more': false,
  'errors': <dynamic>[],
};

class _FakeClient extends http.BaseClient {
  _FakeClient({this.pullHandler});

  final Map<String, dynamic> Function(http.BaseRequest request)? pullHandler;

  int pullCalls = 0;

  http.StreamedResponse _json(Map<String, dynamic> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        200,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/api/auth/login')) {
      return _json({
        'token': 'fake-token',
        'user': {'id': 'u1', 'username': 'sync_service', 'role': 'admin'},
      });
    }
    if (request.method == 'POST' && path.endsWith('/api/sync/push')) {
      return _json({'results': <dynamic>[]});
    }
    if (request.method == 'GET' && path.endsWith('/api/sync/pull')) {
      pullCalls++;
      return _json(pullHandler?.call(request) ?? _emptyPullPage());
    }
    throw StateError('unexpected ${request.method} $path');
  }
}

// ─── الاختبارات ─────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
    });
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<CloudflareSyncManager> makeManager(_FakeClient client) async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'test-token',
      deviceId: 'uuid-cache-device',
    );
    return manager;
  }

  Future<int> seedEmployeeAndCycle() async {
    final empId = await db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: 'عمار الاختبار',
            basicSalary: 1000.0,
            status: 'active',
            localUuid: 'emp-uuid-fix',
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
          ),
        );
    await db
        .into(db.salaryCycles)
        .insert(
          SalaryCyclesCompanion.insert(
            employeeId: empId,
            cycleKey: '2026-09',
            localUuid: 'cycle-uuid-fix',
            createdAt: 1700000100,
            updatedAt: 1700000100,
            lastModified: 1700000100,
            employeeUuid: const Value('emp-uuid-fix'),
          ),
        );
    return empId;
  }

  // ─── أ) عقد fk_rules + مخطط D1 ────────────────────────────────

  test(
    'أ-1: ذاكرة employee_uuid لسجلات الترحيل و cycle_uuid لدفعات الدورة معرّفة في fk_rules',
    () {
      final carry = fkRulesByEntity['salary_carry_over_logs']!.singleWhere(
        (r) => r.column == 'employee_id',
      );
      expect(carry.uuidCacheColumn, 'employee_uuid');

      final pay = fkRulesByEntity['salary_payments']!.singleWhere(
        (r) => r.column == 'cycle_id',
      );
      expect(pay.uuidCacheColumn, 'cycle_uuid');
    },
  );

  test(
    'أ-2: العمودان موجودان في مخطط D1 الفعلي (worker/schema.sql) — عقد التطابق',
    () {
      final schema = _loadD1Columns();
      expect(
        schema['salary_carry_over_logs'],
        contains('employee_uuid'),
        reason:
            'fk_rules يعتمد employee_uuid كذاكرة حل — يجب أن يكون عموداً '
            'حقيقياً في D1 (migration 0011) وإلا فالحل فاشل دائماً',
      );
      expect(
        schema['salary_payments'],
        contains('cycle_uuid'),
        reason:
            'fk_rules يعتمد cycle_uuid كذاكرة حل — يجب أن يكون عموداً '
            'حقيقياً في D1 (migration 0011) وإلا فالحل فاشل دائماً',
      );
    },
  );

  // ─── ب) الحل عبر الأجهزة على قاعدة ناظرة ─────────────────────

  test(
    'ب-1: سجل ترحيل بـ employee_uuid يُطبَّق على جهاز ناظر رغم employee_id أجنبي',
    () async {
      final empId = await seedEmployeeAndCycle();
      final client = _FakeClient(
        pullHandler: (request) => {
          'changes': [
            _carryOverRow(
              uuid: 'carry-remote-1',
              employeeId: 987654, // رقم محلي لجهاز المصدر — لا يحل رقمياً
              employeeUuid: 'emp-uuid-fix', // ذاكرة UUID — تحل
            ),
          ],
          'cursor': '1700000500',
          'has_more': false,
          'errors': <dynamic>[],
        },
      );
      final manager = await makeManager(client);

      final report = await manager.applyPulledRecords([
        (
          entity: 'salary_carry_over_logs',
          record: _carryOverRow(
            uuid: 'carry-remote-1',
            employeeId: 987654,
            employeeUuid: 'emp-uuid-fix',
          ),
        ),
      ]);

      expect(report.errors, isEmpty, reason: 'لا فشل تطبيق حقيقي');
      final row = await db
          .customSelect(
            'SELECT employee_id, employee_uuid FROM salary_carry_over_logs '
            'WHERE local_uuid = ?',
            variables: [const Variable<String>('carry-remote-1')],
          )
          .getSingleOrNull();
      expect(row, isNotNull, reason: 'الصف أُطبق — لم يُؤجَّل ولا يُحجر');
      expect(
        row!.data['employee_id'],
        empId,
        reason: 'ذاكرة employee_uuid حلّت employee_id الأجنبي للموظف المحلي',
      );
      expect(row.data['employee_uuid'], 'emp-uuid-fix');
      expect(empId, isNot(987654));
    },
  );

  test(
    'ب-2: دفعة راتب بـ cycle_uuid تُطبَّق على جهاز ناظر رغم cycle_id أجنبي',
    () async {
      await seedEmployeeAndCycle();
      final client = _FakeClient();
      final manager = await makeManager(client);

      final report = await manager.applyPulledRecords([
        (
          entity: 'salary_payments',
          record: _paymentRow(
            uuid: 'pay-remote-1',
            cycleId: 765432, // رقم محلي لجهاز المصدر
            cycleUuid: 'cycle-uuid-fix', // ذاكرة UUID للدورة — تحل
            employeeUuid: 'emp-uuid-fix',
          ),
        ),
      ]);

      expect(report.errors, isEmpty);
      final row = await db
          .customSelect(
            'SELECT cycle_id, cycle_uuid, employee_uuid FROM salary_payments '
            'WHERE local_uuid = ?',
            variables: [const Variable<String>('pay-remote-1')],
          )
          .getSingleOrNull();
      expect(row, isNotNull, reason: 'الدفعة أُطبقت — لم تعد تتيمة بنيوياً');
      // cycle_id المحلول يشير للدورة المحلية الفعلية (لا الرقم الأجنبي):
      final cycle = await db
          .customSelect(
            'SELECT id FROM salary_cycles WHERE local_uuid = ?',
            variables: [const Variable<String>('cycle-uuid-fix')],
          )
          .getSingle();
      expect(
        row!.data['cycle_id'],
        cycle.data['id'],
        reason: 'ذاكرة cycle_uuid حلّت cycle_id الأجنبي للدورة المحلية',
      );
      expect(row.data['cycle_id'], isNot(765432));
      expect(row.data['cycle_uuid'], 'cycle-uuid-fix');
      expect(row.data['employee_uuid'], 'emp-uuid-fix');
    },
  );

  // ─── ج) الحجر الصحي بدل التخطي الصامت ─────────────────────────

  test(
    'ج-1: صف بلا local_uuid يُؤجَّل (لا يُطبَّق ولا يضيع صمتاً) وهويتان بلا uuid متمايزتان',
    () async {
      final manager = await makeManager(_FakeClient());

      final records = [
        (
          entity: 'rooms',
          record: _roomRowNoUuid(id: 4242, number: 'NOUUID-1'),
        ),
        (
          entity: 'rooms',
          record: _roomRowNoUuid(id: 4243, number: 'NOUUID-2'),
        ),
      ];
      final report = await manager.applyPulledRecords(records);

      // العقد الجديد: مؤجَّل — يمر سلّم الانتظار/الحجر، لا تخطٍّ صامت.
      expect(report.deferredCount, 2);
      final count = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM rooms WHERE room_number LIKE 'NOUUID-%'",
          )
          .getSingle();
      expect(count.data['n'], 0, reason: 'الصفوف بلا هوية لا تُدرج محلياً');

      // الهويات مستقرة ومتمايزة (كانت ستنهار على 'rooms/null').
      final ids = records
          .map((r) => PullQuarantine.identityForRecord(r.entity, r.record))
          .toSet();
      expect(
        ids.length,
        2,
        reason: 'كل صف بلا uuid له هوية من id الصف الخادمي',
      );
      expect(ids.first, contains('#no-uuid/'));
    },
  );

  test(
    'ج-2: الدورات الثلاث تعزل الصفين بلا local_uuid والمؤشر يتقدم — لا صف يضيع من المحاسبة',
    () async {
      final client = _FakeClient(
        pullHandler: (request) => {
          'changes': [
            _roomRowNoUuid(id: 4242, number: 'NOUUID-1'),
            _roomRowNoUuid(id: 4243, number: 'NOUUID-2'),
          ],
          'cursor': '1700000700',
          'has_more': false,
          'errors': <dynamic>[],
        },
      );
      final manager = await makeManager(client);

      for (var cycle = 1; cycle <= 3; cycle++) {
        await manager.sync();
      }

      final prefs = await SharedPreferences.getInstance();
      final ledger = prefs.getString('cf_pull_quarantined_records') ?? '';
      expect(
        ledger,
        contains('#no-uuid/4242'),
        reason: 'الصف الأول معزول بهويته المستقرة (id الصف الخادمي)',
      );
      expect(
        ledger,
        contains('#no-uuid/4243'),
        reason: 'الصف الثاني معزول أيضاً — لا انهيار على هوية واحدة مشتركة',
      );
      expect(
        prefs.get('cf_last_pull_cursor'),
        1700000700,
        reason: 'المؤشر يتقدم — الحجر لا يجمّد السحب',
      );

      final count = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM rooms WHERE room_number LIKE 'NOUUID-%'",
          )
          .getSingle();
      expect(count.data['n'], 0);
    },
  );

  // ─── د) عقد المنتج: حمولة الترحيل تحمل employeeUuid ──────────

  test(
    'د-1: حمولة الترحيل عبر buildPushOperation تصل السلك employee_uuid وتلتزم عمود D1',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const carryUuid = 'carry-producer-1';
      await OutboxDao(db).merge(
        entity: 'salary_carry_over_logs',
        op: 'create',
        localUuid: carryUuid,
        clientTs: now,
        // نفس ما يبنيه SalaryEntitlementService.processAutoCarryOver
        // بعد إصلاح 2026-10-05 (employeeUuid مختوم من الموظف).
        payload: {
          'employeeId': 3,
          'employeeUuid': 'emp-uuid-fix',
          'amount': 250.0,
          'previousCycleStart': '2026-08-01',
          'previousCycleEnd': '2026-08-31',
          'newCycleStart': '2026-09-01',
          'newCycleEnd': '2026-09-30',
          'reason': 'ترحيل — عقد المنتج',
          'carriedAt': now,
        },
      );
      final items = await db
          .customSelect(
            "SELECT * FROM outbox WHERE local_uuid = '$carryUuid'",
          )
          .get();
      expect(items, hasLength(1));
      final item = await (db.select(
        db.outbox,
      )..where((o) => o.localUuid.equals(carryUuid))).getSingle();

      final op = await buildPushOperation(
        item,
        resolveRowVectorClock: (_, __) async => '{}',
      );
      final data = op['data'] as Map<String, dynamic>;

      // العقد: employee_uuid على السلك (snake_case) + عمود D1 موجود.
      expect(data['employee_uuid'], 'emp-uuid-fix');
      expect(
        data.containsKey('employeeUuid'),
        isFalse,
        reason: 'الحمولة تُطبَّع snake_case قبل الدفع',
      );
      final schema = _loadD1Columns();
      for (final key in data.keys) {
        if (key == 'vector_clock') continue;
        expect(
          schema['salary_carry_over_logs'],
          contains(key),
          reason: 'عمود السلك "$key" يجب أن يكون في مخطط D1 الفعلي',
        );
      }
    },
  );
}
