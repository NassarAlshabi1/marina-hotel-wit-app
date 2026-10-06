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
