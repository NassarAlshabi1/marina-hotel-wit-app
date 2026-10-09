import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ExpensesRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ExpensesRepository(db);
  });
  tearDown(() => db.close());

  test('salary expense stores employeeUuid at creation time', () async {
    final id = await repo.create(
      expenseType: 'سحب راتب', description: 'x', amount: 100,
      date: '2026-10-01', relatedId: 7, employeeUuid: 'EMP-UUID-1',
    );
    final row = await (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingle();
    expect(row.employeeUuid, 'EMP-UUID-1');
  });

  test('employeeUuid is not silently replaced by relatedId', () async {
    final id = await repo.create(
      expenseType: 'سحب راتب', description: 'x', amount: 100,
      date: '2026-10-01', relatedId: 999, employeeUuid: 'EMP-REAL',
    );
    final row = await (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingle();
    expect(row.relatedId, 999);
    expect(row.employeeUuid, 'EMP-REAL');
  });
}
