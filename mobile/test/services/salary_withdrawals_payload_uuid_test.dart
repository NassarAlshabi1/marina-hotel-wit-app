// ignore_for_file: lines_longer_than_80_chars
// ═══════════════════════════════════════════════════════════════
//  salary_withdrawals_payload_uuid_test.dart — 2026-09-10
//  عقد جذر «107 سجل محجوب: أب غير محلول»:
//  كل حمولة outbox لسحوبات الرواتب يجب أن تحمل employeeUuid
//  (مرجع الأب المستقر عبر الأجهزة) — employee_id الرقمي وحده
//  لا يحل خادمياً. الحالات: create/update/soft-delete/يتيم.
// ═══════════════════════════════════════════════════════════════
import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalaryWithdrawalsRepository swRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    swRepo = SalaryWithdrawalsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  int _empSeq = 0;

  Future<int> seedEmployee({String name = 'عمار الدبادي'}) async {
    _empSeq++;
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: name,
            localUuid: 'emp-test-uuid-$_empSeq',
            basicSalary: 500,
            status: 'active',
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
          ),
        );
  }

  Future<Map<String, dynamic>?> lastPayloadFor(
    String entity,
    String op,
  ) async {
    final rows =
        await (db.select(db.outbox)
              ..where(
                (t) => t.entity.equals(entity) & t.op.equals(op),
              )
              ..orderBy([(t) => d.OrderingTerm.desc(t.id)])
              ..limit(1))
            .get();
    if (rows.isEmpty) {
      return null;
    }
    return jsonDecode(rows.first.payload) as Map<String, dynamic>;
  }

  test('createFromExpense يحقن employeeUuid في حمولة create', () async {
    final empId = await seedEmployee();
    final emp = await (db.select(
      db.employees,
    )..where((t) => t.id.equals(empId))).getSingle();

    await swRepo.createFromExpense(
      expenseId: 101,
      employeeId: empId,
      reason: 'exp_101',
      amount: 50,
      date: '2026-09-10',
    );

    final payload = await lastPayloadFor('salary_withdrawals', 'create');
    expect(payload, isNotNull);
    expect(payload!['employeeId'], empId);
    expect(
      payload['employeeUuid'],
      emp.localUuid,
      reason: 'الحمولة يجب أن تحمل المرجع المستقر عبر الأجهزة',
    );
  });

  test('saveFromExpense (مسار الإنشاء) يحقن employeeUuid', () async {
    final empId = await seedEmployee();
    final emp = await (db.select(
      db.employees,
    )..where((t) => t.id.equals(empId))).getSingle();

    await swRepo.saveFromExpense(
      expenseId: 202,
      employeeId: empId,
      action: 'withdrawal',
      amount: 75,
      date: '2026-09-10',
      note: 'اختبار',
    );

    final payload = await lastPayloadFor('salary_withdrawals', 'create');
    expect(payload, isNotNull);
    expect(payload!['employeeUuid'], emp.localUuid);
  });

  test('saveFromExpense (مسار التحديث) يحقن employeeUuid', () async {
    final empId = await seedEmployee();
    final emp = await (db.select(
      db.employees,
    )..where((t) => t.id.equals(empId))).getSingle();

    await swRepo.saveFromExpense(
      expenseId: 303,
      employeeId: empId,
      action: 'withdrawal',
      amount: 30,
      date: '2026-09-10',
    );
    await swRepo.saveFromExpense(
      expenseId: 303,
      employeeId: empId,
      action: 'withdrawal',
      amount: 45,
      date: '2026-09-11',
    );

    final payload = await lastPayloadFor('salary_withdrawals', 'update');
    expect(payload, isNotNull);
    expect(payload!['employeeId'], empId);
    expect(payload['employeeUuid'], emp.localUuid);
  });

  test('deleteByExpenseId يحقن employeeUuid في حمولة soft-delete', () async {
    final empId = await seedEmployee();
    final emp = await (db.select(
      db.employees,
    )..where((t) => t.id.equals(empId))).getSingle();

    await swRepo.createFromExpense(
      expenseId: 404,
      employeeId: empId,
      reason: 'exp_404',
      amount: 20,
      date: '2026-09-10',
    );
    await swRepo.deleteByExpenseId(404);

    final payload = await lastPayloadFor('salary_withdrawals', 'update');
    expect(payload, isNotNull);
    expect(payload!['employeeUuid'], emp.localUuid);
    expect(payload['deletedAt'], isNotNull);
  });

  // ملاحظة (2026-09-10): لا يوجد اختبار لمسار «موظف مفقود» هنا — قيد
  // FOREIGN KEY المحلي يمنع أصلاً إنشاء سحوبة لموظف غير موجود محلياً.
  // السحوبات اليتيمة تنشأ فقط من سحب صفوف الخادم (أب محذوف خادمياً)
  // ويغطيها: employee_uuid=null في D1 (migration 0006) + الحجر التدريجي
  // في cloudflare_sync_manager (عتبة 3 دورات ثم عزل وتقدم المؤشر).
}
