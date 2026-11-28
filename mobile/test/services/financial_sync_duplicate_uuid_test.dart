import 'package:appwrite/models.dart' as models;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

models.Document _expenseDoc({
  required String documentId,
  required int sequence,
  required int lastModified,
  required double amount,
}) {
  return models.Document(
    $id: documentId,
    $sequence: sequence,
    $collectionId: 'expenses',
    $databaseId: 'marina',
    $createdAt: '2026-11-01T00:00:00.000Z',
    $updatedAt: '2026-11-01T00:00:00.000Z',
    $permissions: const <String>[],
    data: <String, dynamic>{
      'localUuid': 'salary-expense-uuid-1',
      'expenseType': 'راتب',
      'description': 'اختبار منع تكرار مصروف الراتب',
      'amount': amount,
      'date': '2026-11-01',
      'createdAt': 1793491200,
      'lastModified': lastModified,
      'updatedAt': 1793491200,
      'vectorClock': '{}',
      'deviceId': 'financial-sync-test',
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('duplicate salary-expense cloud UUID is applied once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    AdapterRegistry.initialize(db);
    final manager = AppwriteSyncManager(
      appwriteService: AppwriteService(),
      database: db,
    );
    addTearDown(() async {
      manager.dispose();
      AdapterRegistry.reset();
      await db.close();
    });

    // The canonical Appwrite document ID is retained even if a legacy alias
    // claims a later timestamp; future pushes target this canonical UUID.
    final applied = await manager.syncExpensesForTesting(<models.Document>[
      _expenseDoc(
        documentId: 'salary-expense-uuid-1',
        sequence: 1,
        lastModified: 100,
        amount: 125.0,
      ),
      _expenseDoc(
        documentId: 'legacy-duplicate-document-id',
        sequence: 2,
        lastModified: 200,
        amount: 999.0,
      ),
    ]);

    final rows = await db.select(db.expenses).get();
    expect(applied, 1);
    expect(rows, hasLength(1));
    expect(rows.single.localUuid, 'salary-expense-uuid-1');
    expect(rows.single.amount, 125.0);
  });
}
