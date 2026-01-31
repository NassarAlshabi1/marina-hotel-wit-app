import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/events/sync_event.dart';
import 'package:marina_hotel_mobile/services/sync_core/persistence/sqlite_event_persistence.dart';

void main() {
  late AppDatabase db;
  late SqliteEventPersistence persistence;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    persistence = SqliteEventPersistence(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('persist and acknowledge event', () async {
    final event = EnhancedSyncEvent.create(
      table: 'rooms',
      entityId: 'r1',
      payload: {'name': '101'},
    );

    await persistence.persist(event);
    final pending = await persistence.getUnacknowledged();
    expect(pending.length, 1);

    await persistence.acknowledge(event.id);
    final pendingAfter = await persistence.getUnacknowledged();
    expect(pendingAfter.length, 0);
  });

  test('persistBatch stores multiple events', () async {
    final events = [
      EnhancedSyncEvent.create(
        table: 'rooms',
        entityId: 'r1',
        payload: {'name': '101'},
      ),
      EnhancedSyncEvent.update(
        table: 'rooms',
        entityId: 'r1',
        payload: {'name': '102'},
      ),
    ];

    await persistence.persistBatch(events);
    final pending = await persistence.getUnacknowledged();
    expect(pending.length, 2);
  });

  test('getByCorrelationId returns matching events', () async {
    final correlationId = 'corr-1';

    await persistence.persist(
      EnhancedSyncEvent.create(
        table: 'payments',
        entityId: 'p1',
        payload: {'amount': 50},
        correlationId: correlationId,
      ),
    );
    await persistence.persist(
      EnhancedSyncEvent.create(
        table: 'payments',
        entityId: 'p2',
        payload: {'amount': 60},
        correlationId: correlationId,
      ),
    );

    final items = await persistence.getByCorrelationId(correlationId);
    expect(items.length, 2);
  });
}
