import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

/// Contract tests for financial links that must survive synchronization,
/// backup/restore, and a provider migration.
///
/// SQLite integer ids remain useful local foreign keys, but they are not
/// cross-device identity. Every relationship asserted here therefore needs a
/// persisted UUID alongside its local integer id.
void main() {
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
}
