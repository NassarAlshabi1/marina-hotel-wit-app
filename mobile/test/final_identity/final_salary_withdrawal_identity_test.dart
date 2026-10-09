import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ExpensesRepository expenses;
  late SalaryWithdrawalsRepository withdrawals;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expenses = ExpensesRepository(db);
    withdrawals = SalaryWithdrawalsRepository(db);
  });
  tearDown(() => db.close());

  Future<int> employee(String uuid, String name) => db.into(db.employees).insert(
        EmployeesCompanion(
          name: d.Value(name), basicSalary: const d.Value(1000),
          status: const d.Value('active'), localUuid: d.Value(uuid),
          createdAt: const d.Value(1), updatedAt: const d.Value(1),
          lastModified: const d.Value(1),
        ),
      );

  test('creating a salary expense persists employeeUuid and withdrawal linkage', () async {
    final emp = await employee('EMP-A', 'A');
    final expenseId = await expenses.create(
      expenseType: 'سحب راتب', description: 'test', amount: 500,
      date: '2026-10-01', relatedId: emp, employeeUuid: 'EMP-A',
    );
    await withdrawals.saveFromExpense(
      expenseId: expenseId, employeeId: emp, action: 'سحب راتب',
      amount: 500, date: '2026-10-01', hotelDayKey: '2026-10-01',
    );

    final e = await (db.select(db.expenses)..where((t) => t.id.equals(expenseId))).getSingle();
    expect(e.employeeUuid, 'EMP-A');

    final sw = await (db.select(db.salaryWithdrawals)..where((t) => t.expenseId.equals(expenseId))).getSingle();
    expect(sw.employeeUuid, 'EMP-A');
    expect(sw.expenseUuid, e.localUuid);
    expect(sw.expenseId, expenseId);
  });

  test('two employees with different UUIDs cannot share one active expense UUID', () async {
    final a = await employee('EMP-A', 'A');
    final b = await employee('EMP-B', 'B');
    final ea = await expenses.create(
      expenseType: 'سحب راتب', description: 'A', amount: 500,
      date: '2026-10-01', relatedId: a, employeeUuid: 'EMP-A',
    );
    final eb = await expenses.create(
      expenseType: 'سحب راتب', description: 'B', amount: 500,
      date: '2026-10-01', relatedId: b, employeeUuid: 'EMP-B',
    );
    await withdrawals.saveFromExpense(
      expenseId: ea, employeeId: a, action: 'سحب راتب', amount: 500, date: '2026-10-01',
    );
    await withdrawals.saveFromExpense(
      expenseId: eb, employeeId: b, action: 'سحب راتب', amount: 500, date: '2026-10-01',
    );

    final rows = await db.select(db.salaryWithdrawals).get();
    expect(rows.map((r) => r.employeeUuid).toSet(), {'EMP-A', 'EMP-B'});
    final expA = await (db.select(db.expenses)..where((t) => t.id.equals(ea))).getSingle();
    final expB = await (db.select(db.expenses)..where((t) => t.id.equals(eb))).getSingle();
    expect(rows.map((r) => r.expenseUuid).toSet(), {expA.localUuid, expB.localUuid});
  });
}
