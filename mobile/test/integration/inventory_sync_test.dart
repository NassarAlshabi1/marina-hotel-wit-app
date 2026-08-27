import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/inventory_repository.dart';

void main() {
  late AppDatabase db;
  late AdapterRegistry adapters;
  late InventoryRepository repository;
  late OutboxDao outbox;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapters = AdapterRegistry.testing(db);
    repository = InventoryRepository(db, adapters);
    outbox = OutboxDao(db, adapters);
  });

  tearDown(() async => db.close());

  test('local inventory changes are represented in Outbox', () async {
    final itemId = await repository.createItem(
      name: 'مياه',
      unit: 'كرتون',
      initialQuantity: 10,
      minimumQuantity: 2,
    );
    await repository.recordMovement(
      itemId: itemId,
      movementType: 'out',
      quantity: 3,
      userId: 7,
      userName: 'مشرف',
    );

    final item = await (db.select(db.inventoryItems)
          ..where((row) => row.id.equals(itemId)))
        .getSingle();
    expect(item.quantity, 7);
    expect(await outbox.countPendingPushable(), 3);

    await expectLater(
      repository.recordMovement(
        itemId: itemId,
        movementType: 'out',
        quantity: 8,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      (await (db.select(db.inventoryItems)
                ..where((row) => row.id.equals(itemId)))
            .getSingle())
          .quantity,
      7,
    );
    expect(await outbox.countPendingPushable(), 3);
  });

  test('remote item and movement pull without reverse Outbox entries', () async {
    const itemUuid = '00000000-0000-4000-8000-000000000001';
    const movementUuid = '00000000-0000-4000-8000-000000000002';
    const now = 1_754_000_000;

    await adapters.inventoryItems.upsertFromJson(
      {
        'localUuid': itemUuid,
        'name': 'مناديل',
        'unit': 'كرتون',
        'quantity': 12,
        'minimumQuantity': 3,
        'isActive': true,
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'createdAtEpoch': now,
        'lastModifiedEpoch': now,
        'version': 1,
        'origin': 'mobile',
      },
      src: Source.appwrite,
    );
    final item = await (db.select(db.inventoryItems)
          ..where((row) => row.localUuid.equals(itemUuid)))
        .getSingle();

    await adapters.inventoryTransactions.upsertFromJson(
      {
        'localUuid': movementUuid,
        'itemLocalUuid': itemUuid,
        'movementType': 'in',
        'quantity': 12,
        'balanceAfter': 12,
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'createdAtEpoch': now,
        'lastModifiedEpoch': now,
        'version': 1,
      },
      src: Source.appwrite,
    );

    final movement = await (db.select(db.inventoryTransactions)
          ..where((row) => row.localUuid.equals(movementUuid)))
        .getSingle();
    expect(movement.itemId, item.id);
    expect(movement.itemLocalUuid, itemUuid);
    expect(movement.origin, 'server');
    expect(await outbox.countPendingPushable(), 0);
  });
}
