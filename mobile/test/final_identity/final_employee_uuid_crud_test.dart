import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/employees_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late EmployeesRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = EmployeesRepository(db);
  });
  tearDown(() => db.close());

  test('employee lifecycle operations resolve by localUuid, not numeric id', () async {
    final id = await repo.create(name: 'Test', status: 'active', basicSalary: 1000);
    final created = await (db.select(db.employees)..where((e) => e.id.equals(id))).getSingle();
    final uuid = created.localUuid;
    expect(uuid, isNotEmpty);

    await repo.terminateByLocalUuid(
      localUuid: uuid,
      terminationType: 'استقالة',
      terminationDate: '2026-10-01',
      terminationReason: 'test',
    );
    var row = await (db.select(db.employees)..where((e) => e.localUuid.equals(uuid))).getSingle();
    expect(row.status, isNot(equals('active')));

    await repo.reactivateByLocalUuid(localUuid: uuid);
    row = await (db.select(db.employees)..where((e) => e.localUuid.equals(uuid))).getSingle();
    expect(row.status, equals('active'));
  });
}
