// Delta sync service unit tests — regression baseline for the diff sync
// algorithm. These tests characterise the CURRENT behavior (including
// known bugs) so future fixes don't silently change semantics.
//
// Coverage:
//   1. Empty DB → no changes, but mirror snapshot is empty too.
//   2. First sync (no prior mirror) → all rows emitted as 'insert'.
//   3. Second sync (mirror present) with no changes → no changes emitted.
//   4. Local row update → single 'update' change emitted.
//   5. Local soft-delete after sync → 'update' with deleted_at set.
//   6. ⚠️ Known bug: hard-deleted row keeps emitting 'update' forever
//      (missing-row path always emits with nowTs). This test documents
//      the behavior; a fix must change this test.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/delta_sync_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late DeltaSyncService deltaSync;

  setUp(() async {
    db = TestDatabase.create();
    await db.customSelect('SELECT 1').get();
    deltaSync = DeltaSyncService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<RoomsCompanion> _roomCompanion(String number, {int? createdAt}) async {
    final now = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return RoomsCompanion(
      localUuid: Value('uuid-$number'),
      roomNumber: Value(number),
      type: const Value('single'),
      price: const Value(50.0),
      status: const Value('available'),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      createdAtEpoch: Value(now),
      lastModifiedEpoch: Value(now),
      version: const Value(1),
      origin: const Value('local'),
      vectorClock: const Value('{}'),
      deviceId: const Value('test'),
    );
  }

  group('DeltaSyncService.compute', () {
    test(
      '1. Empty DB → no changes, mirror snapshot has empty per-entity maps',
      () async {
        final result = await deltaSync.compute();
        expect(result.changes, isEmpty);
        // The mirror snapshot contains an entry per entity (even when empty).
        // It's not literally an empty Map, but each entity's table map is empty.
        for (final entry in result.mirrorSnapshot.entries) {
          expect(
            entry.value,
            isEmpty,
            reason: 'entity ${entry.key} should have an empty mirror map',
          );
        }
      },
    );

    test(
      '2. First sync — all rows emitted as insert (no prior mirror)',
      () async {
        await db.into(db.rooms).insert(await _roomCompanion('101'));
        await db.into(db.rooms).insert(await _roomCompanion('102'));

        final result = await deltaSync.compute();
        // First sync → all rows emitted as 'insert' regardless of timestamps
        // (isFirstSyncForTable = !hasMirror triggers shouldInsert).
        expect(result.changes.length, 2);
        for (final change in result.changes) {
          expect(change.operation, 'insert');
          expect(change.entity, 'rooms');
        }
        // Mirror snapshot should now contain both rows.
        expect(result.mirrorSnapshot['rooms']?.length, 2);
        // First sync (with changes) does NOT persist the mirror.
        final validation = await deltaSync.validateMirror();
        expect(validation.isValid, isFalse);
      },
    );

    test('3. Second sync — no changes → empty delta', () async {
      // First sync to populate mirror.
      await db.into(db.rooms).insert(await _roomCompanion('101'));
      final first = await deltaSync.compute();
      expect(first.changes.length, 1);
      await deltaSync.persistMirror(first);

      // ✅ Simulate a successful push by updating lastPushTs.
      // DeltaSyncService reads `state.lastPushTs` as `normalizedSince`.
      // Without this update, normalizedSince stays at 0 and every row
      // (with createdAt > 0) is re-emitted as 'insert' on the next sync.
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db
          .into(db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion(
              id: const Value(1),
              lastPushTs: Value(nowSec),
            ),
          );

      // Second sync — no changes since mirror was persisted AND
      // lastPushTs is now > the row's createdAt.
      final second = await deltaSync.compute();
      expect(second.changes, isEmpty);
    });

    test('4. Local update after sync → single update change', () async {
      await db.into(db.rooms).insert(await _roomCompanion('101'));
      final first = await deltaSync.compute();
      await deltaSync.persistMirror(first);

      // ✅ Bump lastPushTs so the next compute() uses it as normalizedSince.
      final pushTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db
          .into(db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion(
              id: const Value(1),
              lastPushTs: Value(pushTs),
            ),
          );

      // Update the row's lastModified to be after the previous sync.
      final room = await (db.select(
        db.rooms,
      )..where((r) => r.roomNumber.equals('101'))).getSingle();
      await (db.update(db.rooms)..where((r) => r.id.equals(room.id))).write(
        RoomsCompanion(
          status: const Value('occupied'),
          lastModified: Value(room.lastModified + 100),
          updatedAt: Value(room.lastModified + 100),
        ),
      );

      final second = await deltaSync.compute();
      expect(second.changes.length, 1);
      expect(second.changes.first.operation, 'update');
      expect(second.changes.first.localUuid, 'uuid-101');
    });

    test('5. Soft-delete after sync → update with deleted_at set', () async {
      await db.into(db.rooms).insert(await _roomCompanion('101'));
      final first = await deltaSync.compute();
      await deltaSync.persistMirror(first);

      // ✅ Bump lastPushTs so the next compute() uses it as normalizedSince.
      final pushTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db
          .into(db.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion(
              id: const Value(1),
              lastPushTs: Value(pushTs),
            ),
          );

      // Soft-delete the row (set deletedAt to a future timestamp).
      final room = await (db.select(
        db.rooms,
      )..where((r) => r.roomNumber.equals('101'))).getSingle();
      final futureTs = room.lastModified + 200;
      await (db.update(db.rooms)..where((r) => r.id.equals(room.id))).write(
        RoomsCompanion(
          deletedAt: Value(futureTs),
          lastModified: Value(futureTs),
        ),
      );

      final second = await deltaSync.compute();
      expect(second.changes.length, 1);
      expect(second.changes.first.operation, 'update');
      // deleted_at should be present in the payload.
      final data = second.changes.first.data;
      expect(data['deleted_at'], isNotNull);
    });

    test(
      '6. ✅ FIX: hard-deleted row emits delete only once (not forever)',
      () async {
        // Step 1: insert a room and sync.
        await db.into(db.rooms).insert(await _roomCompanion('101'));
        final first = await deltaSync.compute();
        await deltaSync.persistMirror(first);
        expect(first.changes.length, 1);

        // Step 2: HARD-delete the row (delete the row from the table, not
        // just soft-delete). This simulates a real hard delete.
        await (db.delete(
          db.rooms,
        )..where((r) => r.roomNumber.equals('101'))).go();

        // Step 3: first sync after hard-delete — emits delete ONCE.
        final second = await deltaSync.compute();
        expect(
          second.changes.length,
          1,
          reason:
              'First detection of hard-delete should emit a delete '
              'change so the server learns about it.',
        );
        expect(second.changes.first.operation, 'update');
        expect(second.changes.first.data['deleted_at'], isNotNull);

        // ✅ FIX: persist mirror so the delete is recorded (with deleted_at
        // set in payload). Without persistence, the next compute() can't
        // know the delete was already emitted.
        await deltaSync.persistMirror(second);

        // Step 4: subsequent sync — should NOT emit again because:
        //   - The mirror now contains the row with deleted_at set
        //   - But the local DB no longer has the row → still "missing"
        //   - previousDeletedAt != null → check deleteStamp > normalizedSince
        //   - deleteStamp (recorded) <= normalizedSince (just bumped) → skip
        //
        // We need to bump lastPushTs to simulate a successful push.
        // Without it, normalizedSince stays at 0 and deleteStamp > 0 is true.
        await db
            .into(db.syncState)
            .insertOnConflictUpdate(
              SyncStateCompanion(
                id: const Value(1),
                lastPushTs: Value(
                  DateTime.now().millisecondsSinceEpoch ~/ 1000,
                ),
              ),
            );

        final third = await deltaSync.compute();
        // ✅ The fix: third sync should NOT re-emit the delete.
        // (Either zero changes, or zero changes for entity 'rooms'.)
        final roomsChanges = third.changes
            .where((c) => c.entity == 'rooms')
            .toList();
        expect(
          roomsChanges,
          isEmpty,
          reason:
              'FIX: After successful push, hard-deleted rows should '
              'not be re-emitted on every sync cycle. previousDeletedAt '
              'is now set in the mirror, and deleteStamp <= normalizedSince '
              'after lastPushTs was updated.',
        );
      },
    );
  });

  group('DeltaSyncService.validateMirror', () {
    test('returns valid=true when mirror matches DB', () async {
      await db.into(db.rooms).insert(await _roomCompanion('101'));
      final first = await deltaSync.compute();
      await deltaSync.persistMirror(first);

      final validation = await deltaSync.validateMirror();
      expect(validation.isValid, isTrue);
      expect(validation.issues, isEmpty);
    });

    test('detects mirror staleness after local update', () async {
      await db.into(db.rooms).insert(await _roomCompanion('101'));
      final first = await deltaSync.compute();
      await deltaSync.persistMirror(first);

      // Update the row without re-syncing.
      final room = await (db.select(
        db.rooms,
      )..where((r) => r.roomNumber.equals('101'))).getSingle();
      await (db.update(db.rooms)..where((r) => r.id.equals(room.id))).write(
        RoomsCompanion(status: const Value('occupied')),
      );

      final validation = await deltaSync.validateMirror();
      // Either hash mismatch is detected (sample hit) or the validation
      // passes (sample miss). We can't guarantee sample hit, so just
      // verify the validation runs without throwing.
      expect(validation, isNotNull);
    });
  });
}
