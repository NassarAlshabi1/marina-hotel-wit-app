// ============================================================================
//  Marina Hotel — Appwrite Sync Flow Benchmark (Mock)
//  ============================================================================
//  يقيس أداء flow المزامنة (push/pull) باستخدام drift operations حقيقية.
//
//  ملاحظة منهجية (لا تخمين):
//    AppwriteSyncManager.sync() يستدعي Appwrite SDK الذي يتطلب اتصال شبكة
//    + credentials. لا يمكن تشغيله في test بدون mock معقد.
//    بدلاً من ذلك، هذا الـ benchmark يحاكي الـ flow عبر drift operations:
//      - push = takeBatch + (محاكاة إرسال شبكة) + markCompleted
//      - pull = (محاكاة استقبال شبكة) + insertOne + updateById
//    هذا يعكس الـ bottleneck الحقيقي (drift operations، ليس الشبكة).
//
//  المقاييس:
//    1. Push flow: takeBatch(100) + markCompleted — محاكاة رفع 100 سجل
//    2. Pull flow: insertOne × 100 — محاكاة استقبال 100 سجل
//    3. Full sync cycle: push + pull معاً
//    4. Conflict resolution: LWW على 100 سجل
//    5. Latency breakdown per phase
//
//  التشغيل:
//    flutter test test/performance/appwrite_sync_flow_benchmark_test.dart \
//      --reporter=expanded
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars, avoid_redundant_argument_values

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/daos/bookings_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// محاكاة latency الشبكة (50ms لكل دفعة).
Future<void> _simulateNetworkLatency({int ms = 50}) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OutboxDao outboxDao;
  late BookingsDao bookingsDao;
  late RoomsDao roomsDao;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outboxDao = OutboxDao(db);
    bookingsDao = BookingsDao(db, outboxDao);
    roomsDao = RoomsDao(db, outboxDao);

    // إنشاء غرف لـ foreign key (await لضمان اكتمالها قبل الـ test)
    for (var i = 0; i < 5; i++) {
      await roomsDao.insertOne(
        RoomsCompanion(
          roomNumber: d.Value('${100 + i}'),
          type: const d.Value('عادية'),
          price: const d.Value(100.0),
          status: const d.Value('شاغرة'),
          localUuid: d.Value('room-$i'),
        ),
      );
    }
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  1. Push Flow — محاكاة رفع 100 سجل
  // ═══════════════════════════════════════════════════════════════════════════
  group('📤 Push Flow (100 records)', () {
    test(
      'push 100 records (takeBatch + network + markCompleted) خلال < 200ms',
      () async {
        // إعداد: 100 outbox entries
        await db.transaction(() async {
          for (var i = 0; i < 100; i++) {
            await outboxDao.merge(
              entity: 'bookings',
              op: 'create',
              localUuid: 'push-uuid-$i',
              payload: {'id': i, 'name': 'Push $i'},
              clientTs: i,
              source: 'local',
            );
          }
        });

        final stopwatch = Stopwatch()..start();

        // Phase 1: takeBatch
        final phase1 = Stopwatch()..start();
        final batch = await outboxDao.takeBatch(100);
        phase1.stop();

        // Phase 2: محاكاة إرسال شبكة
        final phase2 = Stopwatch()..start();
        await _simulateNetworkLatency(ms: 50);
        phase2.stop();

        // Phase 3: markCompleted
        final phase3 = Stopwatch()..start();
        final ids = batch.map((e) => e.id).toList();
        await outboxDao.markCompleted(ids);
        phase3.stop();

        stopwatch.stop();

        debugPrint('✓ Push flow (100 records):');
        debugPrint('  Total: ${stopwatch.elapsedMilliseconds}ms');
        debugPrint('  Phase 1 (takeBatch): ${phase1.elapsedMilliseconds}ms');
        debugPrint('  Phase 2 (network sim): ${phase2.elapsedMilliseconds}ms');
        debugPrint(
          '  Phase 3 (markCompleted): ${phase3.elapsedMilliseconds}ms',
        );
        debugPrint(
          '  Drift overhead: ${stopwatch.elapsedMilliseconds - phase2.elapsedMilliseconds}ms',
        );

        expect(batch.length, 100);
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(200),
          reason: 'push 100 records يجب أن يكون < 200ms (شبكة 50ms + drift)',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  2. Pull Flow — محاكاة استقبال 100 سجل
  // ═══════════════════════════════════════════════════════════════════════════
  group('📥 Pull Flow (100 records)', () {
    test('pull 100 records (network + insertOne) خلال < 500ms', () async {
      final stopwatch = Stopwatch()..start();

      // Phase 1: محاكاة استقبال شبكة
      final phase1 = Stopwatch()..start();
      await _simulateNetworkLatency(ms: 50);
      phase1.stop();

      // Phase 2: insertOne × 100 في transaction
      final phase2 = Stopwatch()..start();
      await db.transaction(() async {
        for (var i = 0; i < 100; i++) {
          await bookingsDao.insertOne(
            BookingsCompanion(
              roomNumber: d.Value('${100 + (i % 5)}'),
              guestName: d.Value('Pull Guest $i'),
              guestPhone: const d.Value('050'),
              guestNationality: const d.Value('يمني'),
              checkinDate: d.Value(DateTime.now().toIso8601String()),
              status: const d.Value('نشط'),
              localUuid: d.Value('pull-uuid-$i'),
            ),
          );
        }
      });
      phase2.stop();

      stopwatch.stop();

      debugPrint('✓ Pull flow (100 records):');
      debugPrint('  Total: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('  Phase 1 (network sim): ${phase1.elapsedMilliseconds}ms');
      debugPrint(
        '  Phase 2 (insertOne × 100 in tx): ${phase2.elapsedMilliseconds}ms',
      );
      debugPrint(
        '  Drift overhead: ${stopwatch.elapsedMilliseconds - phase1.elapsedMilliseconds}ms',
      );

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: 'pull 100 records يجب أن يكون < 500ms (شبكة 50ms + drift)',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  3. Full Sync Cycle — push + pull
  // ═══════════════════════════════════════════════════════════════════════════
  group('🔄 Full Sync Cycle (push 50 + pull 50)', () {
    test('full sync cycle خلال < 500ms', () async {
      // إعداد: 50 outbox entries للـ push
      await db.transaction(() async {
        for (var i = 0; i < 50; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'cycle-push-$i',
            payload: {'id': i},
            clientTs: i,
            source: 'local',
          );
        }
      });

      final stopwatch = Stopwatch()..start();

      // Push phase
      final pushBatch = await outboxDao.takeBatch(50);
      await _simulateNetworkLatency(ms: 50);
      await outboxDao.markCompleted(pushBatch.map((e) => e.id).toList());

      // Pull phase
      await _simulateNetworkLatency(ms: 50);
      await db.transaction(() async {
        for (var i = 0; i < 50; i++) {
          await bookingsDao.insertOne(
            BookingsCompanion(
              roomNumber: d.Value('${100 + (i % 5)}'),
              guestName: d.Value('Cycle Guest $i'),
              guestPhone: const d.Value('050'),
              guestNationality: const d.Value('يمني'),
              checkinDate: d.Value(DateTime.now().toIso8601String()),
              status: const d.Value('نشط'),
              localUuid: d.Value('cycle-pull-$i'),
            ),
          );
        }
      });

      stopwatch.stop();

      debugPrint('✓ Full sync cycle (push 50 + pull 50):');
      debugPrint('  Total: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('  Network sim: ~100ms (50ms push + 50ms pull)');
      debugPrint('  Drift overhead: ${stopwatch.elapsedMilliseconds - 100}ms');

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: 'full sync cycle يجب أن يكون < 500ms',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  4. Conflict Resolution — LWW على 100 سجل
  // ═══════════════════════════════════════════════════════════════════════════
  group('⚖️ Conflict Resolution (LWW, 100 records)', () {
    test('LWW resolution لـ 100 سجل خلال < 50ms', () async {
      // محاكاة 100 سجل مع conflict (localTs vs remoteTs)
      final conflicts = List.generate(
        100,
        (i) => {
          'localUuid': 'conflict-$i',
          'localLastModified': i < 50 ? 2000 : 1000, // 50 محلي أحدث
          'remoteLastModified': i < 50 ? 1000 : 2000, // 50 بعيد أحدث
        },
      );

      final stopwatch = Stopwatch()..start();
      var localWins = 0;
      var remoteWins = 0;
      for (final c in conflicts) {
        final localTs = c['localLastModified'] as int;
        final remoteTs = c['remoteLastModified'] as int;
        if (localTs >= remoteTs) {
          localWins++;
        } else {
          remoteWins++;
        }
      }
      stopwatch.stop();

      debugPrint(
        '✓ LWW conflict resolution (100 records): ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('  Local wins: $localWins, Remote wins: $remoteWins');

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(50),
        reason: 'LWW لـ 100 سجل يجب أن يكون < 50ms',
      );
      expect(localWins, 50);
      expect(remoteWins, 50);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  5. Latency Breakdown — تحليل كل phase
  // ═══════════════════════════════════════════════════════════════════════════
  group('📊 Latency Breakdown', () {
    test('تحليل زمن كل phase في sync cycle', () async {
      // إعداد
      await db.transaction(() async {
        for (var i = 0; i < 100; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'latency-$i',
            payload: {'id': i},
            clientTs: i,
            source: 'local',
          );
        }
      });

      final phases = <String, int>{};

      // Phase 1: takeBatch
      var sw = Stopwatch()..start();
      final batch = await outboxDao.takeBatch(100);
      sw.stop();
      phases['takeBatch'] = sw.elapsedMilliseconds;

      // Phase 2: محاكاة serialize + send
      sw = Stopwatch()..start();
      // محاكاة serialize (تحويل payload لـ string — يقيس زمن المعالجة)
      final serialized = batch.map((e) => e.payload.toString()).join(',');
      expect(serialized.length, greaterThan(0)); // منع optimizer من حذفها
      await _simulateNetworkLatency(ms: 30);
      sw.stop();
      phases['serialize+send'] = sw.elapsedMilliseconds;

      // Phase 3: markCompleted
      sw = Stopwatch()..start();
      await outboxDao.markCompleted(batch.map((e) => e.id).toList());
      sw.stop();
      phases['markCompleted'] = sw.elapsedMilliseconds;

      // Phase 4: محاكاة receive + deserialize
      sw = Stopwatch()..start();
      await _simulateNetworkLatency(ms: 30);
      sw.stop();
      phases['receive'] = sw.elapsedMilliseconds;

      // Phase 5: insertOne × 100
      sw = Stopwatch()..start();
      await db.transaction(() async {
        for (var i = 0; i < 100; i++) {
          await bookingsDao.insertOne(
            BookingsCompanion(
              roomNumber: const d.Value('101'),
              guestName: d.Value('Latency Guest $i'),
              guestPhone: const d.Value('050'),
              guestNationality: const d.Value('يمني'),
              checkinDate: d.Value(DateTime.now().toIso8601String()),
              status: const d.Value('نشط'),
              localUuid: d.Value('latency-pull-$i'),
            ),
          );
        }
      });
      sw.stop();
      phases['insertOne×100'] = sw.elapsedMilliseconds;

      final total = phases.values.fold<int>(0, (a, b) => a + b);

      debugPrint('✓ Latency breakdown (100 records):');
      for (final entry in phases.entries) {
        debugPrint('  ${entry.key}: ${entry.value}ms');
      }
      debugPrint('  Total: ${total}ms');

      expect(
        total,
        lessThan(500),
        reason: 'إجمالي latency يجب أن يكون < 500ms',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  6. تقرير نهائي
  // ═══════════════════════════════════════════════════════════════════════════
  group('📊 Sync Flow Summary', () {
    test('طباعة ملخص مقاييس sync flow', () {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  📊 Appwrite Sync Flow Benchmark — Summary');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  المنهجية:');
      debugPrint('    • يحاكي sync flow عبر drift operations حقيقية');
      debugPrint('    • شبكة latency محاكاة (50ms لكل دفعة)');
      debugPrint('    • لا يتطلب Appwrite SDK حقيقي (آمن في CI)');
      debugPrint('  المقاييس:');
      debugPrint('    • Push flow (takeBatch + network + markCompleted)');
      debugPrint('    • Pull flow (network + insertOne × N)');
      debugPrint('    • Full sync cycle (push + pull)');
      debugPrint('    • Conflict resolution (LWW)');
      debugPrint('    • Latency breakdown per phase');
      debugPrint('═══════════════════════════════════════════════════════════');
      expect(true, isTrue);
    });
  });
}
