// اختبارات تحسينات P1 (تقرير 2026-09-11) لقاطع الدائرة:
// عتبة الإخفاقات المتتالية في half-open + سجل انتقالات الحالة
// المختوم زمنياً + حقول getStatus الجديدة.
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_core/circuit_breaker.dart';

class BoomException implements Exception {}

void main() {
  group('halfOpenMaxConsecutiveFailures', () {
    test(
      'الافتراضي 1: فشل مسبار واحد يعيد الفتح (السلوك السابق محفوظ)',
      () async {
        final cb = CircuitBreaker(
          name: 't1',
          config: const CircuitBreakerConfig(
            failureThreshold: 1,
            resetTimeout: Duration(milliseconds: 50),
          ),
        );

        await expectLater(
          cb.execute(() async => throw BoomException()),
          throwsA(isA<BoomException>()),
        );
        expect(cb.state, CircuitState.open);

        // انتظار resetTimeout → المسبار التالي يدخل half-open
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await expectLater(
          cb.execute(() async => throw BoomException()),
          throwsA(isA<BoomException>()),
        );
        expect(cb.state, CircuitState.open, reason: 'فشل واحد = إعادة الفتح');
        expect(cb.halfOpenConsecutiveFailures, 0);
        cb.dispose();
      },
    );

    test('عتبة 2: أول فشل يبقي half-open والثاني يفتح', () async {
      final cb = CircuitBreaker(
        name: 't2',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          resetTimeout: Duration(milliseconds: 50),
          halfOpenMaxConsecutiveFailures: 2,
        ),
      );

      await expectLater(
        cb.execute(() async => throw BoomException()),
        throwsA(isA<BoomException>()),
      );
      expect(cb.state, CircuitState.open);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      // مسبار 1 يفشل — يبقى half-open
      await expectLater(
        cb.execute(() async => throw BoomException()),
        throwsA(isA<BoomException>()),
      );
      expect(cb.state, CircuitState.halfOpen);
      expect(cb.halfOpenConsecutiveFailures, 1);

      // مسبار 2 يفشل — بلغ العتبة → open
      await expectLater(
        cb.execute(() async => throw BoomException()),
        throwsA(isA<BoomException>()),
      );
      expect(cb.state, CircuitState.open);
      expect(cb.halfOpenConsecutiveFailures, 0);
      cb.dispose();
    });

    test('نجاح المسبار يصفّر عدّاد الإخفاقات المتتالية', () async {
      final cb = CircuitBreaker(
        name: 't3',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          resetTimeout: Duration(milliseconds: 50),
          halfOpenMaxConsecutiveFailures: 3,
        ),
      );

      await expectLater(
        cb.execute(() async => throw BoomException()),
        throwsA(isA<BoomException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // فشل ثم نجاح → العدّاد يصفَّر ولا يتراكم
      await expectLater(
        cb.execute(() async => throw BoomException()),
        throwsA(isA<BoomException>()),
      );
      expect(cb.halfOpenConsecutiveFailures, 1);

      await cb.execute(() async => 'ok');
      expect(cb.halfOpenConsecutiveFailures, 0);
      expect(cb.state, CircuitState.halfOpen, reason: 'successThreshold=2');

      await cb.execute(() async => 'ok');
      expect(cb.state, CircuitState.closed);
      cb.dispose();
    });
  });

  group('سجل انتقالات الحالة', () {
    test('كل انتقال يُختتم زمنياً ويُحصى', () async {
      final cb = CircuitBreaker(
        name: 't4',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          resetTimeout: Duration(milliseconds: 50),
        ),
      );

      expect(cb.lastStateChangeAt, isNull);
      expect(cb.transitionCount, 0);

      await expectLater(
        cb.execute(() async => throw BoomException()),
        throwsA(isA<BoomException>()),
      );
      expect(cb.transitionCount, 1);
      expect(cb.lastStateChangeAt, isNotNull);
      expect(cb.transitions.single.from, CircuitState.closed);
      expect(cb.transitions.single.to, CircuitState.open);
      cb.dispose();
    });

    test('السجل محدود بـ maxTransitionHistory (الأقدم يُحذف)', () async {
      final cb = CircuitBreaker(
        name: 't5',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          maxTransitionHistory: 3,
        ),
      );

      // closed→open ثم reset→closed، ثلاث مرات = 6 انتقالات
      for (var i = 0; i < 3; i++) {
        await expectLater(
          cb.execute(() async => throw BoomException()),
          throwsA(isA<BoomException>()),
        );
        cb.reset();
      }

      expect(cb.transitionCount, 6);
      expect(cb.transitions.length, 3);
      // آخر 3 انتقالات: open→closed, closed→open, open→closed
      expect(cb.transitions[0].from, CircuitState.open);
      expect(cb.transitions[0].to, CircuitState.closed);
      expect(cb.transitions[2].to, CircuitState.closed);
      // السجل غير قابل للتعديل خارجياً
      expect(() => cb.transitions.add(cb.transitions.first), throwsA(anything));
      cb.dispose();
    });

    test('reset يصفّر عدّاد half-open ويحوّل إلى closed', () async {
      final cb = CircuitBreaker(
        name: 't6',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          resetTimeout: Duration(milliseconds: 50),
          halfOpenMaxConsecutiveFailures: 3,
        ),
      );

      await expectLater(
        cb.execute(() async => throw BoomException()),
        throwsA(isA<BoomException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await expectLater(
        cb.execute(() async => throw BoomException()),
        throwsA(isA<BoomException>()),
      );
      expect(cb.state, CircuitState.halfOpen);
      expect(cb.halfOpenConsecutiveFailures, 1);

      cb.reset();
      expect(cb.state, CircuitState.closed);
      expect(cb.halfOpenConsecutiveFailures, 0);
      cb.dispose();
    });
  });

  group('getStatus', () {
    test('يتضمن الحقول الجديدة', () async {
      final cb = CircuitBreaker(
        name: 't7',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          maxTransitionHistory: 5,
        ),
      );

      final before = cb.getStatus();
      expect(before['lastStateChangeAt'], isNull);
      expect(before['transitionCount'], 0);
      expect(before['halfOpenConsecutiveFailures'], 0);
      expect(before['recentTransitions'], isEmpty);

      await expectLater(
        cb.execute(() async => throw BoomException()),
        throwsA(isA<BoomException>()),
      );

      final after = cb.getStatus();
      expect(after['state'], 'open');
      expect(after['failureCount'], 1);
      expect(after['lastStateChangeAt'], isNotNull);
      expect(after['transitionCount'], 1);
      expect(after['recentTransitions'], hasLength(1));
      cb.dispose();
    });
  });
}
