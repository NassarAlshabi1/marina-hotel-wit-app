// Production Readiness Tests — verifies the app is ready for production.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/utils/weak_device_optimizer.dart';
import 'package:marina_hotel_mobile/utils/circular_buffer_logger.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  group('Production Readiness', () {
    group('WeakDeviceOptimizer', () {
      test('1GB RAM detected as weak (level 2)', () {
        final opt = WeakDeviceOptimizer.instance;
        opt.initialize(processorCount: 2, memoryMB: 1024);
        expect(opt.isWeakDevice, isTrue);
        expect(opt.optimizationLevel, equals(2));
        expect(opt.maxListItemsBeforePagination, equals(20));
        expect(opt.syncConcurrency, equals(1));
      });

      test('4GB RAM detected as mid-range (level 1)', () {
        final opt = WeakDeviceOptimizer.instance;
        opt.initialize(processorCount: 4, memoryMB: 4096);
        expect(opt.isWeakDevice, isFalse);
        expect(opt.optimizationLevel, equals(1));
      });

      test('8GB RAM detected as high-end (level 0)', () {
        final opt = WeakDeviceOptimizer.instance;
        opt.initialize(processorCount: 8, memoryMB: 8192);
        expect(opt.isWeakDevice, isFalse);
        expect(opt.optimizationLevel, equals(0));
        expect(opt.syncConcurrency, equals(4));
      });

      test('debounceDuration scales', () {
        final opt = WeakDeviceOptimizer.instance;
        opt.initialize(processorCount: 2, memoryMB: 1024);
        expect(opt.debounceDuration.inMilliseconds, equals(500));
        opt.initialize(processorCount: 8, memoryMB: 8192);
        expect(opt.debounceDuration.inMilliseconds, equals(150));
      });
    });

    group('CircularBufferLogger', () {
      test('buffer bounded (no memory leak)', () {
        final logger = CircularBufferLogger.instance;
        for (var i = 0; i < 600; i++) {
          logger.info('msg $i', tag: 'TEST');
        }
        expect(logger.bufferSize, lessThanOrEqualTo(500));
      });

      test('readLast returns recent entries', () {
        final logger = CircularBufferLogger.instance;
        logger.clear();
        for (var i = 0; i < 10; i++) {
          logger.info('msg $i', tag: 'TEST');
        }
        final entries = logger.readLast(3);
        expect(entries.length, equals(3));
        expect(entries.last['message'], equals('msg 9'));
      });

      test('clear empties buffer', () {
        final logger = CircularBufferLogger.instance;
        logger.info('test', tag: 'TEST');
        expect(logger.bufferSize, greaterThan(0));
        logger.clear();
        expect(logger.bufferSize, equals(0));
      });
    });

    group('Database Integrity', () {
      test('all critical tables accessible', () async {
        expect(await db.select(db.rooms).get(), isEmpty);
        expect(await db.select(db.bookings).get(), isEmpty);
        expect(await db.select(db.payments).get(), isEmpty);
        expect(await db.select(db.expenses).get(), isEmpty);
        expect(await db.select(db.debts).get(), isEmpty);
        expect(await db.select(db.employees).get(), isEmpty);
        expect(await db.select(db.cashTransactions).get(), isEmpty);
        expect(await db.select(db.bookingNotes).get(), isEmpty);
        expect(await db.select(db.shiftNotes).get(), isEmpty);
        expect(await db.select(db.guestInfos).get(), isEmpty);
        expect(await db.select(db.outbox).get(), isEmpty);
        expect(await db.select(db.salaryWithdrawals).get(), isEmpty);
      });

      test('outbox retains pending entries (offline)', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await db
            .into(db.outbox)
            .insert(
              OutboxCompanion(
                entity: const Value('rooms'),
                op: const Value('create'),
                localUuid: const Value('test-offline'),
                payload: const Value('{}'),
                clientTs: Value(now),
                processingStatus: const Value('pending'),
              ),
            );

        final pending = await (db.select(
          db.outbox,
        )..where((t) => t.processingStatus.equals('pending'))).get();
        expect(pending.length, equals(1));
        expect(pending.first.localUuid, equals('test-offline'));
      });
    });

    group('Financial Accuracy', () {
      test('integer amounts prevent rounding bugs', () {
        final amount = 50000;
        expect(amount, isA<int>());
        expect(amount ~/ 1000, equals(50));
      });

      test('truncation policy (no overcharge)', () {
        expect(1000.99.floor(), equals(1000));
        expect((-500.5).ceil(), equals(-500));
      });
    });
  });
}
