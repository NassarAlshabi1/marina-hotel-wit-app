// ============================================================================
//  Marina Hotel — Sync Operations Benchmark
//  ============================================================================
//  يقيس أداء عمليات المزامنة الحقيقية عبر drift database + outbox.
//
//  المقاييس:
//    1. زمن إضافة 100 outbox entry (outbox merge)
//    2. زمن takeBatch (استرجاع دفعة للرفع)
//    3. زمن transaction لإضافة 50 مصروف + 50 outbox entry
//    4. زمن استعلام outbox countPendingPushable
//    5. مقارنة single insert vs batch insert
//
//  التشغيل:
//    flutter test test/performance/sync_operations_benchmark_test.dart \
//      --reporter=expanded
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars, avoid_redundant_argument_values, prefer_const_constructors

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/daos/expenses_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
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
  //  1. Outbox merge — إضافة 100 entry
  // ═══════════════════════════════════════════════════════════════════════════
  group('📤 Outbox Merge Performance', () {
    test('إضافة 100 outbox entry خلال < 500ms', () async {
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        await outboxDao.merge(
          entity: 'bookings',
          op: 'create',
          localUuid: 'uuid-$i',
          payload: {
            'id': i,
            'guestName': 'Guest $i',
            'roomNumber': '${100 + (i % 20)}',
            'amount': (i * 150.5).toStringAsFixed(2),
          },
          clientTs: DateTime.now().millisecondsSinceEpoch,
          source: 'local',
        );
      }
      stopwatch.stop();

      debugPrint(
        '✓ Outbox merge 100 entries: ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint(
        '  Rate: ${(100 / (stopwatch.elapsedMilliseconds + 1) * 1000).toStringAsFixed(0)} entries/sec',
      );

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: 'إضافة 100 outbox entry يجب أن يكون < 500ms',
      );
    });

    test('إضافة 100 outbox entry في transaction خلال < 200ms', () async {
      final stopwatch = Stopwatch()..start();
      await db.transaction(() async {
        for (var i = 0; i < 100; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'update',
            localUuid: 'uuid-tx-$i',
            payload: {
              'id': i,
              'guestName': 'Guest TX $i',
              'amount': (i * 100.0).toStringAsFixed(2),
            },
            clientTs: DateTime.now().millisecondsSinceEpoch,
            source: 'local',
          );
        }
      });
      stopwatch.stop();

      debugPrint(
        '✓ Outbox merge 100 entries (transaction): ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint(
        '  Speedup vs single: ~${(500 / (stopwatch.elapsedMilliseconds + 1)).toStringAsFixed(1)}x expected',
      );

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(200),
        reason: 'transaction يجب أن يكون أسرع بكثير من single inserts',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  2. takeBatch — استرجاع دفعة للرفع
  // ═══════════════════════════════════════════════════════════════════════════
  group('📦 takeBatch Performance', () {
    test('takeBatch(50) من 100 entry خلال < 50ms', () async {
      // إعداد: إضافة 100 entry أولاً
      for (var i = 0; i < 100; i++) {
        await outboxDao.merge(
          entity: 'bookings',
          op: 'create',
          localUuid: 'batch-uuid-$i',
          payload: {'id': i, 'name': 'Item $i'},
          clientTs: i,
          source: 'local',
        );
      }

      final stopwatch = Stopwatch()..start();
      final batch = await outboxDao.takeBatch(50);
      stopwatch.stop();

      debugPrint(
        '✓ takeBatch(50) from 100 entries: ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('  Batch size: ${batch.length}');

      expect(batch.length, 50);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(50),
        reason: 'takeBatch يجب أن يكون سريعاً جداً (< 50ms)',
      );
    });

    test('countPendingPushable من 200 entry خلال < 30ms', () async {
      // إعداد: 200 entry
      for (var i = 0; i < 200; i++) {
        await outboxDao.merge(
          entity: 'bookings',
          op: 'create',
          localUuid: 'count-uuid-$i',
          payload: {'id': i},
          clientTs: i,
          source: 'local',
        );
      }

      final stopwatch = Stopwatch()..start();
      final count = await outboxDao.countPendingPushable();
      stopwatch.stop();

      debugPrint(
        '✓ countPendingPushable (200 entries): ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('  Count: $count');

      expect(count, 200);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(30),
        reason: 'count query يجب أن يكون < 30ms',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  3. Comprehensive sync flow — إضافة مصروف + outbox entry
  // ═══════════════════════════════════════════════════════════════════════════
  group('🔄 Comprehensive Sync Flow', () {
    test('50 مصروف + 50 outbox entry في transaction خلال < 1 ثانية', () async {
      // إعداد: إنشاء غرفة واحدة (foreign key)
      final roomsDao = RoomsDao(db, outboxDao);
      await roomsDao.insertOne(
        RoomsCompanion(
          roomNumber: const d.Value('101'),
          type: const d.Value('عادية'),
          price: const d.Value(100.0),
          status: const d.Value('شاغرة'),
          localUuid: const d.Value('room-101-uuid'),
        ),
      );

      final expensesDao = ExpensesDao(db, outboxDao);
      final now = DateTime.now();

      final stopwatch = Stopwatch()..start();
      await db.transaction(() async {
        for (var i = 0; i < 50; i++) {
          await expensesDao.insertOne(
            ExpensesCompanion(
              expenseType: const d.Value('صيانة'),
              description: d.Value('مصروف $i'),
              amount: d.Value((i + 1) * 10.0),
              date: d.Value(now.toIso8601String()),
              hotelDayKey: const d.Value('2026-07-20'),
              localUuid: d.Value('sync-expense-$i'),
            ),
          );
          // كل مصروف يُنشئ outbox entry تلقائياً عبر DAO
        }
      });
      stopwatch.stop();

      final outboxCount = await outboxDao.countPendingPushable();

      debugPrint(
        '✓ 50 expenses + outbox entries (transaction): ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('  Outbox count: $outboxCount');
      debugPrint(
        '  Rate: ${(50 / (stopwatch.elapsedMilliseconds + 1) * 1000).toStringAsFixed(0)} expenses/sec',
      );

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1000),
        reason: '50 مصروف + outbox entries يجب أن يكون < 1 ثانية',
      );
      expect(
        outboxCount,
        greaterThan(0),
        reason: 'كل مصروف يجب أن يُنشئ outbox entry',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  4. Single vs Batch Insert Comparison
  // ═══════════════════════════════════════════════════════════════════════════
  group('⚖️ Single vs Batch Insert', () {
    test('batch insert أسرع من single insert لـ 50 outbox entry', () async {
      // نستخدم outbox بدلاً من bookings لتجنب foreign key constraints.
      // outbox entries لا تتطلب foreign key.

      // 1) Single inserts (بدون transaction)
      final singleStopwatch = Stopwatch()..start();
      for (var i = 0; i < 50; i++) {
        await outboxDao.merge(
          entity: 'bookings',
          op: 'create',
          localUuid: 'single-outbox-$i',
          payload: {'id': i, 'name': 'Single $i'},
          clientTs: i,
          source: 'local',
        );
      }
      singleStopwatch.stop();

      // 2) Batch inserts (في transaction)
      final batchStopwatch = Stopwatch()..start();
      await db.transaction(() async {
        for (var i = 0; i < 50; i++) {
          await outboxDao.merge(
            entity: 'bookings',
            op: 'create',
            localUuid: 'batch-outbox-$i',
            payload: {'id': i, 'name': 'Batch $i'},
            clientTs: i + 1000,
            source: 'local',
          );
        }
      });
      batchStopwatch.stop();

      final speedup =
          singleStopwatch.elapsedMilliseconds /
          (batchStopwatch.elapsedMilliseconds + 1);

      debugPrint('✓ Single vs Batch insert (50 outbox entries):');
      debugPrint('  Single inserts:  ${singleStopwatch.elapsedMilliseconds}ms');
      debugPrint('  Batch (tx):      ${batchStopwatch.elapsedMilliseconds}ms');
      debugPrint('  Speedup:         ${speedup.toStringAsFixed(2)}x');

      // batch يجب أن يكون أسرع (أو على الأقل مساوياً مع تقلبات CI)
      expect(
        batchStopwatch.elapsedMilliseconds,
        lessThanOrEqualTo(singleStopwatch.elapsedMilliseconds + 50),
        reason: 'batch insert يجب أن يكون أسرع من single inserts',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  5. تقرير نهائي
  // ═══════════════════════════════════════════════════════════════════════════
  group('📊 Sync Performance Summary', () {
    test('طباعة ملخص مقاييس المزامنة', () {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  📊 Sync Operations Benchmark — Summary');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  يقيس:');
      debugPrint('    • Outbox merge (single + transaction)');
      debugPrint('    • takeBatch (استرجاع دفعة للرفع)');
      debugPrint('    • countPendingPushable (عدّ السجلات المعلّقة)');
      debugPrint('    • Comprehensive flow (مصروف + outbox)');
      debugPrint('    • Single vs Batch insert comparison');
      debugPrint('  DB: drift NativeDatabase.memory() (حقيقية)');
      debugPrint('═══════════════════════════════════════════════════════════');
      expect(true, isTrue);
    });
  });
}
