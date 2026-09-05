import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_realtime_sync.dart';

void main() {
  group('RemoteChangeQueue', () {
    test('deduplicates repeated events for the same remote document', () {
      final queue = RemoteChangeQueue();
      queue.add(collection: 'payments', documentId: 'p1', event: 'update');
      queue.add(collection: 'payments', documentId: 'p1', event: 'update');
      queue.add(collection: 'payments', documentId: 'p1', event: 'delete');

      expect(queue.length, 2);
      expect(queue.drain(), hasLength(2));
      expect(queue.isEmpty, isTrue);
    });
  });

  group('AppwriteRealtimeSync trigger-only ingress', () {
    late AppwriteRealtimeSync realtime;

    setUp(() {
      realtime = AppwriteRealtimeSync();
      realtime.stop();
      realtime.remoteChangeQueue.clear();
      realtime.resetRemoteChangesFlag();
    });

    tearDown(() async {
      await realtime.stop();
    });

    test('coalesces a burst into one Delta pull callback', () async {
      var pulls = 0;
      final completed = Completer<void>();
      // The production singleton receives its callback at startup; this test
      // validates the ingress contract through the public test hook.
      await realtime.initialize(
        deviceId: 'test-device',
        deltaPull: () async {
          pulls++;
          completed.complete();
          return true;
        },
      );

      for (var i = 0; i < 10; i++) {
        realtime.enqueueForTesting(collection: 'payments', documentId: 'p$i');
      }

      await completed.future.timeout(const Duration(seconds: 2));
      // العلم يُصفَّر بعد عودة الـcallback مباشرة (microtask لاحق) — استقرار
      // قصير قبل الجزم لتجنّب السباق مع سلسلة _runDeltaPull.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(pulls, 1);
      expect(realtime.hasRemoteChanges.value, isFalse);
    });

    test('keeps the queue when Delta pull fails', () async {
      final attempted = Completer<void>();
      await realtime.initialize(
        deviceId: 'test-device',
        deltaPull: () async {
          attempted.complete();
          throw StateError('offline');
        },
      );

      realtime.enqueueForTesting(
        collection: 'payments',
        documentId: 'p-offline',
      );
      await attempted.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(realtime.remoteChangeQueue.isEmpty, isFalse);
      expect(realtime.hasRemoteChanges.value, isTrue);
    });
  });
}
