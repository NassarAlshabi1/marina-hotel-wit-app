// ============================================================================
//  Marina Hotel — Outbox Processing Under Load Benchmark
//  ============================================================================
//  يقيس أداء معالجة outbox تحت حمل ثقيل (1000+ entries).
//
//  المقاييس:
//    1. زمن إضافة 1000 outbox entry (single + transaction)
//    2. زمن takeBatch(100) من 1000 entries
//    3. زمن countPendingPushable من 1000 entries
//    4. زمن markCompleted لـ 100 entries
//    5. زمن retryFailed من 50 failed entries
//    6. زمن reclaimForPush (استرجاع stuck entries)
//    7. زمن clearStale (تنظيف stale entries)
//
//  التشغيل:
//    flutter test test/performance/outbox_load_benchmark_test.dart \
//      --reporter=expanded
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars, avoid_redundant_argument_values

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OutboxDao outboxDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outboxDao = OutboxDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  1. Bulk Insert — 1000 entries
  // ═══════════════════════════════════════════════════════════════════════════
  group('📥 Bulk Insert (1000 entries)', () {
    test('إضافة 1000 outbox entry (single) خلال < 5 ثواني', () async {
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        await outboxDao.merge(
          entity: 'bookings',
          op: 'create',
          localUuid: 'bulk-single-$i',
          payload: {
            'id': i,
            'guestName': 'Guest $i',
            'roomNumber': '${100 + (i % 20)}',
            'amount': (i * 150.5).toStringAsFixed(2),
          },
          clientTs: i,
          source: 'local',
        );
      }
      stopwatch.stop();

      final count = await outboxDao.count();
      debugPrint('✓ Insert 1000 entries (single): ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('  Rate: ${(1000 / (stopwatch.elapsedMilliseconds + 1) * 1000).toStringAsFixed(0)} entries/sec');
      debugPrint('  Count: $count');

      expect(count, 1000);
      expect(stopwatch.elapsedMilliseconds, lessThan(5000),
          reason: '1000 single inserts يجب أن يكون < 5 ثواني');
    });

    test('إضافة 1000 outbox entry (transaction) خلال < 1 ثانية', () async {
      final stopwatch = Stopwatch()..start();
      await db.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'bulk-tx-$i',
            payload: {
              'id': i,
              'guestName': 'Guest TX $i',
              'amount': (i * 100.0).toStringAsFixed(2),
            },
            clientTs: i,
            source: 'local',
          );
        }
      });
      stopwatch.stop();

      final count = await outboxDao.count();
      debugPrint('✓ Insert 1000 entries (transaction): ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('  Rate: ${(1000 / (stopwatch.elapsedMilliseconds + 1) * 1000).toStringAsFixed(0)} entries/sec');
      debugPrint('  Speedup vs single: ~5x expected');

      expect(count, 1000);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000),
          reason: '1000 inserts في transaction يجب أن يكون < 1 ثانية');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  2. takeBatch — استرجاع دفعات من 1000 entries
  // ═══════════════════════════════════════════════════════════════════════════
  group('📦 takeBatch from 1000 entries', () {
    test('takeBatch(100) خلال < 50ms', () async {
      // إعداد: 1000 entries
      await db.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'batch-uuid-$i',
            payload: {'id': i},
            clientTs: i,
            source: 'local',
          );
        }
      });

      final stopwatch = Stopwatch()..start();
      final batch = await outboxDao.takeBatch(100);
      stopwatch.stop();

      debugPrint('✓ takeBatch(100) from 1000 entries: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('  Batch size: ${batch.length}');

      expect(batch.length, 100);
      expect(stopwatch.elapsedMilliseconds, lessThan(50),
          reason: 'takeBatch يجب أن يكون < 50ms حتى مع 1000 entries');
    });

    test('takeBatch(500) خلال < 100ms', () async {
      // إعداد: 1000 entries جديدة (لكل test setUp جديد)
      await db.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'batch500-uuid-$i',
            payload: {'id': i},
            clientTs: i,
            source: 'local',
          );
        }
      });

      final stopwatch = Stopwatch()..start();
      final batch = await outboxDao.takeBatch(500);
      stopwatch.stop();

      debugPrint('✓ takeBatch(500) from 1000 entries: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('  Batch size: ${batch.length}');

      expect(batch.length, 500);
      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'takeBatch(500) يجب أن يكون < 100ms');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  3. Count Queries — مع 1000 entries
  // ═══════════════════════════════════════════════════════════════════════════
  group('🔢 Count Queries (1000 entries)', () {
    test('count() خلال < 30ms', () async {
      // إعداد: 1000 entries
      await db.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'count-uuid-$i',
            payload: {'id': i},
            clientTs: i,
            source: 'local',
          );
        }
      });

      final stopwatch = Stopwatch()..start();
      final result = await outboxDao.count();
      stopwatch.stop();

      debugPrint('✓ count() from 1000 entries: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('  Count: $result');

      expect(result, 1000);
      expect(stopwatch.elapsedMilliseconds, lessThan(30),
          reason: 'count() يجب أن يكون < 30ms');
    });

    test('countPendingPushable() خلال < 30ms', () async {
      // إعداد: 1000 entries (نفس الـ db من test السابق قد تكون فارغة الآن
      // لأن كل test له setUp جديد، لكن نُعيد التأمين)
      await db.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'pending-uuid-$i',
            payload: {'id': i},
            clientTs: i,
            source: 'local',
          );
        }
      });

      final stopwatch = Stopwatch()..start();
      final result = await outboxDao.countPendingPushable();
      stopwatch.stop();

      debugPrint('✓ countPendingPushable() from 1000 entries: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('  Pending: $result');

      expect(stopwatch.elapsedMilliseconds, lessThan(30),
          reason: 'countPendingPushable يجب أن يكون < 30ms');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  4. markCompleted — إكمال 100 entries
  // ═══════════════════════════════════════════════════════════════════════════
  group('✅ markCompleted (100 entries)', () {
    test('markCompleted لـ 100 entries خلال < 100ms', () async {
      // إعداد: 1000 entries ثم أخذ batch من 100
      await db.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'completed-uuid-$i',
            payload: {'id': i},
            clientTs: i,
            source: 'local',
          );
        }
      });

      // أخذ batch من 100 entries أولاً
      final batch = await outboxDao.takeBatch(100);
      expect(batch.length, 100);

      final ids = batch.map((e) => e.id).toList();
      final stopwatch = Stopwatch()..start();
      await outboxDao.markCompleted(ids);
      stopwatch.stop();

      debugPrint('✓ markCompleted(100 entries): ${stopwatch.elapsedMilliseconds}ms');

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'markCompleted لـ 100 entries يجب أن يكون < 100ms');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  5. retryFailed — إعادة محاولة 50 failed entries
  // ═══════════════════════════════════════════════════════════════════════════
  group('🔄 retryFailed (50 entries)', () {
    test('retryFailed لـ 50 failed entries خلال < 100ms', () async {
      // إعداد: 1000 entries + أخذ 50 + markFailed
      await db.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'retry-uuid-$i',
            payload: {'id': i},
            clientTs: i,
            source: 'local',
          );
        }
      });

      // إنشاء 50 failed entries
      final batch = await outboxDao.takeBatch(50);
      final ids = batch.map((e) => e.id).toList();
      await outboxDao.markFailed(ids);

      final stopwatch = Stopwatch()..start();
      await outboxDao.retryFailed();
      stopwatch.stop();

      debugPrint('✓ retryFailed (50 entries): ${stopwatch.elapsedMilliseconds}ms');

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'retryFailed لـ 50 entries يجب أن يكون < 100ms');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  6. reclaimForPush — استرجاع stuck entries
  // ═══════════════════════════════════════════════════════════════════════════
  group('🔁 reclaimForPush', () {
    test('reclaimForPush من 1000 entries خلال < 200ms', () async {
      // إعداد: 1000 entries
      await db.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'reclaim-uuid-$i',
            payload: {'id': i},
            clientTs: i,
            source: 'local',
          );
        }
      });

      final stopwatch = Stopwatch()..start();
      final reclaimed = await outboxDao.reclaimForPush();
      stopwatch.stop();

      debugPrint('✓ reclaimForPush from 1000 entries: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('  Reclaimed: $reclaimed');

      expect(stopwatch.elapsedMilliseconds, lessThan(200),
          reason: 'reclaimForPush يجب أن يكون < 200ms');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  7. تقرير نهائي
  // ═══════════════════════════════════════════════════════════════════════════
  group('📊 Outbox Load Summary', () {
    test('طباعة ملخص مقاييس outbox تحت حمل', () {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  📊 Outbox Processing Under Load — Summary');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  المقاييس:');
      debugPrint('    • Bulk insert (1000 entries: single vs transaction)');
      debugPrint('    • takeBatch (100, 500 من 1000)');
      debugPrint('    • Count queries (count, countPendingPushable)');
      debugPrint('    • markCompleted (100 entries)');
      debugPrint('    • retryFailed (50 entries)');
      debugPrint('    • reclaimForPush (استرجاع stuck)');
      debugPrint('  DB: drift NativeDatabase.memory() (حقيقية)');
      debugPrint('═══════════════════════════════════════════════════════════');
      expect(true, isTrue);
    });
  });
}
