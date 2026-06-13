import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:drift/native.dart';

void main() {
  group('OutboxDao', () {
    late AppDatabase database;
    late OutboxDao outboxDao;

    setUpAll(() {
      sqlite3flutterLibsInit();
    });

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      outboxDao = OutboxDao(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('merge creates new entry', () async {
      final id = await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'test-uuid-1',
        payload: {'guestName': 'John'},
        clientTs: 1000,
      );

      expect(id, greaterThan(0));
      
      final count = await outboxDao.count();
      expect(count, equals(1));
    });

    test('merge updates existing pending entry', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'test-uuid-2',
        payload: {'guestName': 'John'},
        clientTs: 1000,
      );

      final id2 = await outboxDao.merge(
        entity: 'bookings',
        op: 'update',
        localUuid: 'test-uuid-2',
        payload: {'guestName': 'Jane'},
        clientTs: 2000,
      );

      final count = await outboxDao.count();
      expect(count, equals(1));
      expect(id2, greaterThan(0));
    });

    test('merge does not duplicate processing entries', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'test-uuid-3',
        payload: {'guestName': 'John'},
        clientTs: 1000,
      );

      // Simulate processing status
      await database.customStatement(
        'UPDATE outbox SET processing_status = ? WHERE local_uuid = ?',
        ['processing', 'test-uuid-3'],
      );

      final id = await outboxDao.merge(
        entity: 'bookings',
        op: 'update',
        localUuid: 'test-uuid-3',
        payload: {'guestName': 'Jane'},
        clientTs: 2000,
      );

      final count = await outboxDao.count();
      expect(count, equals(1));
      
      // Should reset to pending
      final entry = await database.select(database.outbox)
          ..where((t) => t.localUuid.equals('test-uuid-3'))
          ..limit(1)
          .getSingleOrNull();
      expect(entry?.processingStatus, equals('pending'));
    });

    test('takeBatch claims entries atomically', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'uuid-1',
        payload: {'a': 1},
        clientTs: 1000,
      );
      await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'uuid-2',
        payload: {'b': 2},
        clientTs: 2000,
      );

      final batch = await outboxDao.takeBatch(10, workerId: 'worker-1');
      expect(batch.length, equals(2));
      
      for (final entry in batch) {
        expect(entry.processingStatus, equals('processing'));
        expect(entry.processingWorker, equals('worker-1'));
      }
    });

    test('takeBatch respects source filter', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'local-1',
        payload: {},
        clientTs: 1000,
        source: 'local',
      );
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'restore-1',
        payload: {},
        clientTs: 2000,
        source: 'restore',
      );

      final localBatch = await outboxDao.takeBatch(10, sources: ['local']);
      expect(localBatch.length, equals(1));
      expect(localBatch.first.localUuid, equals('local-1'));
    });

    test('markCompleted removes entries', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'uuid-complete',
        payload: {},
        clientTs: 1000,
      );

      final batch = await outboxDao.takeBatch(10);
      await outboxDao.markCompleted(batch.map((e) => e.id).toList());

      final count = await outboxDao.count();
      expect(count, equals(0));
    });

    test('setError increments attempts', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'uuid-error',
        payload: {},
        clientTs: 1000,
      );

      final batch = await outboxDao.takeBatch(10);
      await outboxDao.setError(batch.first.id, 'Network error', 1);

      final entry = await database.select(database.outbox)
          ..where((t) => t.id.equals(batch.first.id))
          .getSingleOrNull();
      expect(entry?.attempts, equals(1));
      expect(entry?.lastError, equals('Network error'));
      expect(entry?.processingStatus, equals('failed'));
    });

    test('retryFailed resets failed entries', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'uuid-retry',
        payload: {},
        clientTs: 1000,
      );

      final batch = await outboxDao.takeBatch(10);
      await outboxDao.setError(batch.first.id, 'Error', 1);
      await outboxDao.retryFailed();

      final count = await outboxDao.count();
      expect(count, equals(1));
      
      final entry = await database.select(database.outbox)
          ..where((t) => t.id.equals(batch.first.id))
          .getSingleOrNull();
      expect(entry?.processingStatus, equals('pending'));
      expect(entry?.attempts, equals(0));
    });

    test('clearStale resets old failed entries', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'stale-1',
        payload: {},
        clientTs: 1000,
      );

      final batch = await outboxDao.takeBatch(10);
      await outboxDao.setError(batch.first.id, 'Error', 5); // > threshold

      final cleared = await outboxDao.clearStale(attemptsThreshold: 3);
      expect(cleared, equals(1));
      
      final entry = await database.select(database.outbox)
          ..where((t) => t.id.equals(batch.first.id))
          .getSingleOrNull();
      expect(entry?.processingStatus, equals('pending'));
    });

    test('cleanupCompleted removes old completed entries', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'old-complete',
        payload: {},
        clientTs: 1000,
      );
      final batch = await outboxDao.takeBatch(10);
      await outboxDao.markCompleted(batch.map((e) => e.id).toList());

      // Manually set old timestamp
      await database.customStatement(
        'UPDATE outbox SET client_ts = ? WHERE local_uuid = ?',
        [1000, 'old-complete'],
      );

      final cleaned = await outboxDao.cleanupCompleted(olderThan: Duration(days: 1));
      expect(cleaned, equals(1));
    });

    test('removePulledEntities removes matching local uuids', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'pulled-1',
        payload: {},
        clientTs: 1000,
      );
      await outboxDao.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'pulled-2',
        payload: {},
        clientTs: 2000,
      );

      final removed = await outboxDao.removePulledEntities(['pulled-1']);
      expect(removed, equals(1));

      final count = await outboxDao.count();
      expect(count, equals(1));
    });

    test('getConflicts returns failed entries with errors', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'conflict-1',
        payload: {'guestName': 'John'},
        clientTs: 1000,
      );

      final batch = await outboxDao.takeBatch(10);
      await outboxDao.setError(batch.first.id, 'Version conflict', 1);

      final conflicts = await outboxDao.getConflicts();
      expect(conflicts.length, equals(1));
      expect(conflicts.first.targetTable, equals('bookings'));
      expect(conflicts.first.lastError, equals('Version conflict'));
    });

    test('resolveConflict updates payload and resets status', () async {
      await outboxDao.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: 'resolve-1',
        payload: {'guestName': 'John'},
        clientTs: 1000,
      );

      final batch = await outboxDao.takeBatch(10);
      await outboxDao.setError(batch.first.id, 'Conflict', 1);
      
      await outboxDao.resolveConflict(
        batch.first.id,
        {'guestName': 'Jane'},
        resolution: 'local_wins',
      );

      final entry = await database.select(database.outbox)
          ..where((t) => t.id.equals(batch.first.id))
          .getSingleOrNull();
      expect(entry?.processingStatus, equals('pending'));
      expect(entry?.attempts, equals(0));
      expect(entry?.lastError, isNull);
      
      final payload = jsonDecode(entry!.payload);
      expect(payload['guestName'], equals('Jane'));
    });
  });
}