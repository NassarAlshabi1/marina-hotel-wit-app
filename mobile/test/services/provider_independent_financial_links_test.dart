import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

/// Contract tests for financial links that must survive synchronization,
/// backup/restore, and a provider migration.
///
/// SQLite integer ids remain useful local foreign keys, but they are not
/// cross-device identity. Every relationship asserted here therefore needs a
/// persisted UUID alongside its local integer id.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Future<Set<String>> columns(String table) async {
    final db = TestDatabase.create();
    addTearDown(db.close);

    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  group('provider-independent financial relationship schema', () {
    test('withdrawal persists the expense UUID, not only expense_id', () async {
      expect(
        await columns('salary_withdrawals'),
        contains('expense_uuid'),
        reason:
            'expense_id is local to one SQLite database and cannot identify '
            'the mirrored expense on another device',
      );
    });

    test('expense persists the reverse withdrawal UUID', () async {
      expect(
        await columns('expenses'),
        contains('withdrawal_uuid'),
        reason:
            'the reverse UUID makes the one-to-one mirror relationship '
            'verifiable after restore and provider migration',
      );
    });

    test('salary payment persists its cycle UUID', () async {
      expect(
        await columns('salary_payments'),
        contains('cycle_uuid'),
        reason:
            'cycle_id is device-local; synthesizing cycle_local_uuid only '
            'during export does not preserve the relationship in the row',
      );
    });

    test('carry-over log persists its employee UUID', () async {
      expect(
        await columns('salary_carry_over_logs'),
        contains('employee_uuid'),
        reason:
            'employee_id can differ between devices and must not be used as '
            'portable employee identity',
      );
    });
  });
  test(
    'expense and withdrawal persist reciprocal UUIDs and Outbox links',
    () async {
      final db = TestDatabase.create();
      addTearDown(db.close);
      const now = 1700000000;

      final employeeId = await db
          .into(db.employees)
          .insert(
            EmployeesCompanion.insert(
              name: 'موظف اختبار',
              localUuid: 'employee-stable-uuid',
              basicSalary: 1000,
              status: 'active',
              createdAt: now,
              updatedAt: now,
              lastModified: now,
            ),
          );
      final expenseId = await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              localUuid: 'expense-stable-uuid',
              createdAt: now,
              updatedAt: now,
              lastModified: now,
              expenseType: 'سحب راتب',
              relatedId: d.Value(employeeId),
              employeeUuid: const d.Value('employee-stable-uuid'),
              description: 'سحب مستقل',
              amount: 125,
              date: '2026-10-06',
            ),
          );

      await SalaryWithdrawalsRepository(db).createFromExpense(
        expenseId: expenseId,
        employeeId: employeeId,
        reason: 'exp_$expenseId',
        amount: 125,
        date: '2026-10-06',
        notify: false,
      );

      final withdrawal = await db.select(db.salaryWithdrawals).getSingle();
      final expense = await db.select(db.expenses).getSingle();
      expect(withdrawal.expenseUuid, expense.localUuid);
      expect(expense.withdrawalUuid, withdrawal.localUuid);

      final outbox = await db.select(db.outbox).get();
      final withdrawalPayload =
          jsonDecode(
                outbox
                    .singleWhere((row) => row.entity == 'salary_withdrawals')
                    .payload,
              )
              as Map<String, dynamic>;
      final expensePayload =
          jsonDecode(
                outbox.singleWhere((row) => row.entity == 'expenses').payload,
              )
              as Map<String, dynamic>;
      expect(withdrawalPayload['expenseUuid'], expense.localUuid);
      expect(expensePayload['withdrawalUuid'], withdrawal.localUuid);
    },
  );
}
