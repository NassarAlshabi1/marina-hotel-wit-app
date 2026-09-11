// اختبارات تحسينات P1 (تقرير 2026-09-11) لاستراتيجية إعادة المحاولة:
// قائمة retryableErrors + مسند retryableErrorTest + إحصائيات إعادة المحاولة.
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_core/retry_strategy.dart';

class NetworkishError implements Exception {}

class AuthishError implements Exception {}

void main() {
  RetryConfig fastConfig({
    int maxAttempts = 3,
    List<Type> retryableErrors = const <Type>[],
    bool Function(dynamic error)? retryableErrorTest,
  }) => RetryConfig(
    maxAttempts: maxAttempts,
    initialDelay: const Duration(milliseconds: 1),
    maxDelay: const Duration(milliseconds: 5),
    retryableErrors: retryableErrors,
    retryableErrorTest: retryableErrorTest,
  );

  group('القائمة الفارغة = السلوك السابق', () {
    test('كل الأخطاء قابلة للإعادة والقرار للمتصل', () async {
      final rs = RetryStrategy(config: fastConfig());
      var calls = 0;
      final result = await rs.execute<int>(
        operation: () async {
          calls++;
          if (calls < 3) {
            throw NetworkishError();
          }
          return 7;
        },
        shouldRetry: (_) => true,
      );
      expect(result, 7);
      expect(calls, 3);
      expect(rs.isRetryableError(AuthishError()), isTrue);
    });
  });

  group('retryableErrors', () {
    test('النوع غير المدرج يُرفع فوراً دون استهلاك المحاولات', () async {
      final rs = RetryStrategy(
        config: fastConfig(
          maxAttempts: 5,
          retryableErrors: const <Type>[NetworkishError],
        ),
      );
      var calls = 0;
      await expectLater(
        rs.execute<int>(
          operation: () async {
            calls++;
            throw AuthishError();
          },
          shouldRetry: (_) => true,
        ),
        throwsA(isA<AuthishError>()),
      );
      expect(calls, 1, reason: 'لا إعادة ولا انتظار لنوع غير مدرج');
      expect(rs.totalBlockedByPolicy, 1);
      expect(rs.totalAttempts, 1);
    });

    test('النوع المدرج يُعاد محاولته بشكل طبيعي', () async {
      final rs = RetryStrategy(
        config: fastConfig(
          maxAttempts: 3,
          retryableErrors: const <Type>[NetworkishError],
        ),
      );
      var calls = 0;
      final result = await rs.execute<int>(
        operation: () async {
          calls++;
          if (calls == 1) {
            throw NetworkishError();
          }
          return 42;
        },
        shouldRetry: (_) => true,
      );
      expect(result, 42);
      expect(calls, 2);
      expect(rs.totalRetries, 1);
      expect(rs.totalBlockedByPolicy, 0);
    });

    test('المطابقة نوع runtimeType الدقيق', () {
      final rs = RetryStrategy(
        config: fastConfig(retryableErrors: const <Type>[NetworkishError]),
      );
      expect(rs.isRetryableError(NetworkishError()), isTrue);
      expect(rs.isRetryableError(AuthishError()), isFalse);
    });
  });

  group('retryableErrorTest', () {
    test('له الأولوية على القائمة', () async {
      // قائمة فارغة تعني نظرياً «كل شيء قابل» — لكن المسند يحكم حصرياً
      final rs = RetryStrategy(
        config: fastConfig(
          retryableErrorTest: (e) => e is NetworkishError,
        ),
      );
      expect(rs.isRetryableError(NetworkishError()), isTrue);
      expect(rs.isRetryableError(AuthishError()), isFalse);

      var calls = 0;
      await expectLater(
        rs.execute<int>(
          operation: () async {
            calls++;
            throw AuthishError();
          },
          shouldRetry: (_) => true,
        ),
        throwsA(isA<AuthishError>()),
      );
      expect(calls, 1);
    });
  });

  group('shouldRetryError — جمع السياستين', () {
    test('لا إعادة إلا إذا سمحت السياستان معاً', () {
      final rs = RetryStrategy(
        config: fastConfig(retryableErrors: const <Type>[NetworkishError]),
      );
      final net = NetworkishError();
      final auth = AuthishError();

      // سياسة المتصل تسمح + النوع مدرج → إعادة
      expect(rs.shouldRetryError(net, (_) => true), isTrue);
      // سياسة المتصل ترفض → لا إعادة مهما كان النوع
      expect(rs.shouldRetryError(net, (_) => false), isFalse);
      // سياسة المتصل تسمح + النوع غير مدرج → لا إعادة
      expect(rs.shouldRetryError(auth, (_) => true), isFalse);
    });
  });

  group('إحصائيات إعادة المحاولة', () {
    test('تحصي التنفيذات والمحاولات والإعادات', () async {
      final rs = RetryStrategy(config: fastConfig());
      var calls = 0;
      await rs.execute<int>(
        operation: () async {
          calls++;
          if (calls < 3) {
            throw NetworkishError();
          }
          return 1;
        },
        shouldRetry: (_) => true,
      );
      expect(rs.totalExecutions, 1);
      expect(rs.totalAttempts, 3);
      expect(rs.totalRetries, 2);
      expect(rs.totalExhausted, 0);
      expect(rs.totalBlockedByPolicy, 0);
      expect(rs.stats['maxAttempts'], 3);
    });

    test('تحصي الاستنفاد وآخر خطأ', () async {
      final rs = RetryStrategy(config: fastConfig(maxAttempts: 2));
      expect(rs.lastErrorAt, isNull);
      await expectLater(
        rs.execute<int>(
          operation: () async => throw NetworkishError(),
          shouldRetry: (_) => true,
        ),
        throwsA(isA<Exception>()),
      );
      expect(rs.totalExecutions, 1);
      expect(rs.totalAttempts, 2);
      expect(rs.totalExhausted, 1);
      expect(rs.lastErrorAt, isNotNull);
      expect(rs.lastErrorMessage, contains('NetworkishError'));
    });

    test('resetStats يصفّر كل شيء', () async {
      final rs = RetryStrategy(config: fastConfig());
      await expectLater(
        rs.execute<int>(
          operation: () async => throw NetworkishError(),
          shouldRetry: (_) => false,
        ),
        throwsA(isA<NetworkishError>()),
      );
      expect(rs.totalExecutions, 1);
      rs.resetStats();
      expect(rs.totalExecutions, 0);
      expect(rs.totalAttempts, 0);
      expect(rs.lastErrorAt, isNull);
      expect(rs.stats['totalRetries'], 0);
    });

    test('تنفيذ ناجح من أول محاولة بلا إعادات', () async {
      final rs = RetryStrategy(config: fastConfig());
      final result = await rs.execute<String>(
        operation: () async => 'ok',
        shouldRetry: (_) => true,
      );
      expect(result, 'ok');
      expect(rs.totalExecutions, 1);
      expect(rs.totalAttempts, 1);
      expect(rs.totalRetries, 0);
    });
  });
}
