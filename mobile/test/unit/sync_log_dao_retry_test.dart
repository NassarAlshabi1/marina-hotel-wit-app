import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/daos/sync_log_dao.dart';

void main() {
  group('SyncLogRetryPolicy', () {
    test(
      'retries transient locks with 80/160/320ms backoff then succeeds',
      () async {
        var calls = 0;
        final waits = <Duration>[];

        final result = await SyncLogRetryPolicy.run<int>(
          () async {
            calls++;
            if (calls < 4) {
              throw Exception('SQLite_BUSY: database is locked');
            }
            return 42;
          },
          wait: (duration) async {
            waits.add(duration);
          },
        );

        expect(result, 42);
        expect(calls, 4);
        expect(
          waits,
          const [
            Duration(milliseconds: 80),
            Duration(milliseconds: 160),
            Duration(milliseconds: 320),
          ],
        );
      },
    );

    test(
      'uses four bounded waits and rethrows after the fifth lock failure',
      () async {
        var calls = 0;
        final waits = <Duration>[];
        final finalError = Exception(
          'SqliteException(517): database is locked',
        );

        await expectLater(
          SyncLogRetryPolicy.run<int>(
            () async {
              calls++;
              throw finalError;
            },
            wait: (duration) async {
              waits.add(duration);
            },
          ),
          throwsA(same(finalError)),
        );

        expect(calls, SyncLogRetryPolicy.maxAttempts);
        expect(waits, hasLength(SyncLogRetryPolicy.maxAttempts - 1));
        expect(waits.last, const Duration(milliseconds: 640));
      },
    );

    test('does not retry non-lock errors', () async {
      var calls = 0;

      await expectLater(
        SyncLogRetryPolicy.run<int>(() async {
          calls++;
          throw ArgumentError('malformed SQL');
        }),
        throwsArgumentError,
      );

      expect(calls, 1);
    });

    test(
      'recognizes BUSY and BUSY_SNAPSHOT but not unrelated SQLite errors',
      () {
        expect(
          SyncLogRetryPolicy.isRetryableLockError(
            Exception('SqliteException(517): database is locked'),
          ),
          isTrue,
        );
        expect(
          SyncLogRetryPolicy.isRetryableLockError(
            Exception('SQLite_BUSY (5)'),
          ),
          isTrue,
        );
        expect(
          SyncLogRetryPolicy.isRetryableLockError(
            Exception('SqliteException(10): disk I/O error'),
          ),
          isFalse,
        );
      },
    );
  });
}
