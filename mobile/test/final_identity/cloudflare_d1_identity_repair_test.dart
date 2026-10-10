import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_identity_repair.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_identity_validator.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seedWithdrawals(int count) async {
    await db.customStatement('''
      INSERT INTO employees
        (id, local_uuid, name, basic_salary, status, created_at, updated_at, last_modified)
      VALUES (1, 'emp-a', 'Employee A', 1000, 'active', 1, 1, 1)
    ''');
    await db.customStatement('''
      INSERT INTO expenses
        (id, local_uuid, expense_type, related_id, description, amount, date,
         employee_uuid, withdrawal_uuid, created_at, updated_at, last_modified)
      VALUES (5, 'exp-a', 'سلفة', 1, 'Salary advance', 100, '2026-10-01',
              'emp-a', NULL, 1, 1, 1)
    ''');
    for (var i = 0; i < count; i++) {
      await db.customStatement(
        '''
        INSERT INTO salary_withdrawals
          (id, local_uuid, employee_id, employee_uuid, amount, withdraw_date,
           expense_id, expense_uuid, created_at, updated_at, last_modified)
        VALUES (?, ?, 1, 'emp-a', 100, '2026-10-01', 5, NULL, 1, 1, 1)
        ''',
        [7 + i, 'wd-${String.fromCharCode(97 + i)}'],
      );
    }
    if (count == 1) {
      await db.customStatement(
        "UPDATE expenses SET withdrawal_uuid = 'wd-a' WHERE id = 5",
      );
    }
  }

  const selected = {'employees', 'expenses', 'salary_withdrawals'};

  test('repairs a single unambiguous expense_uuid link', () async {
    await seedWithdrawals(1);

    final result = await CloudflareD1IdentityRepair.repair(
      db: db,
      selectedTables: selected,
    );

    final rows = await db.select(db.salaryWithdrawals).get();
    expect(result.linksRepaired, 1);
    expect(rows.single.expenseUuid, 'exp-a');
    expect(
      await CloudflareD1IdentityValidator.inspect(
        db: db,
        selectedTables: selected,
      ),
      isEmpty,
    );
  });

  test('skips ambiguous duplicate expense_id links without throwing', () async {
    await seedWithdrawals(2);

    final result = await CloudflareD1IdentityRepair.repair(
      db: db,
      selectedTables: selected,
    );

    final rows = await db.select(db.salaryWithdrawals).get();
    expect(result.linksRepaired, 0);
    expect(rows, hasLength(2));
    expect(rows.every((row) => row.expenseUuid == null), isTrue);
    final issues = await CloudflareD1IdentityValidator.inspect(
      db: db,
      selectedTables: selected,
    );
    expect(issues.join('\n'), contains('expense_uuid مفقود أو غير محسوم'));
  });

  test(
    'uses an exact withdrawal_uuid reverse link to resolve duplicates',
    () async {
      await seedWithdrawals(2);
      await db.customStatement(
        "UPDATE expenses SET withdrawal_uuid = 'wd-a' WHERE id = 5",
      );

      final result = await CloudflareD1IdentityRepair.repair(
        db: db,
        selectedTables: selected,
      );

      final rows = await db.select(db.salaryWithdrawals).get();
      final byUuid = {for (final row in rows) row.localUuid: row};
      expect(result.linksRepaired, 1);
      expect(byUuid['wd-a']!.expenseUuid, 'exp-a');
      expect(byUuid['wd-b']!.expenseUuid, isNull);
      expect(
        await CloudflareD1IdentityValidator.inspect(
          db: db,
          selectedTables: selected,
        ),
        isNotEmpty,
      );
    },
  );
}
