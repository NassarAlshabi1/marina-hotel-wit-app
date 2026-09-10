import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_logger.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync/sync_gate.dart';
import 'package:marina_hotel_mobile/services/sync/sync_timers.dart';
import 'package:marina_hotel_mobile/services/sync_core/circuit_breaker.dart';
import 'package:marina_hotel_mobile/services/sync_core/retry_strategy.dart';

/// اختبارات تعزيزات P0/P1 لتقرير تحليل مزامنة Cloudflare (2026-09-11):
///
/// P0 — SyncGate:
/// 1. مهلة العمليات المتعثرة (تحرير تلقائي عند الطلب بعد تجاوز المهلة).
/// 2. تسجيل العمليات المرفوضة (سجل دائم في الذاكرة + عدّادات).
///
/// P1 — SyncTimers / CircuitBreaker / RetryStrategy:
/// 3. إحصائيات المؤقتات (fireCount/errorCount/متوسط المدة).
/// 4. halfOpenMaxAttempts + سجل أوقات الانتقال بين الحالات.
/// 5. retryableErrors + إحصائيات إعادة المحاولة.
///
/// ⚠️ هذه الاختبارات إضافية بالكامل — لا تغيّر سلوك أي مسار قائم.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────
  group('SyncGate — P0: مهلة المتعثر وسجل الرفض', () {
    final gate = SyncGate.instance;

    tearDown(() {
      // تنظيف حالة الـ Singleton بعد كل اختبار
      gate.exit();
      gate.stuckOperationTimeout = SyncGate.defaultStuckOperationTimeout;
      gate.clearRejectionLog();
    });

    test('يرفض الدخول والبوابة مشغولة ويسجل العملية المرفوضة', () {
      final rejectedBefore = gate.totalRejected;
      final logBefore = gate.recentRejections.length;

      expect(gate.tryEnter(operation: 'pull', source: 'test_a'), isTrue);
      expect(gate.tryEnter(operation: 'push', source: 'test_b'), isFalse);

      expect(gate.totalRejected, rejectedBefore + 1);
      expect(gate.recentRejections.length, logBefore + 1);

      final rec = gate.recentRejections.last;
      expect(rec.kind, 'rejected');
      expect(rec.requestedOperation, 'push');
      expect(rec.requestedSource, 'test_b');
      expect(rec.busyWithOperation, 'pull');
      expect(rec.busyWithSource, 'test_a');

      gate.exit(token: gate.activeToken);
      expect(gate.isBusy, isFalse);
    });

    test('يحرر تلقائياً عملية متعثرة تجاوزت المهلة ويدخل الطلب الجديد', () {
      gate.stuckOperationTimeout = Duration.zero; // كل حائز يعتبر متعثراً

      expect(gate.tryEnter(operation: 'pull', source: 'stuck_test'), isTrue);
      final stuckToken = gate.activeToken;

      // طلب جديد: تحرير تلقائي للمتعثرة + دخول الجديدة
      expect(gate.tryEnter(operation: 'auto_sync', source: 'recovery'), isTrue);
      expect(gate.state.operation, 'auto_sync');
      expect(gate.totalStuckReleased, greaterThan(0));

      final stuckRecord = gate.recentRejections
          .where((r) => r.kind == 'stuck_released')
          .last;
      expect(stuckRecord.busyWithOperation, 'pull');
      expect(stuckRecord.requestedOperation, 'auto_sync');

      // exit برمز قديم يُتجاهل — الحيازة الجديدة تبقى محمية
      gate.exit(token: stuckToken);
      expect(gate.isBusy, isTrue);
      expect(gate.state.operation, 'auto_sync');

      // exit بالرمز الحالي يحرر فعلاً
      gate.exit(token: gate.activeToken);
      expect(gate.isBusy, isFalse);
    });

    test('runGuarded يعيد نتيجة المهمة ويحرر البوابة برمزها', () async {
      final result = await gate.runGuarded<int>(
        operation: 'pull',
        source: 'rg_test',
        task: () async => 42,
      );
      expect(result, 42);
      expect(gate.isBusy, isFalse);
    });

    test('runGuardedVoid يرفض عند الانشغال ويعيد false دون تنفيذ', () async {
      expect(gate.tryEnter(operation: 'pull', source: 'busy_holder'), isTrue);
      var executed = false;
      final ok = await gate.runGuardedVoid(
        operation: 'push',
        source: 'rgv_test',
        task: () async => executed = true,
      );
      expect(ok, isFalse);
      expect(executed, isFalse);
      gate.exit(token: gate.activeToken);
    });

    test('runGuarded يحرر البوابة حتى عند فشل المهمة', () async {
      await expectLater(
        gate.runGuarded<void>(
          operation: 'pull',
          source: 'rg_fail_test',
          task: () async => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(gate.isBusy, isFalse);
    });

    test('statsSnapshot يعرض الحقول الجديدة', () {
      final snap = gate.statsSnapshot;
      expect(snap['totalRejected'], isA<int>());
      expect(snap['totalStuckReleased'], isA<int>());
      expect(snap['totalEntered'], isA<int>());
      expect(snap['stuckTimeoutMin'], 5);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('SyncTimers — P1: إحصائيات المؤقتات', () {
    late AppDatabase db;
    late OutboxDao outboxDao;
    late SyncTimers timers;
    int pushCalls = 0;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      outboxDao = OutboxDao(db);
      pushCalls = 0;
      timers = SyncTimers(
        outboxDao: outboxDao,
        logger: AppwriteLogger(),
        onSync: () async => true,
        onPushOnly: () async {
          pushCalls++;
          return true;
        },
      );
    });

    tearDown(() async {
      timers.dispose();
      await db.close();
    });

    test('auto_sync يجمع fireCount وآخر إطلاق ومتوسط المدة', () async {
      timers.startAutoSync(interval: const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 90));
      timers.stopAutoSync();

      final s = timers.timerStats['auto_sync'];
      expect(s, isNotNull);
      expect(s!.fireCount, greaterThanOrEqualTo(2));
      expect(s.errorCount, 0);
      expect(s.lastFireAt, isNotNull);
      expect(s.averageExecutionMs, greaterThanOrEqualTo(0));
      expect(timers.statsSnapshot.containsKey('auto_sync'), isTrue);
    });

    test('أخطاء onSync تُحتسب دون انهيار المؤقت أو unhandled error', () async {
      var calls = 0;
      final failing = SyncTimers(
        outboxDao: outboxDao,
        logger: AppwriteLogger(),
        onSync: () async {
          calls++;
          throw StateError('boom-$calls');
        },
        onPushOnly: () async => true,
      );
      failing.startAutoSync(interval: const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 70));
      failing.stopAutoSync();

      final s = failing.timerStats['auto_sync']!;
      expect(s.fireCount, greaterThanOrEqualTo(2));
      expect(s.errorCount, greaterThanOrEqualTo(2));
      expect(s.lastError, contains('boom'));
      expect(s.lastErrorAt, isNotNull);
      failing.dispose();
    });

    test(
      'debounced_push يسجل الإطلاق الفعلي بعد انتهاء نافذة التأجيل',
      () async {
        timers.triggerDebouncedPush(window: const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 80));

        final s = timers.timerStats['debounced_push'];
        expect(s, isNotNull);
        expect(s!.fireCount, 1);
        expect(pushCalls, 1);
        expect(s.errorCount, 0);
      },
    );

    test('resetStats يصفّر كل العدادات', () async {
      timers.triggerDebouncedPush(window: const Duration(milliseconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(timers.timerStats['debounced_push']!.fireCount, 1);

      timers.resetStats();
      final s = timers.timerStats['debounced_push']!;
      expect(s.fireCount, 0);
      expect(s.errorCount, 0);
      expect(s.totalExecutionMs, 0);
      expect(s.lastError, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('CircuitBreaker — P1: halfOpenMaxAttempts وسجل الانتقالات', () {
    test('يسجل أوقات الانتقال closed→open→halfOpen→closed', () async {
      final cb = CircuitBreaker(
        name: 't-transitions',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          timeout: Duration(milliseconds: 100),
          resetTimeout: Duration(milliseconds: 40),
          successThreshold: 1,
          halfOpenMaxAttempts: 3,
        ),
      );
      expect(cb.lastTransitionAt, isNull);
      expect(cb.recentTransitions, isEmpty);

      // فشل → open
      await expectLater(
        cb.execute<void>(() async => throw Exception('x')),
        throwsA(isA<Exception>()),
      );
      expect(cb.state, CircuitState.open);
      expect(cb.lastTransitionAt, isNotNull);
      expect(cb.recentTransitions.last['from'], 'closed');
      expect(cb.recentTransitions.last['to'], 'open');

      // بعد resetTimeout → halfOpen، ثم نجاح → closed
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final result = await cb.execute<int>(() async => 7);
      expect(result, 7);
      expect(cb.state, CircuitState.closed);

      final transitions = cb.recentTransitions
          .map((t) => '${t['from']}→${t['to']}')
          .toList();
      expect(
        transitions,
        containsAll(<String>[
          'closed→open',
          'open→halfOpen',
          'halfOpen→closed',
        ]),
      );
      expect(cb.getStatus()['lastTransitionAt'], isNotNull);
      cb.dispose();
    });

    test('halfOpenMaxAttempts يجبر العودة إلى open عند التجاوز', () async {
      final cb = CircuitBreaker(
        name: 't-halfopen-limit',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          timeout: Duration(milliseconds: 100),
          resetTimeout: Duration(milliseconds: 30),
          successThreshold: 99, // غير قابل للبلوغ — يُبقي الدائرة halfOpen
          halfOpenMaxAttempts: 2,
        ),
      );
      await expectLater(
        cb.execute<void>(() async => throw Exception('fail')),
        throwsA(isA<Exception>()),
      );
      expect(cb.state, CircuitState.open);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // المحاولتان 1 و2 داخل halfOpen تنجحان لكن الدائرة تبقى halfOpen
      expect(await cb.execute<int>(() async => 1), 1);
      expect(cb.state, CircuitState.halfOpen);
      expect(await cb.execute<int>(() async => 2), 2);
      expect(cb.state, CircuitState.halfOpen);

      // المحاولة 3 تتجاوز الحد → open + CircuitBreakerOpenException
      await expectLater(
        cb.execute<int>(() async => 3),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
      expect(cb.state, CircuitState.open);
      expect(cb.getStatus()['halfOpenMaxAttempts'], 2);
      cb.dispose();
    });

    test('المسار الافتراضي لا يفعّل حد half-open (نجاحان يغلقان)', () async {
      final cb = CircuitBreaker(
        name: 't-default-path',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          timeout: Duration(milliseconds: 100),
          resetTimeout: Duration(milliseconds: 30),
          successThreshold: 2,
          halfOpenMaxAttempts: 3,
        ),
      );
      await expectLater(
        cb.execute<void>(() async => throw Exception('fail')),
        throwsA(isA<Exception>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await cb.execute<int>(() async => 1), 1);
      expect(cb.state, CircuitState.halfOpen);
      expect(await cb.execute<int>(() async => 2), 2);
      expect(cb.state, CircuitState.closed); // أُغلق قبل بلوغ الحد
      expect(cb.halfOpenExecutions, 0); // صُفّر عند الإغلاق
      cb.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────
  group('RetryStrategy — P1: retryableErrors والإحصائيات', () {
    test('القائمة الفارغة تحافظ على السلوك القديم (shouldRetry فقط)', () async {
      final rs = RetryStrategy(
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
        ),
      );
      var attempts = 0;
      await expectLater(
        rs.execute<int>(
          operation: () async {
            attempts++;
            throw StateError('nope');
          },
          shouldRetry: (_) => false,
        ),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 1);
      expect(rs.stats.nonRetryable, 1);
      expect(rs.stats.retries, 0);
      expect(rs.stats.lastError, contains('nope'));
    });

    test(
      'retryableErrors تمنع إعادة محاولة الأنواع غير المذكورة فوراً',
      () async {
        final rs = RetryStrategy(
          config: const RetryConfig(
            maxAttempts: 5,
            initialDelay: Duration(milliseconds: 1),
            retryableErrors: [TimeoutException],
          ),
        );
        var attempts = 0;
        await expectLater(
          rs.execute<int>(
            operation: () async {
              attempts++;
              throw StateError('not-listed');
            },
            shouldRetry: (_) => true, // حتى مع موافقة shouldRetry
          ),
          throwsA(isA<StateError>()),
        );
        expect(attempts, 1); // رمي فوري بلا محاولات إضافية
        expect(rs.stats.nonRetryable, 1);
        expect(rs.stats.retries, 0);
      },
    );

    test(
      'retryableErrors تسمح بالمذكور حتى الاستنفاد وتحتسب exhausted',
      () async {
        final rs = RetryStrategy(
          config: const RetryConfig(
            maxAttempts: 3,
            initialDelay: Duration(milliseconds: 1),
            retryableErrors: [TimeoutException],
          ),
        );
        var attempts = 0;
        await expectLater(
          rs.execute<int>(
            operation: () async {
              attempts++;
              throw TimeoutException('slow');
            },
            shouldRetry: (_) => true,
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(attempts, 3);
        expect(rs.stats.attempts, 3);
        expect(rs.stats.retries, 2);
        expect(rs.stats.exhausted, 1);
      },
    );

    test('النجاح بعد إعادة محاولة يُحتسب في successAfterRetry', () async {
      final rs = RetryStrategy(
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
          retryableErrors: [StateError],
        ),
      );
      var attempts = 0;
      final result = await rs.execute<int>(
        operation: () async {
          attempts++;
          if (attempts == 1) {
            throw StateError('once');
          }
          return 5;
        },
        shouldRetry: (_) => true,
      );
      expect(result, 5);
      expect(rs.stats.successAfterRetry, 1);
      expect(rs.stats.retries, 1);
      expect(rs.stats.toMap().containsKey('nonRetryable'), isTrue);
    });
  });
}
