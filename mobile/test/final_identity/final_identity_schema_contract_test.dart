import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<List<Map<String, dynamic>>> indexes(String table) async =>
      (await db.customSelect("PRAGMA index_list('$table')").get())
          .map((r) => r.data)
          .toList();

  test('all synchronised identity tables expose UNIQUE local_uuid', () async {
    for (final table in const [
      'employees',
      'expenses',
      'salary_withdrawals',
      'salary_cycles',
      'salary_payments',
      'salary_carry_over_logs',
    ]) {
      final rows = await indexes(table);
      var found = false;
      for (final row in rows) {
        if (row['unique'] != 1) continue;
        final name = row['name']?.toString();
        if (name == null) continue;
        final cols = await db.customSelect(
          "PRAGMA index_info('${name.replaceAll("'", "''")}')",
        ).get();
        if (cols.length == 1 && cols.first.data['name'] == 'local_uuid') {
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: '$table must have UNIQUE(local_uuid)');
    }
  });

  test('salary_withdrawals has partial UNIQUE expense_uuid index', () async {
    final rows = await indexes('salary_withdrawals');
    final target = rows.where(
      (r) => r['name'] == 'ux_salary_withdrawals_expense_uuid_active',
    );
    expect(target, isNotEmpty);
    expect(target.first['unique'], 1);

    final sql = await db.customSelect(
      "SELECT sql FROM sqlite_master WHERE type='index' AND name='ux_salary_withdrawals_expense_uuid_active'",
    ).getSingle();
    final ddl = (sql.data['sql'] as String).toLowerCase();
    expect(ddl, contains('unique index'));
    expect(ddl, contains('expense_uuid'));
    expect(ddl, contains('where'));
    expect(ddl, contains('deleted_at is null'));
  });
}
