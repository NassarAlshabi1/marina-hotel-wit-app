import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/batch/batch_operations_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  late AppDatabase db;
  late BatchOperationsService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = BatchOperationsService(db);
  });

  tearDown(() async {
    await db.close();
  });

  RoomsCompanion room({required String localUuid, required double price}) =>
      RoomsCompanion.insert(
        roomNumber: '101',
        type: 'standard',
        price: price,
        status: 'شاغرة',
        localUuid: localUuid,
        createdAt: 1,
        updatedAt: 1,
        lastModified: 1,
      );

  test(
    'batchInsertRooms يحدّث السجل على local_uuid ويحافظ على id المحلي',
    () async {
      await service.batchInsertRooms([
        room(localUuid: 'room-batch-uuid', price: 100),
      ]);
      final before = await db.select(db.rooms).getSingle();

      await service.batchInsertRooms([
        room(localUuid: 'room-batch-uuid', price: 250),
      ]);

      final rows = await db.select(db.rooms).get();
      expect(rows, hasLength(1));
      expect(rows.single.localUuid, 'room-batch-uuid');
      expect(rows.single.id, before.id);
      expect(rows.single.price, 250);
    },
  );

  test('bulkInsertSync يستخدم local_uuid ولا يكتب id البعيد', () async {
    await service.batchInsertRooms([
      room(localUuid: 'room-raw-sync-uuid', price: 100),
    ]);
    final before = await db.select(db.rooms).getSingle();

    await service.bulkInsertSync('rooms', [
      {
        'id': 999,
        'local_uuid': 'room-raw-sync-uuid',
        'room_number': '101',
        'type': 'suite',
        'price': 300,
        'status': 'مشغولة',
        'created_at': 1,
        'updated_at': 2,
        'last_modified': 2,
      },
    ]);

    final rows = await db.select(db.rooms).get();
    expect(rows, hasLength(1));
    expect(rows.single.localUuid, 'room-raw-sync-uuid');
    expect(rows.single.id, before.id);
    expect(rows.single.type, 'suite');
    expect(rows.single.price, 300);
  });
}
