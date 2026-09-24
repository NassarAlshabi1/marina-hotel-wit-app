// ═══════════════════════════════════════════════════════════════
//  expense_edit_dup_diagnostic_test.dart — (2026-09-25) Bug 2
//
//  العَرَض المُبلَّغ: بعد تعديل مبلغ مصروف (أو مصروف رواتب) يتكرر
//  السطر عند عرض التقرير.
//
//  منهجية «لا تخمين»: هذا الاختبار يشغّل دورة المستخدم الحقيقية
//  بالمستودعات الفعلية (ExpensesRepository + SalaryWithdrawalsRepository)
//  ثم يحاكي echo المزامنة (push → خادم وهمي → pull apply) كما يفعل
//  الـ worker حرفياً، وفي كل مرحلة يشغّل خوارزمية بناء صفوف تقرير
//  المصروفات (المصروفات + السحوبات اليتيمة) ويقيس عدد الصفوف.
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/screens/settings/error_tracker_screen.dart';
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خادم وهمي: يخزّن آخر data لكل local_uuid (مثل صفوف D1) ويرجعها echo
class _EchoServerClient extends http.BaseClient {
  final Map<String, Map<String, dynamic>> serverRows = {};
  final Map<String, String> entityByUuid = {};

  http.StreamedResponse _json(Map<String, dynamic> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        200,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/api/sync/push')) {
      final raw = request is http.Request
          ? request.bodyBytes
          : await (request as http.StreamedRequest).finalize().toBytes();
      final decoded = gzip.decode(raw);
      final body = jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
      final ops = body['operations'] as List;
      for (final op in ops) {
        final map = op as Map<String, dynamic>;
        final data = map['data'] as Map<String, dynamic>;
        final uuid = data['local_uuid'] as String?;
        final entity = map['entity'] as String?;
        if (uuid != null && entity != null) {
          serverRows[uuid] = Map<String, dynamic>.from(data);
          entityByUuid[uuid] = entity;
        }
      }
      return _json({
        'results': [
          for (final op in ops)
            {
              'idempotencyKey': (op as Map)['idempotencyKey'],
              'opStatus': 'applied',
              'localUuid': (op['data'] as Map)['local_uuid'],
            },
        ],
      });
    }
    if (request.method == 'GET' && path.endsWith('/api/sync/pull')) {
      return _json({
        'changes': <dynamic>[],
        'cursor': '0',
        'has_more': false,
        'errors': <dynamic>[],
      });
    }
    throw StateError('unexpected ${request.method} $path');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ExpensesRepository expensesRepo;
  late SalaryWithdrawalsRepository salaryRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
    });
    ErrorTrackerStore.instance.clear();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expensesRepo = ExpensesRepository(db);
    salaryRepo = SalaryWithdrawalsRepository(db);
  });

  tearDown(() async {
    CloudflareSyncManager.instance.reset();
    await db.close();
  });

  Future<CloudflareSyncManager> makeManager(_EchoServerClient client) async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'dup-test-token',
      deviceId: 'dup-test-device',
    );
    return manager;
  }

  Future<int> seedEmployee() {
    final now = Time.nowEpoch();
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion(
            localUuid: Value(IdGen.uuid()),
            name: const Value('موظف اختبار'),
            basicSalary: const Value(1000.0),
            status: const Value('نشط'),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ),
        );
  }

  /// خوارزمية صفوف تقرير المصروفات — نسخة وفية من
  /// expenses_report_screen: كل المصروفات + السحوبات اليتيمة فقط.
  Future<int> reportRowCount() async {
    final expenses = await (db.select(
      db.expenses,
    )..where((t) => t.deletedAt.isNull())).get();
    final withdrawals = await (db.select(
      db.salaryWithdrawals,
    )..where((t) => t.deletedAt.isNull())).get();

    final swExpenseId = <int, int>{};
    if (withdrawals.isNotEmpty) {
      final ids = withdrawals.map((w) => w.id).toList();
      final rows = await db
          .customSelect(
            'SELECT id, expense_id FROM salary_withdrawals '
            'WHERE id IN (${List.filled(ids.length, '?').join(',')})',
            variables: ids.map(Variable.withInt).toList(),
          )
          .get();
      for (final row in rows) {
        final raw = row.data['expense_id'];
        if (raw is int) swExpenseId[row.read<int>('id')] = raw;
      }
    }

    final addedExpenseIds = expenses.map((e) => e.id).toSet();
    var rows = expenses.length;
    for (final sw in withdrawals) {
      final isDirect = sw.reason?.startsWith('direct_withdrawal_') ?? false;
      if (isDirect) {
        rows++;
        continue;
      }
      final byColumn = swExpenseId[sw.id];
      var matched = byColumn != null && addedExpenseIds.contains(byColumn);
      if (!matched && sw.reason != null) {
        final match = RegExp(r'exp_(\d+)').firstMatch(sw.reason!);
        if (match != null) {
          final expId = int.tryParse(match.group(1)!);
          matched = expId != null && addedExpenseIds.contains(expId);
        }
      }
      if (!matched) rows++;
    }
    return rows;
  }

  test(
    'دورة المستخدم كاملة: إنشاء → تعديل → echo مزامنة — لا ازدواج',
    () async {
      final client = _EchoServerClient();
      final manager = await makeManager(client);

      final employeeId = await seedEmployee();
      final employee = await (db.select(
        db.employees,
      )..where((t) => t.id.equals(employeeId))).getSingle();

      // ─── 1) إنشاء مصروف راتب 100 (نفس مسار الشاشة) ───
      final expenseId = await expensesRepo.create(
        expenseType: 'سحب راتب',
        relatedId: employeeId,
        description: 'سحب راتب',
        amount: 100,
        date: '2026-09-25',
        hotelDayKey: '2026-09-25',
        employeeUuid: employee.localUuid,
      );
      await salaryRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: employeeId,
        action: 'سحب راتب',
        amount: 100,
        date: '2026-09-25',
        note: 'سحب راتب',
        hotelDayKey: '2026-09-25',
      );

      expect(await reportRowCount(), 1, reason: 'بعد الإنشاء: سطر واحد');
      expect(await _liveWithdrawals(db, expenseId), 1);

      // ─── 2) تعديل المبلغ 100 → 250 (نفس مسار الشاشة) ───
      await expensesRepo.update(
        expenseId,
        expenseType: 'سحب راتب',
        relatedId: employeeId,
        description: 'سحب راتب',
        amount: 250,
        date: '2026-09-25',
        hotelDayKey: '2026-09-25',
        employeeUuid: employee.localUuid,
      );
      await salaryRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: employeeId,
        action: 'سحب راتب',
        amount: 250,
        date: '2026-09-25',
        note: 'سحب راتب',
        hotelDayKey: '2026-09-25',
      );

      expect(await _liveExpenses(db), 1, reason: 'لا مصروف ثانٍ محلياً');
      expect(
        await _liveWithdrawals(db, expenseId),
        1,
        reason: 'لا سحوبة ثانية محلياً',
      );
      expect(
        await reportRowCount(),
        1,
        reason: 'التقرير بعد التعديل: سطر واحد',
      );

      // ─── 3) push ثم echo السحوبات كما يفعل الخادم ───
      await manager.pushLocalChanges();
      expect(
        client.serverRows.length,
        greaterThanOrEqualTo(2),
        reason: 'المصروف والسحوبة وصلتا الخادم',
      );

      await manager.applyPulledRecords([
        for (final entry in client.serverRows.entries)
          (
            entity: client.entityByUuid[entry.key]!,
            record: Map<String, dynamic>.of(entry.value),
          ),
      ]);

      expect(await _liveExpenses(db), 1, reason: 'بعد echo: لا مصروف ثانٍ');
      expect(
        await _liveWithdrawals(db, expenseId),
        1,
        reason: 'بعد echo: لا سحوبة ثانية',
      );
      expect(
        await reportRowCount(),
        1,
        reason: 'التقرير بعد المزامنة الكاملة: سطر واحد',
      );
    },
  );
}

Future<int> _liveExpenses(AppDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM expenses WHERE deleted_at IS NULL',
      )
      .getSingle();
  return rows.read<int>('c');
}

Future<int> _liveWithdrawals(AppDatabase db, int expenseId) async {
  final rows = await db
      .customSelect(
        'SELECT COUNT(*) AS c FROM salary_withdrawals '
        'WHERE deleted_at IS NULL AND (expense_id = ? OR reason LIKE ?)',
        variables: [
          Variable.withInt(expenseId),
          Variable.withString('%exp_$expenseId%'),
        ],
      )
      .getSingle();
  return rows.read<int>('c');
}
