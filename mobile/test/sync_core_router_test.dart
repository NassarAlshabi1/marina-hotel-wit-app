import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_core/enhanced_event_bus.dart';
import 'package:marina_hotel_mobile/services/sync_core/events/sync_event.dart';
import 'package:marina_hotel_mobile/services/sync_core/router/enhanced_sync_router.dart';
import 'package:marina_hotel_mobile/services/sync_core/adapters/sync_target_adapter.dart';

import 'helpers/fake_sync_adapter.dart';
import 'helpers/memory_event_persistence.dart';

void main() {
  test('routes to all adapters and acknowledges events', () async {
    final persistence = MemoryEventPersistence();
    final bus = EnhancedEventBus(persistence);
    await bus.initialize();

    final adapterA = FakeSyncAdapter(type: SyncTargetType.appwrite);
    final adapterB = FakeSyncAdapter(type: SyncTargetType.googleDrive);

    final router = EnhancedSyncRouter(
      eventBus: bus,
      config: const SyncRouterConfig(
        strategy: RoutingStrategy.all,
        debounceWindow: Duration.zero,
        maxBatchSize: 1,
        enableParallel: false,
      ),
    );

    router.registerAdapter(adapterA);
    router.registerAdapter(adapterB);
    await router.start();

    final pushed = Completer<void>();
    adapterA.onPush = (events) async {
      adapterA.pushedEvents.addAll(events);
      return SyncPushResult.success(
        affectedCount: events.length,
        syncedIds: events.map((e) => e.id).toList(),
      );
    };
    adapterB.onPush = (events) async {
      adapterB.pushedEvents.addAll(events);
      pushed.complete();
      return SyncPushResult.success(
        affectedCount: events.length,
        syncedIds: events.map((e) => e.id).toList(),
      );
    };

    final event = EnhancedSyncEvent.create(
      table: 'rooms',
      entityId: 'r1',
      payload: {'name': '101'},
    );

    await bus.publish(event);
    await pushed.future.timeout(const Duration(seconds: 1));

    expect(adapterA.pushedEvents.length, 1);
    expect(adapterB.pushedEvents.length, 1);

    final pending = await bus.pendingCount();
    expect(pending, 0);
  });

  test('primaryFirst stops on primary failure', () async {
    final persistence = MemoryEventPersistence();
    final bus = EnhancedEventBus(persistence);
    await bus.initialize();

    var secondaryCalled = false;

    final primary = FakeSyncAdapter(
      type: SyncTargetType.appwrite,
      onPush: (events) async {
        return SyncPushResult.failure(
          error: 'primary failed',
          failedIds: events.map((e) => e.id).toList(),
        );
      },
    );

    final secondary = FakeSyncAdapter(
      type: SyncTargetType.googleDrive,
      onPush: (events) async {
        secondaryCalled = true;
        return SyncPushResult.success(
          affectedCount: events.length,
          syncedIds: events.map((e) => e.id).toList(),
        );
      },
    );

    final router = EnhancedSyncRouter(
      eventBus: bus,
      config: const SyncRouterConfig(
        strategy: RoutingStrategy.primaryFirst,
        debounceWindow: Duration.zero,
        maxBatchSize: 1,
        enableParallel: false,
        primaryTarget: SyncTargetType.appwrite,
      ),
    );

    router.registerAdapter(primary);
    router.registerAdapter(secondary);
    await router.start();

    final event = EnhancedSyncEvent.create(
      table: 'payments',
      entityId: 'p1',
      payload: {'amount': 50},
    );

    await bus.publish(event);
    await Future.delayed(const Duration(milliseconds: 20));

    expect(secondaryCalled, isFalse);
  });

  test('roundRobin distributes events across adapters', () async {
    final persistence = MemoryEventPersistence();
    final bus = EnhancedEventBus(persistence);
    await bus.initialize();

    final adapterA = FakeSyncAdapter(type: SyncTargetType.appwrite);
    final adapterB = FakeSyncAdapter(type: SyncTargetType.googleDrive);

    final router = EnhancedSyncRouter(
      eventBus: bus,
      config: const SyncRouterConfig(
        strategy: RoutingStrategy.roundRobin,
        debounceWindow: Duration.zero,
        maxBatchSize: 3,
        enableParallel: false,
      ),
    );

    router.registerAdapter(adapterA);
    router.registerAdapter(adapterB);
    await router.start();

    await bus.publishBatch([
      EnhancedSyncEvent.create(
        table: 'rooms',
        entityId: 'r1',
        payload: {'name': '101'},
      ),
      EnhancedSyncEvent.create(
        table: 'rooms',
        entityId: 'r2',
        payload: {'name': '102'},
      ),
      EnhancedSyncEvent.create(
        table: 'rooms',
        entityId: 'r3',
        payload: {'name': '103'},
      ),
    ]);

    await Future.delayed(const Duration(milliseconds: 50));

    expect(adapterA.pushedEvents.length, 2);
    expect(adapterB.pushedEvents.length, 1);
  });

  test('priority routes critical to all and normal to local', () async {
    final persistence = MemoryEventPersistence();
    final bus = EnhancedEventBus(persistence);
    await bus.initialize();

    final appwrite = FakeSyncAdapter(type: SyncTargetType.appwrite);
    final local = FakeSyncAdapter(type: SyncTargetType.localJson);

    final router = EnhancedSyncRouter(
      eventBus: bus,
      config: const SyncRouterConfig(
        strategy: RoutingStrategy.priority,
        debounceWindow: Duration.zero,
        maxBatchSize: 2,
        enableParallel: false,
      ),
    );

    router.registerAdapter(appwrite);
    router.registerAdapter(local);
    await router.start();

    await bus.publishBatch([
      EnhancedSyncEvent.create(
        table: 'payments',
        entityId: 'p1',
        payload: {'amount': 10},
        priority: SyncPriority.critical,
      ),
      EnhancedSyncEvent.create(
        table: 'rooms',
        entityId: 'r1',
        payload: {'name': '101'},
        priority: SyncPriority.normal,
      ),
    ]);

    await Future.delayed(const Duration(milliseconds: 50));

    expect(appwrite.pushedEvents.length, 1);
    expect(local.pushedEvents.length, 2);
  });

  test('failover tries next adapter after failure', () async {
    final persistence = MemoryEventPersistence();
    final bus = EnhancedEventBus(persistence);
    await bus.initialize();

    var secondaryCalled = false;

    final primary = FakeSyncAdapter(
      type: SyncTargetType.appwrite,
      onPush: (events) async {
        return SyncPushResult.failure(error: 'fail', failedIds: []);
      },
    );

    final secondary = FakeSyncAdapter(
      type: SyncTargetType.localJson,
      onPush: (events) async {
        secondaryCalled = true;
        return SyncPushResult.success(
          affectedCount: events.length,
          syncedIds: events.map((e) => e.id).toList(),
        );
      },
    );

    final router = EnhancedSyncRouter(
      eventBus: bus,
      config: const SyncRouterConfig(
        strategy: RoutingStrategy.failover,
        debounceWindow: Duration.zero,
        maxBatchSize: 1,
        enableParallel: false,
        targetPriority: [SyncTargetType.appwrite, SyncTargetType.localJson],
      ),
    );

    router.registerAdapter(primary);
    router.registerAdapter(secondary);
    await router.start();

    final event = EnhancedSyncEvent.create(
      table: 'rooms',
      entityId: 'r1',
      payload: {'name': '101'},
    );

    await bus.publish(event);
    await Future.delayed(const Duration(milliseconds: 50));

    expect(secondaryCalled, isTrue);
  });
}
