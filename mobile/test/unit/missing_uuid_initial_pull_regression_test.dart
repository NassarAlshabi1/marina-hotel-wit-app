import 'package:appwrite/models.dart' as models;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

models.Document _doc({
  required String id,
  required Map<String, dynamic> data,
}) => models.Document(
  $id: id,
  $sequence: 0,
  $collectionId: 'expenses',
  $databaseId: 'marina',
  $createdAt: '2026-11-01T00:00:00.000Z',
  $updatedAt: '2026-11-01T12:00:00.000Z',
  $permissions: const <String>[],
  data: data,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'initial pull quarantines missing UUID and continues with valid records',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      AdapterRegistry.initialize(db);
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      try {
        const goodUuid = 'initial-pull-good-uuid';
        final good = _doc(
          id: goodUuid,
          data: <String, dynamic>{
            'localUuid': goodUuid,
            'lastModified': 1760000010,
            'vectorClock': '{}',
            'deviceId': 'device-a',
            'expenseType': 'صيانة',
            'description': 'سجل سليم',
            'amount': 100.0,
            'date': '2026-11-01',
            'createdAt': 1760000000,
          },
        );
        final legacy = _doc(
          id: 'legacy-server-id-only',
          data: <String, dynamic>{
            'lastModified': 1760000020,
            'description': 'سجل قديم بلا هوية',
            'amount': 50.0,
          },
        );
        final originalPayload = Map<String, dynamic>.from(legacy.data);

        final applied = await manager
            .applyPullDocumentsWithIdentityGuardForTesting(
              entity: 'expenses',
              documents: <models.Document>[legacy, good],
              apply: manager.syncExpensesForTesting,
            );

        expect(applied, 1);
        expect(
          await (db.select(
            db.expenses,
          )..where((row) => row.localUuid.equals(goodUuid))).getSingleOrNull(),
          isNotNull,
        );
        expect(
          await (db.select(db.expenses)
                ..where((row) => row.localUuid.equals('legacy-server-id-only')))
              .getSingleOrNull(),
          isNull,
        );

        final quarantined = await (db.select(
          db.orphanQuarantine,
        )..where((row) => row.entity.equals('expenses'))).get();
        expect(quarantined, hasLength(1));
        expect(quarantined.single.localUuid, isNull);
        expect(
          quarantined.single.payloadJson,
          contains('legacy-server-id-only'),
        );
        expect(quarantined.single.payloadJson, contains('سجل قديم بلا هوية'));
        expect(legacy.data, equals(originalPayload));
      } finally {
        await db.close();
      }
    },
  );
}
