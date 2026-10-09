import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  test('fresh schema has all salary employee UUID indexes', () async {
    final db = TestDatabase.create();
    addTearDown(db.close);

    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE 'idx_salary_%_employee_uuid' ORDER BY name",
        )
        .get();
    expect(
      indexes.map((row) => row.read<String>('name')).toSet(),
      containsAll(<String>{
        'idx_salary_withdrawals_employee_uuid',
        'idx_salary_cycles_employee_uuid',
        'idx_salary_payments_employee_uuid',
      }),
    );

    final expenseLinkIndex = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_salary_withdrawals_active_expense'",
        )
        .get();
    expect(expenseLinkIndex, hasLength(1));
    expect(
      expenseLinkIndex.single.read<String>('sql'),
      contains('WHERE deleted_at IS NULL AND expense_uuid IS NOT NULL'),
      reason:
          'active expense_uuid must be unique without constraining NULL links',
    );

    for (final table in <String>[
      'salary_withdrawals',
      'salary_cycles',
      'salary_payments',
    ]) {
      final plan = await db
          .customSelect(
            "EXPLAIN QUERY PLAN SELECT * FROM $table WHERE employee_uuid = 'missing'",
          )
          .get();
      expect(
        plan.map((row) => row.data.values.join(' ')).join(' '),
        contains('employee_uuid'),
        reason: '$table must use its employee_uuid index',
      );
    }
  });
}
