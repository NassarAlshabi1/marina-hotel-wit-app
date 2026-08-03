// ignore_for_file: lines_longer_than_80_chars
import 'package:appwrite/appwrite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_network_helper.dart';

/// اختبارات وحدوية لـ AppwriteNetworkHelper.
///
/// تُغطّي المنطق النقي المسؤول عن السلوك الظاهر في سجلات الإنتاج:
///   • تصنيف 429 (rate limit) — من code / type / نص الرسالة
///   • تصنيف الأخطاء القابلة/غير القابلة لإعادة المحاولة (4xx مقابل 5xx/شبكة)
///   • تمييز خطأ circuit_breaker المحلي عن 429 الحقيقي من السيرفر
///   • استخراج Retry-After من رسالة الخطأ
///   • تفعيل/تصفير الـ circuit breaker وعدّاد 429 المتتالي
///   • حساب backoff الأُسّي (calculateBackoff)
///
/// كلها تعمل دون انتظار حقيقي (لا تستدعي withRetry الذي ينام 60s+).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final helper = AppwriteNetworkHelper();

  // الكائن singleton — نُصفّر الحالة قبل كل اختبار حتى لا تتسرّب.
  setUp(helper.resetForTest);
  tearDown(helper.resetForTest);

  group('تصنيف 429 (isRateLimitError)', () {
    test('code == 429 → true', () {
      expect(helper.isRateLimitErrorForTest(AppwriteException('too many', 429)), isTrue);
    });

    test('type general_rate_limit_exceeded → true', () {
      expect(
        helper.isRateLimitErrorForTest(AppwriteException('nope', 400, 'general_rate_limit_exceeded')),
        isTrue,
      );
    });

    test('type rate_limit → true', () {
      expect(helper.isRateLimitErrorForTest(AppwriteException('x', 400, 'rate_limit')), isTrue);
    });

    test('نص عادي يحتوي 429 → true', () {
      expect(helper.isRateLimitErrorForTest('Error: request failed 429'), isTrue);
    });

    test('نص يحتوي "rate limit" → true', () {
      expect(helper.isRateLimitErrorForTest('Server returned rate limit'), isTrue);
    });

    test('404 ليس rate limit → false', () {
      expect(helper.isRateLimitErrorForTest(AppwriteException('not found', 404, 'document_not_found')), isFalse);
    });

    test('500 ليس rate limit → false', () {
      expect(helper.isRateLimitErrorForTest(AppwriteException('server', 500)), isFalse);
    });
  });

  group('تصنيف قابلية إعادة المحاولة (isRetriableError)', () {
    test('429 قابل لإعادة المحاولة (يُحلّ بالانتظار)', () {
      expect(helper.isRetriableErrorForTest(AppwriteException('too many requests 429', 429)), isTrue);
    });

    test('500 قابل لإعادة المحاولة', () {
      expect(helper.isRetriableErrorForTest(AppwriteException('internal 500', 500)), isTrue);
    });

    test('503 قابل لإعادة المحاولة', () {
      expect(helper.isRetriableErrorForTest(AppwriteException('unavailable 503', 503)), isTrue);
    });

    test('400 غير قابل لإعادة المحاولة', () {
      expect(helper.isRetriableErrorForTest(AppwriteException('bad request', 400)), isFalse);
    });

    test('401 غير قابل لإعادة المحاولة', () {
      expect(helper.isRetriableErrorForTest(AppwriteException('unauthorized', 401)), isFalse);
    });

    test('403 غير قابل لإعادة المحاولة', () {
      expect(helper.isRetriableErrorForTest(AppwriteException('forbidden', 403)), isFalse);
    });

    test('404 document_not_found غير قابل لإعادة المحاولة', () {
      expect(helper.isRetriableErrorForTest(AppwriteException('not found', 404, 'document_not_found')), isFalse);
    });

    test('409 document_already_exists غير قابل لإعادة المحاولة', () {
      expect(
        helper.isRetriableErrorForTest(AppwriteException('exists', 409, 'document_already_exists')),
        isFalse,
      );
    });

    test('402 (حد القراءة) غير قابل لإعادة المحاولة', () {
      // limit_databases_reads_exceeded — كما في السجلات؛ إعادة المحاولة بلا فائدة.
      expect(
        helper.isRetriableErrorForTest(AppwriteException('reads exceeded', 402, 'limit_databases_reads_exceeded')),
        isFalse,
      );
    });

    test('خطأ شبكة (Failed host lookup) قابل لإعادة المحاولة', () {
      expect(helper.isRetriableErrorForTest('SocketException: Failed host lookup'), isTrue);
    });

    test('timeout قابل لإعادة المحاولة', () {
      expect(helper.isRetriableErrorForTest('Operation timeout occurred'), isTrue);
    });

    test('connection refused قابل لإعادة المحاولة', () {
      expect(helper.isRetriableErrorForTest('connection refused'), isTrue);
    });
  });

  group('تمييز circuit breaker المحلي (isCircuitBreakerActive)', () {
    test('type circuit_breaker_active → true', () {
      expect(
        helper.isCircuitBreakerErrorForTest(AppwriteException('cooldown', 429, 'circuit_breaker_active')),
        isTrue,
      );
    });

    test('429 حقيقي من السيرفر (بلا type breaker) → false', () {
      expect(helper.isCircuitBreakerErrorForTest(AppwriteException('too many', 429)), isFalse);
    });
  });

  group('استخراج Retry-After (extractRetryAfter)', () {
    test('"try again after 30 seconds" → 30s', () {
      final d = helper.extractRetryAfterForTest(AppwriteException('please try again after 30 seconds', 429));
      expect(d, const Duration(seconds: 30));
    });

    test('"retry after 45s" → 45s', () {
      final d = helper.extractRetryAfterForTest(AppwriteException('retry after 45s', 429));
      expect(d, const Duration(seconds: 45));
    });

    test('بلا نمط زمني → null', () {
      expect(helper.extractRetryAfterForTest(AppwriteException('rate limited', 429)), isNull);
    });

    test('قيمة خارج الحدود (700s > 600) → null', () {
      expect(helper.extractRetryAfterForTest(AppwriteException('try again after 700 seconds', 429)), isNull);
    });
  });

  group('circuit breaker: التفعيل والتصفير', () {
    test('يبدأ مغلقاً بعد resetForTest', () {
      expect(helper.isCircuitBreakerActive, isFalse);
      expect(helper.circuitBreakerRemaining, isNull);
      expect(helper.consecutiveRateLimitHitsForTest, 0);
    });

    test('أقل من العتبة (4 ضربات) لا يُفعّل الـ breaker', () {
      for (var i = 0; i < 4; i++) {
        helper.simulateRateLimitHitForTest();
      }
      expect(helper.consecutiveRateLimitHitsForTest, 4);
      expect(helper.isCircuitBreakerActive, isFalse);
    });

    test('5 ضربات متتالية تُفعّل الـ breaker', () {
      for (var i = 0; i < 5; i++) {
        helper.simulateRateLimitHitForTest();
      }
      expect(helper.isCircuitBreakerActive, isTrue);
      final remaining = helper.circuitBreakerRemaining;
      expect(remaining, isNotNull);
      // أول تفعيل = تهدئة 60s.
      expect(remaining!.inSeconds, inInclusiveRange(55, 60));
    });

    test('نجاح طلب يصفّر عدّاد 429 المتتالي', () {
      for (var i = 0; i < 3; i++) {
        helper.simulateRateLimitHitForTest();
      }
      expect(helper.consecutiveRateLimitHitsForTest, 3);
      helper.simulateSuccessForTest();
      expect(helper.consecutiveRateLimitHitsForTest, 0);
    });

    test('resetForTest يمسح كل الحالة', () {
      for (var i = 0; i < 6; i++) {
        helper.simulateRateLimitHitForTest();
      }
      expect(helper.isCircuitBreakerActive, isTrue);
      helper.resetForTest();
      expect(helper.isCircuitBreakerActive, isFalse);
      expect(helper.circuitBreakerRemaining, isNull);
      expect(helper.consecutiveRateLimitHitsForTest, 0);
    });
  });

  group('calculateBackoff (backoff أُسّي)', () {
    test('بلا jitter: القيمة حتمية ومتوقّعة', () {
      // base=2000ms, mult=2.0 → exp = 2000 * (2 * attempt)
      final b1 = helper.calculateBackoff(attempt: 1, addJitter: false);
      final b2 = helper.calculateBackoff(attempt: 2, addJitter: false);
      final b3 = helper.calculateBackoff(attempt: 3, addJitter: false);
      expect(b1.inMilliseconds, 4000);
      expect(b2.inMilliseconds, 8000);
      expect(b3.inMilliseconds, 12000);
    });

    test('التأخير يتزايد مع رقم المحاولة', () {
      final b1 = helper.calculateBackoff(attempt: 1, addJitter: false);
      final b2 = helper.calculateBackoff(attempt: 2, addJitter: false);
      final b4 = helper.calculateBackoff(attempt: 4, addJitter: false);
      expect(b2.inMilliseconds, greaterThan(b1.inMilliseconds));
      expect(b4.inMilliseconds, greaterThan(b2.inMilliseconds));
    });

    test('مع jitter: ضمن نطاق [exp, exp*1.35]', () {
      const exp = 4000; // attempt=1
      for (var i = 0; i < 20; i++) {
        final b = helper.calculateBackoff(attempt: 1);
        expect(b.inMilliseconds, greaterThanOrEqualTo(exp));
        expect(b.inMilliseconds, lessThanOrEqualTo((exp * 1.35).round()));
      }
    });

    test('baseDelay/multiplier مخصّصان يُحترمان', () {
      final b = helper.calculateBackoff(
        attempt: 2,
        baseDelay: const Duration(milliseconds: 1000),
        multiplier: 3.0,
        addJitter: false,
      );
      // 1000 * (3 * 2) = 6000
      expect(b.inMilliseconds, 6000);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // ✅ إصلاح إرهاق 429: يثبت أن probe (maxRetries:1) يفشل فوراً على 429 دون
  //    الانتظار 2×60s — وهو جوهر إصلاح مسار upsert للمستندات الجديدة.
  // ─────────────────────────────────────────────────────────────────────
  group('probe سريع الفشل (maxRetries:1)', () {
    test('429 مع maxRetries:1 → يرمي فوراً، استدعاء واحد، بلا انتظار 60s', () async {
      var calls = 0;
      final sw = Stopwatch()..start();
      await expectLater(
        helper.withRetry<int>(
          operation: () async {
            calls++;
            throw AppwriteException('too many', 429);
          },
          maxRetries: 1,
          operationName: 'test_probe_429',
          suppressErrorLog: true,
        ),
        throwsA(isA<AppwriteException>()),
      );
      sw.stop();
      expect(calls, 1, reason: 'probe يجب أن يستدعي العملية مرة واحدة فقط');
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'probe يجب ألا ينتظر backoff الطويل (60s) على 429',
      );
    });

    test('خطأ عابر (500) مع maxRetries:1 → استدعاء واحد فقط', () async {
      var calls = 0;
      await expectLater(
        helper.withRetry<int>(
          operation: () async {
            calls++;
            throw AppwriteException('server error 500', 500);
          },
          maxRetries: 1,
          operationName: 'test_probe_500',
          suppressErrorLog: true,
        ),
        throwsA(isA<AppwriteException>()),
      );
      expect(calls, 1);
    });

    test('نجاح فوري: العملية تُستدعى مرة وتُرجع القيمة', () async {
      var calls = 0;
      final result = await helper.withRetry<String>(
        operation: () async {
          calls++;
          return 'ok';
        },
        maxRetries: 1,
        operationName: 'test_probe_ok',
      );
      expect(result, 'ok');
      expect(calls, 1);
    });
  });
}
