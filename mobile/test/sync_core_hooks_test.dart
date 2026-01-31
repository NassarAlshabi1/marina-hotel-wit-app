import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/database_sync_hooks.dart';
import 'package:marina_hotel_mobile/services/sync_core/enhanced_event_bus.dart';
import 'package:marina_hotel_mobile/services/sync_core/events/sync_event.dart';

import 'helpers/memory_event_persistence.dart';

void main() {
  late AppDatabase db;
  late MemoryEventPersistence persistence;
  late EnhancedEventBus bus;
  late DatabaseSyncHooks hooks;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    persistence = MemoryEventPersistence();
    bus = EnhancedEventBus(persistence);
    hooks = DatabaseSyncHooks(database: db, eventBus: bus);

    await bus.initialize();
    await hooks.initialize();
    await Future.delayed(const Duration(milliseconds: 20));
  });

  tearDown(() async {
    await hooks.dispose();
    await db.close();
  });

  test('detects create, update, delete for rooms', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            localUuid: 'r1',
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            roomNumber: '101',
            type: 'single',
            price: 100,
            status: 'available',
          ),
        );

    await Future.delayed(const Duration(milliseconds: 30));
    expect(persistence.events.length, 1);
    expect(persistence.events.first.operation, SyncOperation.create);

    await (db.update(db.rooms)..where((t) => t.localUuid.equals('r1'))).write(
      RoomsCompanion(
        status: const Value('occupied'),
        updatedAt: Value(now + 1000),
        lastModified: Value(now + 1000),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 30));
    expect(persistence.events.length, 2);
    expect(persistence.events[1].operation, SyncOperation.update);

    await (db.delete(db.rooms)..where((t) => t.localUuid.equals('r1'))).go();

    await Future.delayed(const Duration(milliseconds: 30));
    expect(persistence.events.length, 3);
    expect(persistence.events.last.operation, SyncOperation.delete);
  });
}
