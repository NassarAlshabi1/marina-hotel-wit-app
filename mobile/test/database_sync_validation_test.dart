import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import '../lib/services/local_db.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Database Schema Validation', () {
    test('Schema version is correct', () {
      expect(db.schemaVersion, 16);
    });

    test('All main tables exist with SyncFields', () async {
      final tablesWithSync = [
        'rooms',
        'bookings',
        'booking_notes',
        'employees',
        'expenses',
        'cash_transactions',
        'payments',
        'debts',
        'booking_nights',
        'hotel_day_ledger',
        'salary_cycles',
        'salary_payments',
      ];

      for (final tableName in tablesWithSync) {
        final result = await db.customSelect(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
          variables: [Variable.withString(tableName)],
        ).get();

        expect(result.isNotEmpty, true, reason: 'Table $tableName should exist');
        
        final sql = result.first.data['sql'] as String;
        expect(sql.contains('local_uuid'), true, reason: '$tableName should have local_uuid');
        expect(sql.contains('server_id'), true, reason: '$tableName should have server_id');
        expect(sql.contains('last_modified'), true, reason: '$tableName should have last_modified');
      }
    });

    test('Sync support tables exist', () async {
      final syncTables = [
        'outbox',
        'sync_state',
        'sync_queue',
        'sync_log',
        'sync_conflicts',
      ];

      for (final tableName in syncTables) {
        final result = await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          variables: [Variable.withString(tableName)],
        ).get();

        expect(result.isNotEmpty, true, reason: 'Sync table $tableName should exist');
      }
    });

    test('Foreign keys are enabled', () async {
      final result = await db.customSelect('PRAGMA foreign_keys').get();
      expect(result.first.data['foreign_keys'], 1);
    });
  });

  group('SyncFields Validation', () {
    test('Rooms table has all SyncFields', () async {
      final room = RoomsCompanion.insert(
        roomNumber: '101',
        type: 'single',
        price: 200.0,
        status: 'شاغرة',
        localUuid: 'test-uuid-room-101',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      final id = await db.into(db.rooms).insert(room);
      expect(id, greaterThan(0));

      final inserted = await (db.select(db.rooms)..where((t) => t.id.equals(id))).getSingle();
      expect(inserted.localUuid, 'test-uuid-room-101');
      expect(inserted.serverId, null);
      expect(inserted.version, 1);
      expect(inserted.origin, 'local');
    });

    test('Bookings table has all SyncFields', () async {
      final room = RoomsCompanion.insert(
        roomNumber: '102',
        type: 'double',
        price: 300.0,
        status: 'شاغرة',
        localUuid: 'test-uuid-room-102',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );
      await db.into(db.rooms).insert(room);

      final booking = BookingsCompanion.insert(
        roomNumber: '102',
        guestName: 'أحمد محمد',
        guestPhone: '966501234567',
        guestNationality: 'سعودي',
        checkinDate: '2025-12-13 14:00:00',
        status: 'نشط',
        localUuid: 'test-uuid-booking-1',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      final id = await db.into(db.bookings).insert(booking);
      expect(id, greaterThan(0));

      final inserted = await (db.select(db.bookings)..where((t) => t.id.equals(id))).getSingle();
      expect(inserted.localUuid, 'test-uuid-booking-1');
      expect(inserted.serverId, null);
      expect(inserted.version, 1);
    });

    test('Payments table has all SyncFields', () async {
      final payment = PaymentsCompanion.insert(
        roomNumber: Value('102'),
        amount: 500.0,
        paymentDate: '2025-12-13 15:00:00',
        paymentMethod: 'نقدي',
        revenueType: 'room',
        localUuid: 'test-uuid-payment-1',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      final id = await db.into(db.payments).insert(payment);
      expect(id, greaterThan(0));

      final inserted = await (db.select(db.payments)..where((t) => t.id.equals(id))).getSingle();
      expect(inserted.localUuid, 'test-uuid-payment-1');
      expect(inserted.paymentMethod, 'نقدي');
    });
  });

  group('Outbox Functionality', () {
    test('Outbox can store pending changes', () async {
      final outboxEntry = OutboxCompanion.insert(
        entity: 'bookings',
        op: 'insert',
        localUuid: 'test-uuid-booking-outbox',
        payload: '{"guestName": "محمد علي", "roomNumber": "103"}',
        clientTs: DateTime.now().millisecondsSinceEpoch,
      );

      final id = await db.into(db.outbox).insert(outboxEntry);
      expect(id, greaterThan(0));

      final entries = await db.select(db.outbox).get();
      expect(entries.length, 1);
      expect(entries.first.entity, 'bookings');
      expect(entries.first.op, 'insert');
      expect(entries.first.attempts, 0);
    });

    test('Outbox tracks retry attempts', () async {
      final outboxEntry = OutboxCompanion.insert(
        entity: 'payments',
        op: 'update',
        localUuid: 'test-uuid-payment-outbox',
        payload: '{"amount": 1000}',
        clientTs: DateTime.now().millisecondsSinceEpoch,
      );

      final id = await db.into(db.outbox).insert(outboxEntry);
      
      await (db.update(db.outbox)..where((t) => t.id.equals(id)))
          .write(const OutboxCompanion(attempts: Value(1)));

      final updated = await (db.select(db.outbox)..where((t) => t.id.equals(id))).getSingle();
      expect(updated.attempts, 1);
    });
  });

  group('SyncState Management', () {
    test('SyncState can be initialized', () async {
      final syncState = SyncStateCompanion.insert(
        id: const Value(1),
        lastServerTs: const Value(0),
        lastPullTs: const Value(0),
        lastPushTs: const Value(0),
        isSyncing: const Value(0),
        version: const Value(1),
      );

      await db.into(db.syncState).insert(
        syncState,
        mode: InsertMode.insertOrReplace,
      );

      final state = await db.select(db.syncState).getSingle();
      expect(state.id, 1);
      expect(state.isSyncing, 0);
    });

    test('SyncState can track sync timestamps', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      
      final syncState = SyncStateCompanion.insert(
        id: const Value(1),
        lastPushTs: Value(now),
      );

      await db.into(db.syncState).insert(
        syncState,
        mode: InsertMode.insertOrReplace,
      );

      final state = await db.select(db.syncState).getSingle();
      expect(state.lastPushTs, now);
    });
  });

  group('Indexes Validation', () {
    test('Rooms indexes exist', () async {
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='rooms' AND name LIKE 'idx_%'",
      ).get();

      expect(indexes.length, greaterThanOrEqualTo(2));
    });

    test('Bookings indexes exist', () async {
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='bookings' AND name LIKE 'idx_%'",
      ).get();

      expect(indexes.length, greaterThanOrEqualTo(3));
    });

    test('Payments indexes exist', () async {
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='payments' AND name LIKE 'idx_%'",
      ).get();

      expect(indexes.length, greaterThanOrEqualTo(2));
    });
  });

  group('Data Integrity', () {
    test('Cannot insert booking with invalid room reference', () async {
      final booking = BookingsCompanion.insert(
        roomNumber: '999',
        guestName: 'اختبار',
        guestPhone: '123456789',
        guestNationality: 'يمني',
        checkinDate: '2025-12-13 14:00:00',
        status: 'نشط',
        localUuid: 'test-uuid-invalid-room',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      expect(
        () async => await db.into(db.bookings).insert(booking),
        throwsA(isA<SqliteException>()),
      );
    });

    test('Unique constraint on localUuid works', () async {
      final room1 = RoomsCompanion.insert(
        roomNumber: '201',
        type: 'suite',
        price: 500.0,
        status: 'شاغرة',
        localUuid: 'duplicate-uuid',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      await db.into(db.rooms).insert(room1);

      final room2 = RoomsCompanion.insert(
        roomNumber: '202',
        type: 'suite',
        price: 500.0,
        status: 'شاغرة',
        localUuid: 'duplicate-uuid',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      expect(
        () async => await db.into(db.rooms).insert(room2),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('Payment Methods Validation', () {
    test('Cash payment can be created', () async {
      final payment = PaymentsCompanion.insert(
        amount: 1000.0,
        paymentDate: '2025-12-13 15:00:00',
        paymentMethod: 'نقدي',
        revenueType: 'room',
        localUuid: 'test-cash-payment',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      final id = await db.into(db.payments).insert(payment);
      final inserted = await (db.select(db.payments)..where((t) => t.id.equals(id))).getSingle();
      
      expect(inserted.paymentMethod, 'نقدي');
      expect(inserted.amount, 1000.0);
    });

    test('Transfer payment can be created', () async {
      final payment = PaymentsCompanion.insert(
        amount: 2000.0,
        paymentDate: '2025-12-13 16:00:00',
        paymentMethod: 'تحويل',
        revenueType: 'room',
        referenceNumber: const Value('REF123456'),
        localUuid: 'test-transfer-payment',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      final id = await db.into(db.payments).insert(payment);
      final inserted = await (db.select(db.payments)..where((t) => t.id.equals(id))).getSingle();
      
      expect(inserted.paymentMethod, 'تحويل');
      expect(inserted.referenceNumber, 'REF123456');
      expect(inserted.amount, 2000.0);
    });

    test('Payments are linked to bookings correctly', () async {
      final room = RoomsCompanion.insert(
        roomNumber: '301',
        type: 'deluxe',
        price: 400.0,
        status: 'شاغرة',
        localUuid: 'room-301-uuid',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );
      await db.into(db.rooms).insert(room);

      final booking = BookingsCompanion.insert(
        roomNumber: '301',
        guestName: 'فاطمة أحمد',
        guestPhone: '966502345678',
        guestNationality: 'سعودي',
        checkinDate: '2025-12-13 12:00:00',
        status: 'نشط',
        localUuid: 'booking-301-uuid',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );
      final bookingId = await db.into(db.bookings).insert(booking);

      final payment = PaymentsCompanion.insert(
        bookingLocalId: Value(bookingId),
        roomNumber: const Value('301'),
        amount: 400.0,
        paymentDate: '2025-12-13 15:00:00',
        paymentMethod: 'نقدي',
        revenueType: 'room',
        localUuid: 'payment-301-uuid',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      final paymentId = await db.into(db.payments).insert(payment);
      final inserted = await (db.select(db.payments)..where((t) => t.id.equals(paymentId))).getSingle();
      
      expect(inserted.bookingLocalId, bookingId);
      expect(inserted.roomNumber, '301');
    });
  });

  group('Sync Operations', () {
    test('Can add to outbox after data change', () async {
      final payment = PaymentsCompanion.insert(
        amount: 750.0,
        paymentDate: '2025-12-13 17:00:00',
        paymentMethod: 'تحويل',
        revenueType: 'room',
        localUuid: 'payment-for-outbox',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lastModified: DateTime.now().millisecondsSinceEpoch,
      );

      await db.into(db.payments).insert(payment);

      final outboxEntry = OutboxCompanion.insert(
        entity: 'payments',
        op: 'insert',
        localUuid: 'payment-for-outbox',
        payload: '{"amount": 750.0, "paymentMethod": "تحويل"}',
        clientTs: DateTime.now().millisecondsSinceEpoch,
      );

      final outboxId = await db.into(db.outbox).insert(outboxEntry);
      expect(outboxId, greaterThan(0));

      final outboxEntries = await db.select(db.outbox).get();
      expect(outboxEntries.any((e) => e.entity == 'payments'), true);
    });

    test('SyncLog can track sync operations', () async {
      final logEntry = SyncLogCompanion.insert(
        syncId: 'sync-${DateTime.now().millisecondsSinceEpoch}',
        direction: 'push',
        deviceId: 'device-test-123',
        metadata: '{}',
        operations: '[]',
        createdAt: DateTime.now().toIso8601String(),
      );

      final logId = await db.into(db.syncLog).insert(logEntry);
      expect(logId, greaterThan(0));

      final logs = await db.select(db.syncLog).get();
      expect(logs.length, 1);
      expect(logs.first.direction, 'push');
    });

    test('SyncConflicts can be recorded', () async {
      final logEntry = SyncLogCompanion.insert(
        syncId: 'sync-conflict-test',
        direction: 'pull',
        deviceId: 'device-test-456',
        metadata: '{}',
        operations: '[]',
        createdAt: DateTime.now().toIso8601String(),
      );
      final logId = await db.into(db.syncLog).insert(logEntry);

      final conflict = SyncConflictsCompanion.insert(
        logId: logId,
        targetTable: 'bookings',
        uuid: 'conflict-booking-uuid',
        resolution: 'local-wins',
        localPayload: '{"amount": 500}',
        remotePayload: '{"amount": 600}',
        createdAt: DateTime.now().toIso8601String(),
      );

      final conflictId = await db.into(db.syncConflicts).insert(conflict);
      expect(conflictId, greaterThan(0));

      final conflicts = await (db.select(db.syncConflicts)
        ..where((t) => t.logId.equals(logId))).get();
      expect(conflicts.length, 1);
      expect(conflicts.first.resolution, 'local-wins');
    });
  });

  group('Migration History', () {
    test('Database should be at latest schema version', () {
      expect(db.schemaVersion, 16);
    });
  });
}
