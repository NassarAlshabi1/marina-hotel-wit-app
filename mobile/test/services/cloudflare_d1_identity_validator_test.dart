import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_identity_validator.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalaryWithdrawalsRepository salaryRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    salaryRepo = SalaryWithdrawalsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertEmployee(String uuid) => db
      .into(db.employees)
      .insert(
        EmployeesCompanion(
          localUuid: drift.Value(uuid),
          name: const drift.Value('موظف اختبار'),
          position: const drift.Value('موظف'),
          status: const drift.Value('active'),
          basicSalary: const drift.Value(5000),
          createdAt: const drift.Value(1),
          updatedAt: const drift.Value(1),
          lastModified: const drift.Value(1),
          createdAtEpoch: const drift.Value(1),
          lastModifiedEpoch: const drift.Value(1),
        ),
      );

  Future<int> insertSalaryExpense({
    required String uuid,
    int? employeeId,
    String? employeeUuid,
  }) => db
      .into(db.expenses)
      .insert(
        ExpensesCompanion(
          localUuid: drift.Value(uuid),
          expenseType: const drift.Value('رواتب'),
          relatedId: drift.Value(employeeId),
          employeeUuid: drift.Value(employeeUuid),
          description: const drift.Value('اختبار راتب'),
          amount: const drift.Value(1000),
          date: const drift.Value('2026-10-09'),
          hotelDayKey: const drift.Value('2026-10-09'),
          createdAt: const drift.Value(1),
          updatedAt: const drift.Value(1),
          lastModified: const drift.Value(1),
          createdAtEpoch: const drift.Value(1),
          lastModifiedEpoch: const drift.Value(1),
        ),
      );

  const fullFinancialTables = <String>{
    'employees',
    'expenses',
    'salary_withdrawals',
  };

  test(
    'first upload accepts a consistent employee/expense/withdrawal UUID graph',
    () async {
      final employeeId = await insertEmployee('employee-uuid-a');
      final expenseId = await insertSalaryExpense(
        uuid: 'expense-uuid-a',
        employeeId: employeeId,
        employeeUuid: 'employee-uuid-a',
      );

      await salaryRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: employeeId,
        action: 'سحب راتب',
        amount: 1000,
        date: '2026-10-09',
        hotelDayKey: '2026-10-09',
      );

      final issues = await CloudflareD1IdentityValidator.inspect(
        db: db,
        selectedTables: fullFinancialTables,
      );
      expect(issues, isEmpty);
    },
  );

  test(
    'salary expense without employee_uuid is blocked before upload',
    () async {
      await insertEmployee('employee-uuid-b');
      await insertSalaryExpense(uuid: 'expense-uuid-b');

      final issues = await CloudflareD1IdentityValidator.inspect(
        db: db,
        selectedTables: const {'employees', 'expenses'},
      );
      expect(issues.join('\n'), contains('employee_uuid'));
    },
  );

  test('mismatched withdrawal_uuid/expense_uuid relation is blocked', () async {
    final employeeId = await insertEmployee('employee-uuid-c');
    final expenseId = await insertSalaryExpense(
      uuid: 'expense-uuid-c',
      employeeId: employeeId,
      employeeUuid: 'employee-uuid-c',
    );
    await salaryRepo.saveFromExpense(
      expenseId: expenseId,
      employeeId: employeeId,
      action: 'سحب راتب',
      amount: 1000,
      date: '2026-10-09',
    );
    await db.customStatement(
      'UPDATE expenses SET withdrawal_uuid = ? WHERE id = ?',
      ['wrong-withdrawal-uuid', expenseId],
    );

    final issues = await CloudflareD1IdentityValidator.inspect(
      db: db,
      selectedTables: fullFinancialTables,
    );
    expect(issues.join('\n'), contains('withdrawal_uuid'));
  });

  test(
    'salary tables require employees in the same first-upload selection',
    () async {
      final employeeId = await insertEmployee('employee-uuid-d');
      final expenseId = await insertSalaryExpense(
        uuid: 'expense-uuid-d',
        employeeId: employeeId,
        employeeUuid: 'employee-uuid-d',
      );
      await salaryRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: employeeId,
        action: 'سحب راتب',
        amount: 1000,
        date: '2026-10-09',
      );

      final issues = await CloudflareD1IdentityValidator.inspect(
        db: db,
        selectedTables: const {'expenses', 'salary_withdrawals'},
      );
      expect(issues.join('\n'), contains('اختر employees'));
    },
  );
}
