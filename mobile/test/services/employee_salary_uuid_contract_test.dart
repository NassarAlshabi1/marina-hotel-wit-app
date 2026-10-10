// ignore_for_file: lines_longer_than_80_chars
import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/salary_advance_installments_service.dart';
import 'package:marina_hotel_mobile/services/salary_entitlement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalaryEntitlementService entitlementService;
  late ExpensesRepository expensesRepository;
  late SalaryWithdrawalsRepository withdrawalsRepository;
  late SalaryAdvanceInstallmentsService installmentsService;
  const nowEpoch = 1791500000;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    entitlementService = SalaryEntitlementService(db);
    expensesRepository = ExpensesRepository(db);
    withdrawalsRepository = SalaryWithdrawalsRepository(db);
    installmentsService = SalaryAdvanceInstallmentsService(
      db,
      expensesRepository,
      withdrawalsRepository,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<Employee> seedEmployee({
    required String uuid,
    required String name,
    required String hireDate,
  }) async {
    final id = await db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: name,
            localUuid: uuid,
            basicSalary: 500,
            status: 'active',
            hireDate: d.Value(hireDate),
            createdAt: nowEpoch,
            updatedAt: nowEpoch,
            lastModified: nowEpoch,
          ),
        );
    return (db.select(db.employees)..where((e) => e.id.equals(id))).getSingle();
  }

  Future<int> seedExpense({
    required String uuid,
    required int relatedId,
    required String employeeUuid,
    required String type,
    required double amount,
    required String date,
  }) {
    return db
        .into(db.expenses)
        .insert(
          ExpensesCompanion(
            localUuid: d.Value(uuid),
            expenseType: d.Value(type),
            relatedId: d.Value(relatedId),
            employeeUuid: d.Value(employeeUuid),
            description: const d.Value('اختبار UUID'),
            amount: d.Value(amount),
            date: d.Value(date),
            hotelDayKey: d.Value(date),
            createdAt: const d.Value(nowEpoch),
            updatedAt: const d.Value(nowEpoch),
            lastModified: const d.Value(nowEpoch),
          ),
        );
  }

  Future<Map<String, dynamic>> outboxPayload(
    String entity,
    String uuid,
  ) async {
    final rows =
        await (db.select(db.outbox)..where(
              (o) => o.entity.equals(entity) & o.localUuid.equals(uuid),
            ))
            .get();
    expect(rows, hasLength(1));
    return jsonDecode(rows.single.payload) as Map<String, dynamic>;
  }

  test('الاستحقاق والدورة يتبعان employee_uuid عند اختلاف related_id', () async {
    final employeeA = await seedEmployee(
      uuid: 'employee-uuid-A',
      name: 'أ',
      hireDate: '2025-10-01',
    );
    final employeeB = await seedEmployee(
      uuid: 'employee-uuid-B',
      name: 'ب',
      hireDate: '2025-10-01',
    );
    final currentCycleStart =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-01';

    // related_id يخص ب محلياً، لكن employee_uuid يثبت أن المصروف للموظف أ.
    await seedExpense(
      uuid: 'salary-expense-A',
      relatedId: employeeB.id,
      employeeUuid: employeeA.localUuid,
      type: 'سحب راتب',
      amount: 250,
      date: currentCycleStart,
    );

    final entitlementA = await entitlementService.calculateEmployeeEntitlement(
      employeeA,
    );
    final entitlementB = await entitlementService.calculateEmployeeEntitlement(
      employeeB,
    );
    expect(entitlementA.totalWithdrawals, 250);
    expect(entitlementB.totalWithdrawals, 0);

    final cycleA = await entitlementService.calculateCurrentCycle(employeeA);
    final cycleB = await entitlementService.calculateCurrentCycle(employeeB);
    expect(cycleA.totalWithdrawals, 250);
    expect(cycleB.totalWithdrawals, 0);
  });

  test(
    'سجل الترحيل المملوك بـ UUID لا ينسخ أو يظهر لموظف صاحب رقم متصادم',
    () async {
      final employeeA = await seedEmployee(
        uuid: 'employee-carry-A',
        name: 'أ',
        hireDate: '2026-09-01',
      );
      final employeeB = await seedEmployee(
        uuid: 'employee-carry-B',
        name: 'ب',
        hireDate: '2026-09-01',
      );
      await seedExpense(
        uuid: 'over-limit-expense-A',
        relatedId: employeeB.id,
        employeeUuid: employeeA.localUuid,
        type: 'سحب راتب',
        amount: 600,
        date: '2026-09-10',
      );
      await db
          .into(db.salaryCarryOverLogs)
          .insert(
            SalaryCarryOverLogsCompanion.insert(
              employeeId: employeeB.id,
              employeeUuid: d.Value(employeeA.localUuid),
              amount: 100,
              previousCycleStart: '2026-09-01',
              previousCycleEnd: '2026-09-30',
              newCycleStart: '2026-10-01',
              newCycleEnd: '2026-10-31',
              reason: 'ترحيل اختبار UUID',
              carriedAt: nowEpoch,
              localUuid: 'carry-over-A',
              createdAt: nowEpoch,
              updatedAt: nowEpoch,
              lastModified: nowEpoch,
            ),
          );

      final cycleA = await entitlementService.calculateCurrentCycle(employeeA);
      final cycleB = await entitlementService.calculateCurrentCycle(employeeB);
      expect(cycleA.carryOverLogs.map((e) => e.localUuid), ['carry-over-A']);
      expect(cycleB.carryOverLogs, isEmpty);
      final logs = await db.select(db.salaryCarryOverLogs).get();
      expect(logs.where((e) => e.deletedAt == null), hasLength(1));
    },
  );

  test(
    'السلفة والأقساط تنشئ مصروفات وسحوبات outbox بعلاقات UUID كاملة',
    () async {
      final employee = await seedEmployee(
        uuid: 'employee-installments-A',
        name: 'أ',
        hireDate: '2025-10-01',
      );
      await installmentsService.createInstallmentAdvance(
        employeeId: employee.id,
        totalAmount: 300,
        advanceDate: '2026-10-01',
        description: 'سلفة اختبار',
        installments: 2,
      );

      final expenses = await db.select(db.expenses).get();
      expect(expenses, hasLength(3));
      expect(
        expenses.every((e) => e.employeeUuid == employee.localUuid),
        isTrue,
      );
      for (final expense in expenses) {
        final payload = await outboxPayload('expenses', expense.localUuid);
        expect(payload['employeeUuid'], employee.localUuid);
        expect(payload['localUuid'], expense.localUuid);
        expect(payload['withdrawalUuid'], isNotEmpty);
        expect(payload['lastModified'], expense.lastModified);
      }

      final withdrawals = await db.select(db.salaryWithdrawals).get();
      expect(withdrawals, hasLength(3));
      for (final withdrawal in withdrawals) {
        expect(withdrawal.localUuid, isNotEmpty);
        expect(withdrawal.employeeUuid, employee.localUuid);
        expect(withdrawal.expenseUuid, isNotEmpty);
        final payload = await outboxPayload(
          'salary_withdrawals',
          withdrawal.localUuid,
        );
        expect(payload['employeeUuid'], employee.localUuid);
        expect(payload['expenseUuid'], withdrawal.expenseUuid);
      }
    },
  );
}
