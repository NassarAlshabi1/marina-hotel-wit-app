import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_mutex.dart';

void main() {
  group('SyncMutex', () {
    late SyncMutex mutex;

    setUp(() {
      mutex = SyncMutex();
    });

    test('acquire/release basic functionality', () async {
      expect(await mutex.acquire(), isTrue);
      mutex.release();
      expect(await mutex.acquire(), isTrue);
    });

    test('rejects concurrent acquire', () async {
      await mutex.acquire();
      final result = await mutex.acquire(timeout: Duration(milliseconds: 50));
      expect(result, isFalse);
      mutex.release();
    });

    test('runExclusive executes action exclusively', () async {
      int counter = 0;
      final futures = List.generate(10, (_) => mutex.runExclusive(() async {
        await Future.delayed(Duration(milliseconds: 10));
        counter++;
        return counter;
      }));

      final results = await Future.wait(futures);
      expect(counter, equals(10));
      expect(results.toSet().length, equals(10));
    });

    test('runExclusive returns null on timeout', () async {
      await mutex.acquire();
      final result = await mutex.runExclusive(() async => 42, timeout: Duration(milliseconds: 10));
      expect(result, isNull);
      mutex.release();
    });

    test('handles rapid acquire/release cycles', () async {
      for (int i = 0; i < 100; i++) {
        expect(await mutex.acquire(timeout: Duration(milliseconds: 10)), isTrue);
        mutex.release();
      }
    });

    test('no deadlock when release called without acquire', () {
      expect(() => mutex.release(), returnsNormally);
    });

    test('multiple waiters - only one acquires', () async {
      await mutex.acquire();
      final completers = List.generate(5, (_) => Completer<bool>());
      
      for (final c in completers) {
        unawaited(mutex.acquire(timeout: Duration(seconds: 1)).then(c.complete));
      }
      
      await Future.delayed(Duration(milliseconds: 50));
      mutex.release();
      
      final results = await Future.wait(completers.map((c) => c.future));
      expect(results.where((r) => r == true).length, equals(1));
    });

    test('stress test - concurrent runExclusive', () async {
      const iterations = 50;
      int successCount = 0;
      
      final futures = List.generate(iterations, (i) => mutex.runExclusive(() async {
        await Future.delayed(Duration(milliseconds: 5));
        successCount++;
        return i;
      }));
      
      await Future.wait(futures);
      expect(successCount, equals(iterations));
    });
  });
}