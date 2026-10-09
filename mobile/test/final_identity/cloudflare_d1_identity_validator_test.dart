import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_identity_validator.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seedValidMirror() async {
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
              'emp-a', 'wd-a', 1, 1, 1)
    ''');
    await db.customStatement('''
      INSERT INTO salary_withdrawals
        (id, local_uuid, employee_id, employee_uuid, amount, withdraw_date,
         expense_id, expense_uuid, created_at, updated_at, last_modified)
      VALUES (7, 'wd-a', 1, 'emp-a', 100, '2026-10-01', 5, 'exp-a', 1, 1, 1)
    ''');
  }

  const selected = {'employees', 'expenses', 'salary_withdrawals'};

  test(
    'accepts a complete employee and salary mirror UUID relationship',
    () async {
      await seedValidMirror();

      final issues = await CloudflareD1IdentityValidator.inspect(
        db: db,
        selectedTables: selected,
      );

      expect(issues, isEmpty);
    },
  );

  test(
    'blocks upload when employee or mirror UUID links are inconsistent',
    () async {
      await seedValidMirror();
      await db.customStatement(
        "UPDATE expenses SET employee_uuid = 'emp-missing' WHERE local_uuid = 'exp-a'",
      );

      final issues = await CloudflareD1IdentityValidator.inspect(
        db: db,
        selectedTables: selected,
      );

      expect(issues, isNotEmpty);
      expect(issues.join('\n'), contains('employee_uuid'));
      expect(issues.join('\n'), contains('withdrawal_uuid'));
    },
  );
}
