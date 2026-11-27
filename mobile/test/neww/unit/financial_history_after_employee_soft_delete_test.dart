import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/employee_financial_report_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late EmployeeFinancialReportRepository reports;

  const employeeUuid = 'former-employee-uuid';
  const reportDate = '2026-01-15';

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    reports = EmployeeFinancialReportRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'حذف الموظف ناعماً لا يخفي حركاته المالية التاريخية من التقارير',
    () async {
      final employeeId = await database
          .into(database.employees)
          .insert(
            const EmployeesCompanion(
              name: d.Value('موظف سابق'),
              basicSalary: d.Value(1000),
              status: d.Value('terminated'),
              hireDate: d.Value('2025-01-01'),
              localUuid: d.Value(employeeUuid),
              createdAt: d.Value(1000),
              updatedAt: d.Value(1000),
              lastModified: d.Value(1000),
            ),
          );

      await database
          .into(database.expenses)
          .insert(
            ExpensesCompanion(
              localUuid: const d.Value('historical-salary-expense'),
              employeeUuid: const d.Value(employeeUuid),
              relatedId: d.Value(employeeId),
              expenseType: const d.Value('سحب راتب'),
              description: const d.Value('مصروف راتب تاريخي'),
              amount: const d.Value(50),
              date: const d.Value(reportDate),
              hotelDayKey: const d.Value(reportDate),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
            ),
          );
      await database
          .into(database.expenses)
          .insert(
            const ExpensesCompanion(
              localUuid: d.Value('individually-deleted-expense'),
              employeeUuid: d.Value(employeeUuid),
              expenseType: d.Value('سحب راتب'),
              description: d.Value('مصروف محذوف ناعماً'),
              amount: d.Value(500),
              date: d.Value(reportDate),
              hotelDayKey: d.Value(reportDate),
              deletedAt: d.Value(1500),
              createdAt: d.Value(1000),
              updatedAt: d.Value(1500),
              lastModified: d.Value(1500),
            ),
          );

      await database
          .into(database.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion(
              localUuid: const d.Value('historical-direct-withdrawal'),
              employeeId: d.Value(employeeId),
              employeeUuid: const d.Value(employeeUuid),
              amount: const d.Value(25),
              withdrawDate: const d.Value(reportDate),
              hotelDayKey: const d.Value(reportDate),
              withdrawalType: const d.Value('سحب راتب'),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
            ),
          );
      await database
          .into(database.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion(
              localUuid: const d.Value('individually-deleted-withdrawal'),
              employeeId: d.Value(employeeId),
              employeeUuid: const d.Value(employeeUuid),
              amount: const d.Value(500),
              withdrawDate: const d.Value(reportDate),
              hotelDayKey: const d.Value(reportDate),
              withdrawalType: const d.Value('سحب راتب'),
              deletedAt: const d.Value(1500),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1500),
              lastModified: const d.Value(1500),
            ),
          );

      final cycleId = await database
          .into(database.salaryCycles)
          .insert(
            SalaryCyclesCompanion(
              localUuid: const d.Value('historical-salary-cycle'),
              employeeId: d.Value(employeeId),
              employeeUuid: const d.Value(employeeUuid),
              cycleKey: const d.Value('2026-01'),
              hotelDayStart: const d.Value('2026-01-01'),
              expectedAmount: const d.Value(100),
              actualPaid: const d.Value(25),
              remainingAmount: const d.Value(75),
              status: const d.Value('open'),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
            ),
          );
      await database
          .into(database.salaryCycles)
          .insert(
            SalaryCyclesCompanion(
              localUuid: const d.Value('individually-deleted-salary-cycle'),
              employeeId: d.Value(employeeId),
              employeeUuid: const d.Value(employeeUuid),
              cycleKey: const d.Value('2026-01-deleted'),
              hotelDayStart: const d.Value('2026-01-01'),
              expectedAmount: const d.Value(500),
              actualPaid: const d.Value(0),
              remainingAmount: const d.Value(500),
              status: const d.Value('open'),
              deletedAt: const d.Value(1500),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1500),
              lastModified: const d.Value(1500),
            ),
          );

      await database
          .into(database.salaryPayments)
          .insert(
            SalaryPaymentsCompanion(
              localUuid: const d.Value('historical-salary-payment'),
              cycleId: d.Value(cycleId),
              employeeUuid: const d.Value(employeeUuid),
              cycleUuid: const d.Value('historical-salary-cycle'),
              amount: const d.Value(25),
              paymentDateIso: const d.Value(reportDate),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
            ),
          );
      await database
          .into(database.salaryPayments)
          .insert(
            SalaryPaymentsCompanion(
              localUuid: const d.Value('individually-deleted-salary-payment'),
              cycleId: d.Value(cycleId),
              employeeUuid: const d.Value(employeeUuid),
              cycleUuid: const d.Value('historical-salary-cycle'),
              amount: const d.Value(500),
              paymentDateIso: const d.Value(reportDate),
              deletedAt: const d.Value(1500),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1500),
              lastModified: const d.Value(1500),
            ),
          );

      await (database.update(database.employees)
            ..where((employee) => employee.id.equals(employeeId)))
          .write(const EmployeesCompanion(deletedAt: d.Value(2000)));

      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 2, 1);
      final account = await reports.buildEmployeeAccountStatement(
        employeeUuid: employeeUuid,
        fromDate: from,
        toDate: to,
      );
      final expenses = await reports.buildExpensesByEmployeeReport(
        employeeUuid: employeeUuid,
        fromDate: from,
        toDate: to,
      );
      final withdrawals = await reports.buildWithdrawalsReport(
        employeeUuid: employeeUuid,
        fromDate: from,
        toDate: to,
      );
      final cycles = await reports.buildSalaryCyclesReport(
        employeeUuid: employeeUuid,
        fromDate: from,
        toDate: to,
      );

      expect(account.movements, hasLength(2));
      expect(expenses.expenses, hasLength(1));
      expect(expenses.total, 50);
      expect(withdrawals.directWithdrawals, hasLength(1));
      expect(withdrawals.directTotal, 25);
      expect(cycles.cycles, hasLength(1));
      expect(cycles.cycles.single.payments, hasLength(1));
      expect(cycles.totalPaid, 25);
    },
  );
}
