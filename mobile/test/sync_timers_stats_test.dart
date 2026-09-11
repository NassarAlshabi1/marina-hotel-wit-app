// اختبارات إحصائيات المؤقتات P1 (تقرير 2026-09-11) لـ SyncTimers:
// كل callback يمر عبر التتبع (إطلاقات/زمن تنفيذ) والأخطاء الملتقَطة
// داخلياً (بتصميم المشروع) لا تُحتسب في errorCount.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_logger.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync/sync_timers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OutboxDao outbox;

  SyncTimers buildTimers({
    Future<bool> Function()? onSync,
    Future<bool> Function()? onPushOnly,
  }) {
    return SyncTimers(
      outboxDao: outbox,
      logger: AppwriteLogger(),
      onSync: onSync ?? (() async => true),
      onPushOnly: onPushOnly ?? (() async => true),
    );
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    DatabaseManager.attachForTesting(db);
    outbox = OutboxDao(db, AdapterRegistry.testing(db));
  });

  tearDown(() async {
    DatabaseManager.detachForTesting();
    await db.close();
  });

  test('stats تغطي أسماء المؤقتات الخمسة حتى قبل أي إطلاق', () {
    final timers = buildTimers();
    final stats = timers.stats;
    expect(stats.keys, hasLength(5));
    expect(stats.keys, containsAll(SyncTimers.trackedTimers));
    expect(stats[SyncTimers.timerSync]!.fireCount, 0);
    expect(
      stats[SyncTimers.timerDebouncePush]!.averageExecutionTime,
      Duration.zero,
    );
    timers.dispose();
  });

  test('triggerDebouncedPush يسجّل الإطلاق والزمن', () async {
    final timers = buildTimers();
    timers.triggerDebouncedPush(window: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final s = timers.statsFor(SyncTimers.timerDebouncePush);
    expect(s.fireCount, 1);
    expect(s.lastFireAt, isNotNull);
    expect(s.errorCount, 0);
    expect(s.totalExecutionMs, greaterThanOrEqualTo(0));
    expect(s.toJson(), contains('fireCount'));
    timers.dispose();
  });

  test('startAutoSync بفاصل قصير يسجّل إطلاقات متعددة', () async {
    var syncCalls = 0;
    final timers = buildTimers(
      onSync: () async {
        syncCalls++;
        return true;
      },
    );
    timers.startAutoSync(interval: const Duration(milliseconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    timers.dispose();

    expect(syncCalls, greaterThanOrEqualTo(2));
    final s = timers.statsFor(SyncTimers.timerSync);
    expect(s.fireCount, greaterThanOrEqualTo(2));
    expect(s.lastFireAt, isNotNull);
    expect(s.averageExecutionTime, isA<Duration>());
  });

  test(
    'الأخطاء الملتقَطة داخلياً لا تُحتسب في errorCount (سلوك مقصود)',
    () async {
      final timers = buildTimers(
        onPushOnly: () async => throw StateError('push boom'),
      );
      timers.triggerDebouncedPush(window: const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final s = timers.statsFor(SyncTimers.timerDebouncePush);
      expect(s.fireCount, 1);
      expect(
        s.errorCount,
        0,
        reason:
            'الـ callback يلتقط الخطأ داخلياً ويسجّله في الـ logger — '
            'errorCount مخصص للأخطاء الهاربة من الـ callback فقط',
      );
      timers.dispose();
    },
  );

  test(
    'failedRetryTimer مع outbox فارغ لا يعدّل الإحصائيات قبل مرور دوره',
    () async {
      final timers = buildTimers();
      // دور المؤقت 5 دقائق — لن يُطلق خلال الاختبار، لكن تشغيله آمن
      timers.startFailedRetryTimer();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(timers.statsFor(SyncTimers.timerFailedRetry).fireCount, 0);
      expect(timers.statsFor(SyncTimers.timerStuckRecovery).fireCount, 0);
      expect(timers.statsFor(SyncTimers.timerCleanup).fireCount, 0);
      timers.dispose();
    },
  );

  test('resetStats يصفّر كل الإحصائيات', () async {
    final timers = buildTimers();
    timers.triggerDebouncedPush(window: const Duration(milliseconds: 15));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(timers.statsFor(SyncTimers.timerDebouncePush).fireCount, 1);

    timers.resetStats();
    expect(timers.statsFor(SyncTimers.timerDebouncePush).fireCount, 0);
    expect(timers.statsFor(SyncTimers.timerDebouncePush).lastFireAt, isNull);
    timers.dispose();
  });
}
