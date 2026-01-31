import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_core/enhanced_event_bus.dart';
import 'package:marina_hotel_mobile/services/sync_core/events/sync_event.dart';

import 'helpers/memory_event_persistence.dart';

void main() {
  test('publish persists and acknowledge clears pending', () async {
    final persistence = MemoryEventPersistence();
    final bus = EnhancedEventBus(persistence);
    await bus.initialize();

    final event = EnhancedSyncEvent.create(
      table: 'rooms',
      entityId: 'r1',
      payload: {'name': '101'},
      priority: SyncPriority.normal,
    );

    await bus.publish(event);
    expect(persistence.events.length, 1);

    final pendingBefore = await bus.pendingCount();
    expect(pendingBefore, 1);

    await bus.acknowledge(event.id);

    final pendingAfter = await bus.pendingCount();
    expect(pendingAfter, 0);
  });

  test('publishBatch persists all events', () async {
    final persistence = MemoryEventPersistence();
    final bus = EnhancedEventBus(persistence);
    await bus.initialize();

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

    await bus.publishBatch(events);
    expect(persistence.events.length, 2);
  });

  test('waitForAcknowledgment completes on acknowledge', () async {
    final persistence = MemoryEventPersistence();
    final bus = EnhancedEventBus(persistence);
    await bus.initialize();

    final event = EnhancedSyncEvent.create(
      table: 'payments',
      entityId: 'p1',
      payload: {'amount': 50},
    );

    await bus.publish(event);

    final future = bus.waitForAcknowledgment(
      event.id,
      timeout: const Duration(seconds: 1),
    );

    await bus.acknowledge(event.id);

    await future;
  });
}
