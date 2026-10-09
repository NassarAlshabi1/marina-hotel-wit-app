import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('salary withdrawals report isolation is based on employeeUuid', () async {
    await db.into(db.employees).insert(EmployeesCompanion(
      name: const d.Value('A'), basicSalary: const d.Value(1000), status: const d.Value('active'),
      localUuid: const d.Value('EMP-A'), createdAt: const d.Value(1), updatedAt: const d.Value(1), lastModified: const d.Value(1),
    ));
    await db.into(db.employees).insert(EmployeesCompanion(
      name: const d.Value('B'), basicSalary: const d.Value(1000), status: const d.Value('active'),
      localUuid: const d.Value('EMP-B'), createdAt: const d.Value(1), updatedAt: const d.Value(1), lastModified: const d.Value(1),
    ));
    await db.customStatement('''INSERT INTO salary_withdrawals
      (employee_id, employee_uuid, amount, withdraw_date, local_uuid, created_at, updated_at, last_modified, version, origin)
      VALUES (1, 'EMP-A', 100, '2026-10-01', 'SW-A', 1, 1, 1, 1, 'local')''');
    await db.customStatement('''INSERT INTO salary_withdrawals
      (employee_id, employee_uuid, amount, withdraw_date, local_uuid, created_at, updated_at, last_modified, version, origin)
      VALUES (1, 'EMP-B', 900, '2026-10-01', 'SW-B', 1, 1, 1, 1, 'local')''');

    final a = await (db.select(db.salaryWithdrawals)
          ..where((t) => t.employeeUuid.equals('EMP-A'))).get();
    final b = await (db.select(db.salaryWithdrawals)
          ..where((t) => t.employeeUuid.equals('EMP-B'))).get();
    expect(a.map((r) => r.amount), [100]);
    expect(b.map((r) => r.amount), [900]);
  });
}
