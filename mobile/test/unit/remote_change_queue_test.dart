import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/remote_change_queue.dart';

void main() {
  group('RemoteChangeQueue trigger-only batching', () {
    test('coalesces a burst into one batch', () async {
      final batches = <List<PendingRemoteRecord>>[];
      final queue = RemoteChangeQueue(
        debounce: const Duration(milliseconds: 10),
        onFlush: (changes) async {
          batches.add(changes);
        },
      );
      addTearDown(queue.dispose);

      for (var i = 0; i < 10; i++) {
        queue.add(
          PendingRemoteRecord(
            collectionId: 'payments',
            documentId: 'payment-$i',
            operation: RemoteOperation.update,
          ),
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(batches, hasLength(1));
      expect(batches.single, hasLength(10));
    });

    test(
      'coalesces repeated events for one record to its latest event',
      () async {
        final batches = <List<PendingRemoteRecord>>[];
        final queue = RemoteChangeQueue(
          debounce: const Duration(milliseconds: 10),
          onFlush: (changes) async {
            batches.add(changes);
          },
        );
        addTearDown(queue.dispose);

        queue.add(
          const PendingRemoteRecord(
            collectionId: 'payments',
            documentId: 'payment-1',
            operation: RemoteOperation.create,
          ),
        );
        queue.add(
          const PendingRemoteRecord(
            collectionId: 'payments',
            documentId: 'payment-1',
            operation: RemoteOperation.update,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(batches, hasLength(1));
        expect(batches.single, hasLength(1));
        expect(batches.single.single.operation, RemoteOperation.update);
      },
    );

    test(
      'keeps a new batch pending while the current trigger is in flight',
      () async {
        final releaseFirst = Completer<void>();
        final firstTriggerStarted = Completer<void>();
        final batches = <List<PendingRemoteRecord>>[];
        final queue = RemoteChangeQueue(
          debounce: const Duration(milliseconds: 10),
          onFlush: (changes) async {
            batches.add(changes);
            if (batches.length == 1) {
              firstTriggerStarted.complete();
              await releaseFirst.future;
            }
          },
        );
        addTearDown(queue.dispose);

        queue.add(
          const PendingRemoteRecord(
            collectionId: 'payments',
            documentId: 'payment-1',
            operation: RemoteOperation.update,
          ),
        );
        await firstTriggerStarted.future;

        queue.add(
          const PendingRemoteRecord(
            collectionId: 'expenses',
            documentId: 'expense-1',
            operation: RemoteOperation.update,
          ),
        );
        releaseFirst.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(batches, hasLength(2));
        expect(batches[0].single.collectionId, 'payments');
        expect(batches[1].single.collectionId, 'expenses');
      },
    );
  });
}
