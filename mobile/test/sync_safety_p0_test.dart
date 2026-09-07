// ═══════════════════════════════════════════════════════════════
//  sync_safety_p0_test.dart
//
//  ✅ Tests for P0-A through P0-J sync safety fixes.
//  Covers:
//    - P0-D: outbox payload/op change resets delivery state
//    - P0-E: cleanupForMissingEntities does not delete pending entries
//    - P0-H: reclaimAllStuckProcessingOnStartup reclaims stuck entries
//    - P0-I: SyncGuard.tryAcquire/release is atomic
//    - P0-F: SmartConflictResolver returns pushedToRemote=true on merges
// ═══════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value, Variable;

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/sync_guard.dart';
import 'package:marina_hotel_mobile/services/sync_core/smart_conflict_resolver.dart';
import 'package:marina_hotel_mobile/services/vector_clock_service.dart';

void main() {
  late AppDatabase db;
  late OutboxDao outboxDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outboxDao = OutboxDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('P0-D: outbox coalescing - delivery state reset on payload/op change', () {
    test(
      'merge with changed payload resets delivered_to_primary to false',
      () async {
        // Insert initial entry, then mark as delivered to primary
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'p0d-test-001',
          payload: {'room_number': '101', 'price': 100},
          clientTs: 1785549900,
        );

        // Manually mark as delivered to primary (simulating stale worker)
        await db.customStatement(
          "UPDATE outbox SET delivered_to_primary = 1, processing_status = 'pending' "
          "WHERE local_uuid = 'p0d-test-001'",
        );

        // Verify pre-condition
        var row = await db
            .customSelect(
              'SELECT delivered_to_primary FROM outbox WHERE local_uuid = ?',
              variables: [Variable<String>('p0d-test-001')],
            )
            .getSingle();
        expect(row.read<int>('delivered_to_primary'), equals(1));

        // Now merge again with DIFFERENT payload
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'p0d-test-001',
          payload: {'room_number': '101', 'price': 200}, // changed!
          clientTs: 1785549901,
        );

        // P0-D: delivered_to_primary should be reset to false
        row = await db
            .customSelect(
              'SELECT delivered_to_primary, attempts, last_error FROM outbox WHERE local_uuid = ?',
              variables: [Variable<String>('p0d-test-001')],
            )
            .getSingle();
        expect(
          row.read<int>('delivered_to_primary'),
          equals(0),
          reason:
              'P0-D: delivered_to_primary must be reset to false when payload changes',
        );
        expect(
          row.read<int>('attempts'),
          equals(0),
          reason: 'P0-D: attempts must be reset to 0 when payload changes',
        );
        expect(
          row.readNullable<String>('last_error'),
          isNull,
          reason: 'P0-D: last_error must be cleared when payload changes',
        );
      },
    );

    test(
      'merge with unchanged payload does NOT reset delivered_to_primary',
      () async {
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'p0d-test-002',
          payload: {'room_number': '102'},
          clientTs: 1785549900,
        );

        await db.customStatement(
          "UPDATE outbox SET delivered_to_primary = 1 WHERE local_uuid = 'p0d-test-002'",
        );

        // Merge again with SAME payload (no change)
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'p0d-test-002',
          payload: {'room_number': '102'}, // same
          clientTs: 1785549900,
        );

        final row = await db
            .customSelect(
              'SELECT delivered_to_primary FROM outbox WHERE local_uuid = ?',
              variables: [Variable<String>('p0d-test-002')],
            )
            .getSingle();
        // Should still be 1 because payload did not change
        expect(row.read<int>('delivered_to_primary'), equals(1));
      },
    );

    test(
      'resolveConflict resets both delivery flags to false',
      () async {
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'p0d-test-003',
          payload: {'room_number': '103'},
          clientTs: 1785549900,
        );

        // Mark both delivery flags as true (would normally trigger deletion,
        // but we set processing_status to failed first to keep it alive)
        await db.customStatement(
          "UPDATE outbox SET delivered_to_primary = 1, delivered_to_secondary = 1, "
          "processing_status = 'failed' WHERE local_uuid = 'p0d-test-003'",
        );

        // Resolve conflict with new data
        await outboxDao.resolveConflict(
          1, // id (auto-increment, first row = 1)
          {'room_number': '103', 'price': 500},
          resolution: 'manual',
        );

        final row = await db
            .customSelect(
              'SELECT delivered_to_primary, delivered_to_secondary, processing_status '
              'FROM outbox WHERE local_uuid = ?',
              variables: [Variable<String>('p0d-test-003')],
            )
            .getSingle();
        expect(
          row.read<int>('delivered_to_primary'),
          equals(0),
          reason: 'resolveConflict must reset delivered_to_primary',
        );
        expect(
          row.read<int>('delivered_to_secondary'),
          equals(0),
          reason: 'resolveConflict must reset delivered_to_secondary',
        );
        expect(
          row.read<String>('processing_status'),
          equals('pending'),
        );
      },
    );
  });

  group('P0-E: hard delete vs tombstone - cleanupForMissingEntities safety', () {
    test(
      'cleanupForMissingEntities does NOT delete pending entries',
      () async {
        // Create a pending entry (could be a creation that hasn't been pushed)
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'p0e-pending-001',
          payload: {'room_number': '201'},
          clientTs: 1785549900,
        );

        // Simulate "the entity is missing locally" (hard-deleted before sync)
        final removed = await outboxDao.cleanupForMissingEntities(
          ['p0e-pending-001'],
        );

        // P0-E: pending entries must NOT be deleted - silent data loss prevention
        expect(
          removed,
          equals(0),
          reason:
              'P0-E: pending entries must not be deleted (silent data loss prevention)',
        );

        final count = await outboxDao.count();
        expect(count, equals(1));
      },
    );

    test(
      'cleanupForMissingEntities deletes only failed entries with high attempts',
      () async {
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'p0e-failed-001',
          payload: {'room_number': '202'},
          clientTs: 1785549900,
        );

        // Mark as failed with 5 attempts (above default minAttempts=3)
        await db.customStatement(
          "UPDATE outbox SET processing_status = 'failed', attempts = 5 "
          "WHERE local_uuid = 'p0e-failed-001'",
        );

        // ✅ وضع P0-E صراحةً (الافتراضي في الدمج = Wave 4 completed-only)
        final removed = await outboxDao.cleanupForMissingEntities(
          ['p0e-failed-001'],
          minAttempts: 3,
        );
        expect(removed, equals(1));
      },
    );
  });

  group('P0-H: reclaimAllStuckProcessingOnStartup', () {
    test(
      'reclaims all processing entries regardless of age',
      () async {
        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'p0h-stuck-001',
          payload: {'room_number': '301'},
          clientTs: 1785549900,
        );

        await outboxDao.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'p0h-stuck-002',
          payload: {'room_number': '302'},
          clientTs: 1785549901,
        );

        // Mark both as processing (simulating crash during push)
        await db.customStatement(
          "UPDATE outbox SET processing_status = 'processing', "
          "processing_started_at = 1785549800 "
          "WHERE local_uuid IN ('p0h-stuck-001', 'p0h-stuck-002')",
        );

        final reclaimed = await outboxDao.reclaimAllStuckProcessingOnStartup();
        expect(reclaimed, equals(2));

        // Verify all are now pending
        final pendingCount = await outboxDao.countPendingPushable();
        expect(pendingCount, equals(2));

        // Verify processing_started_at is cleared
        final rows = await db
            .customSelect(
              'SELECT processing_started_at FROM outbox '
              "WHERE local_uuid IN ('p0h-stuck-001', 'p0h-stuck-002')",
            )
            .get();
        for (final row in rows) {
          expect(row.readNullable<int>('processing_started_at'), isNull);
        }
      },
    );

    test('returns 0 when no stuck entries exist', () async {
      final reclaimed = await outboxDao.reclaimAllStuckProcessingOnStartup();
      expect(reclaimed, equals(0));
    });
  });

  group('P0-I: SyncGuard tryAcquire/release atomic (Wave 5 token ownership)', () {
    // SyncGuard uses static state, so reset between tests
    setUp(() {
      // Force-release any prior state by directly accessing internals
      // via the public markFinished (clears state regardless)
      SyncGuard.markFinished();
    });
    tearDown(() {
      SyncGuard.markFinished();
      // إعادة مهلة stale الافتراضية (10 دقائق — قيمة _defaultStaleLockTimeout)
      SyncGuard.configureTimeouts(
        staleLockTimeout: const Duration(minutes: 10),
      );
    });

    test('tryAcquire succeeds when no lock held', () {
      final token = SyncGuard.tryAcquire(label: 'test_1');
      expect(token, isNotNull);
      expect(SyncGuard.isActive, isTrue);
      expect(SyncGuard.activeLabel, equals('test_1'));
      SyncGuard.release(token!);
    });

    test('tryAcquire fails when lock held by another label', () {
      final first = SyncGuard.tryAcquire(label: 'service_a');
      expect(first, isNotNull);

      final second = SyncGuard.tryAcquire(label: 'service_b');
      expect(second, isNull, reason: 'P0-I: second service must NOT acquire');
      expect(
        SyncGuard.activeLabel,
        equals('service_a'),
        reason: 'Lock must still be held by service_a',
      );

      SyncGuard.release(first!);
    });

    test(
      'stale takeover: old token does NOT release the newer lock (cross-release protection)',
      () {
        final tokenA = SyncGuard.tryAcquire(label: 'service_a');
        expect(tokenA, isNotNull);

        // مهلة stale = صفر مؤقتاً → الاستحواذ التالي ينتزع القفل المنتهي
        SyncGuard.configureTimeouts(staleLockTimeout: Duration.zero);
        final tokenB = SyncGuard.tryAcquire(label: 'service_b');
        expect(tokenB, isNotNull, reason: 'Stale lock must be takeover-able');
        expect(SyncGuard.activeLabel, equals('service_b'));

        // إعادة المهلة الافتراضية → قفل service_b الآن حيّ (غير منتهي)
        SyncGuard.configureTimeouts(
          staleLockTimeout: const Duration(minutes: 10),
        );

        // token القديم يحاول فك قفل حي لا يملكه — يجب رفضه (ملكية Wave 5)
        // (ملاحظة: فك قفل منتهي بأي token مقبول بعمد — صمام أمان perf)
        SyncGuard.release(tokenA!);

        expect(
          SyncGuard.isActive,
          isTrue,
          reason: 'P0-I: stale-token release must NOT clear the newer lock',
        );
        expect(SyncGuard.activeLabel, equals('service_b'));

        SyncGuard.release(tokenB!);
        expect(SyncGuard.isActive, isFalse);
      },
    );

    test('can re-acquire after release', () {
      final first = SyncGuard.tryAcquire(label: 'service_a');
      expect(first, isNotNull);
      SyncGuard.release(first!);

      final second = SyncGuard.tryAcquire(label: 'service_b');
      expect(
        second,
        isNotNull,
        reason: 'P0-I: must be able to acquire after release',
      );
      SyncGuard.release(second!);
    });
  });

  group('P0-F: SmartConflictResolver end-to-end resolution', () {
    test(
      'concurrent update with different fields produces merged result with pushedToRemote=true',
      () {
        final localData = {
          'local_uuid': 'room-001',
          'room_number': '101',
          'price': 100,
          'status': 'available',
          'vector_clock': '{"deviceA": 2}',
          'lastModified': 1785549900,
        };
        final remoteData = {
          'local_uuid': 'room-001',
          'room_number': '101',
          'price': 100,
          'status': 'occupied', // different from local
          'cleaning_status': 'dirty', // only in remote
          'vector_clock': '{"deviceB": 1}',
          'lastModified': 1785549901,
        };

        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: localData,
          remoteData: remoteData,
          commonAncestor: null,
        );

        // Should be a field-level merge (not localWins or remoteWins exclusively)
        expect(
          result.strategy,
          equals(ResolutionStrategy.fieldLevelMerge),
          reason: 'Concurrent update with different fields should field-merge',
        );
        expect(
          result.pushedToRemote,
          isTrue,
          reason: 'P0-F: merged result must be flagged for re-upload',
        );

        // Merged data should contain both local and remote changes
        expect(
          result.mergedData['status'],
          equals('occupied'),
          reason:
              'newerWins for status (remote ts 1785549901 > local 1785549900)',
        );
        expect(
          result.mergedData['cleaning_status'],
          equals('dirty'),
          reason: 'field only in remote should be added to merged',
        );
      },
    );

    test(
      'delete-vs-update gives priority to delete and flags for re-upload',
      () {
        final localData = {
          'local_uuid': 'room-002',
          'room_number': '102',
          'deletedAt': 1785549950, // local delete
          'vector_clock': '{"deviceA": 3}',
          'lastModified': 1785549900,
        };
        final remoteData = {
          'local_uuid': 'room-002',
          'room_number': '102',
          'price': 150, // remote update
          'vector_clock': '{"deviceB": 2}',
          'lastModified': 1785549901,
        };

        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: localData,
          remoteData: remoteData,
          commonAncestor: null,
        );

        // Delete-vs-update: local (delete) wins
        expect(result.strategy, equals(ResolutionStrategy.localWins));
        expect(
          result.pushedToRemote,
          isTrue,
          reason: 'P0-F: delete decision must be re-uploaded to remote',
        );
        expect(
          result.warnings,
          isNotEmpty,
          reason: 'Should warn about delete-vs-update priority',
        );
      },
    );

    test(
      'noConflictRemoteNewer does NOT flag for re-upload',
      () {
        final localData = {
          'local_uuid': 'room-003',
          'room_number': '103',
          'price': 100,
          'vector_clock': '{"deviceA": 1}',
          'lastModified': 1785549900,
        };
        final remoteData = {
          'local_uuid': 'room-003',
          'room_number': '103',
          'price': 200,
          'vector_clock': '{"deviceA": 1, "deviceB": 1}',
          'lastModified': 1785549901,
        };

        final result = SmartConflictResolver.resolve(
          entity: 'rooms',
          localData: localData,
          remoteData: remoteData,
          commonAncestor: null,
        );

        expect(result.strategy, equals(ResolutionStrategy.remoteWins));
        expect(
          result.pushedToRemote,
          isFalse,
          reason: 'P0-F: noConflictRemoteNewer should not require re-upload',
        );
      },
    );
  });

  group('P0-F/P0-D integration: vector clock + outbox delivery flag reset', () {
    test(
      'vector clock concurrent detection works correctly',
      () {
        final vc1 = VectorClock.fromString('{"a": 2, "b": 1}');
        final vc2 = VectorClock.fromString('{"a": 1, "b": 2}');

        expect(
          vc1.isConcurrent(vc2),
          isTrue,
          reason: 'Vector clocks with disjoint increments are concurrent',
        );
        expect(vc1.happensBefore(vc2), isFalse);
        expect(vc2.happensBefore(vc1), isFalse);
      },
    );

    test(
      'vector clock sequential detection works correctly',
      () {
        final vc1 = VectorClock.fromString('{"a": 1, "b": 1}');
        final vc2 = VectorClock.fromString('{"a": 2, "b": 1}');

        // vc1 happens-before vc2 (a: 1->2, b: 1=1)
        expect(vc1.happensBefore(vc2), isTrue);
        expect(vc2.happensBefore(vc1), isFalse);
        expect(vc1.isConcurrent(vc2), isFalse);
      },
    );
  });
}
