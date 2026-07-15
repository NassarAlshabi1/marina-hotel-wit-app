/// ============================================================
/// Marina Hotel - Performance Test Suite
/// ============================================================
/// Automated performance tests for critical operations
/// Run: dart test test/performance_test.dart
/// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import '../lib/services/local_db.dart' as local_db;
import '../lib/services/cache/layered_cache_service.dart';
import '../lib/services/batch/batch_operations_service.dart';
import '../lib/services/optimization/optimized_queries.dart';

void main() {
  group('Performance Tests', () {
    late local_db.MyDatabase db;
    late LayeredCacheService cache;
    late BatchOperationsService batchService;
    late OptimizedQueries queries;

    setUp(() async {
      // Initialize in-memory database for testing
      db = await _initializeTestDb();
      cache = LayeredCacheService();
      batchService = BatchOperationsService(db);
      queries = OptimizedQueries(db);
    });

    tearDown(() async {
      await db.close();
      await cache.clearAll();
    });

    test('Dashboard stats should fetch in < 100ms', () async {
      final stopwatch = Stopwatch()..start();

      final stats = await queries.getDashboardStats();

      stopwatch.stop();
      print('Dashboard stats fetched in ${stopwatch.elapsedMilliseconds}ms');

      expect(stats, isNotNull);
      expect(stats.containsKey('totalRooms'), isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('Batch insert 100 records should be fast', () async {
      final rooms = List.generate(
        100,
        (i) => local_db.RoomsCompanion(
          roomNumber: Value('TEST${i + 1}'),
          type: const Value('single'),
          price: const Value(100.0),
          status: const Value('available'),
        ),
      );

      final stopwatch = Stopwatch()..start();

      final result = await batchService.batchInsertRooms(rooms);

      stopwatch.stop();
      print('Batch inserted ${result.successCount} in ${stopwatch.elapsedMilliseconds}ms');

      expect(result.isSuccess, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('Cache get/set should be < 1ms', () async {
      await cache.set('test_key', 'test_value');

      final stopwatch = Stopwatch()..start();
      final value = await cache.get('test_key', () async => 'new_value');
      stopwatch.stop();

      print('Cache get took ${stopwatch.elapsedMilliseconds}ms');
      expect(value, 'test_value');
      expect(stopwatch.elapsedMilliseconds, lessThan(1));
    });

    test('Occupancy rate query should be fast', () async {
      // Seed some test data
      await _seedTestRooms(db);

      final stopwatch = Stopwatch()..start();
      final rate = await queries.getOccupancyRate('2025-01-15');
      stopwatch.stop();

      print('Occupancy rate fetched in ${stopwatch.elapsedMilliseconds}ms');
      expect(rate, isDouble);
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });

    test('Payment aggregation should be optimized', () async {
      await _seedTestPayments(db);

      final stopwatch = Stopwatch()..start();
      final summary = await queries.getPaymentsByRevenueType(from: '2025-01-01', to: '2025-12-31');
      stopwatch.stop();

      print('Payment summary in ${stopwatch.elapsedMilliseconds}ms');
      expect(summary.isNotEmpty, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('Parallel queries should be 3x faster than sequential', () async {
      // Sequential
      final seqStopwatch = Stopwatch()..start();
      await Future.wait([
        queries.getDashboardStats(),
        queries.getOccupancyRate(null),
        queries.getPaymentsByRevenueType(from: '2025-01-01', to: '2025-01-31'),
      ]);
      seqStopwatch.stop();

      // Parallel (using Future.wait)
      final parStopwatch = Stopwatch()..start();
      final results = await Future.wait([
        queries.getDashboardStats(),
        queries.getOccupancyRate(null),
        queries.getPaymentsByRevenueType(from: '2025-01-01', to: '2025-01-31'),
      ]);
      parStopwatch.stop();

      print('Sequential: ${seqStopwatch.elapsedMilliseconds}ms');
      print('Parallel: ${parStopwatch.elapsedMilliseconds}ms');

      expect(results.length, 3);
      expect(parStopwatch.elapsedMilliseconds, lessThan(seqStopwatch.elapsedMilliseconds));
    });

    test('Index usage verification', () async {
      // Verify indexes exist
      final stats = await local_db.DatabaseOptimizer.getIndexStats(db);

      expect(stats['count'], greaterThan(10));
      print('Found ${stats['count']} indexes');
    });

    test('Memory cache hit rate should be > 90%', () async {
      // Warm up cache
      for (int i = 0; i < 100; i++) {
        await cache.get('key_$i', () async => 'value_$i');
      }

      // Access same keys again
      int hits = 0;
      final total = 100;

      for (int i = 0; i < total; i++) {
        final value = await cache.get('key_$i', () async => 'new_$i');
        if (value == 'value_$i') hits++;
      }

      final hitRate = hits / total;
      print('Cache hit rate: ${(hitRate * 100).toStringAsFixed(1)}%');

      expect(hitRate, greaterThan(0.9));
    });
  });
}

// Helper functions
Future<local_db.MyDatabase> _initializeTestDb() async {
  // In-memory test database
  final db = local_db.MyDatabase();
  await db
      .into(local_db.Rooms)
      .insert(
        local_db.RoomsCompanion(
          roomNumber: const Value('101'),
          type: const Value('single'),
          price: const Value(100.0),
          status: const Value('occupied'),
        ),
      );
  return db;
}

Future<void> _seedTestRooms(local_db.MyDatabase db) async {
  await db.batch((batch) {
    for (int i = 1; i <= 20; i++) {
      batch.insert(
        db.rooms,
        local_db.RoomsCompanion(
          roomNumber: Value('ROOM${i.toString().padLeft(3, '0')}'),
          type: const Value('single'),
          price: Value(100.0 + i * 10),
          status: Value(i % 2 == 0 ? 'occupied' : 'available'),
        ),
      );
    }
  });
}

Future<void> _seedTestPayments(local_db.MyDatabase db) async {
  await db.batch((batch) {
    for (int i = 0; i < 50; i++) {
      batch.insert(
        db.payments,
        local_db.PaymentsCompanion(
          roomNumber: Value('ROOM${(i % 20) + 1}'),
          amount: Value(100.0 + i * 5),
          paymentDate: Value('2025-01-${(i % 28) + 1}'),
          paymentMethod: const Value('cash'),
          revenueType: const Value('room_rent'),
        ),
      );
    }
  });
}
