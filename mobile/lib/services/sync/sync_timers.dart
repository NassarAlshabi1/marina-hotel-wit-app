import 'dart:async';

import '../../utils/debug_log.dart';
import '../appwrite_logger.dart';
import '../daos/outbox_dao.dart';
import '../sync_constants.dart';

/// ✅ P1 (تقرير 2026-09-11): لقطة إحصائية غير قابلة للتغيير لمؤقّت واحد.
///
/// تُعرض في شاشات التشخيص وتُستخدم في الاختبارات. لكل مؤقّت:
/// عدد مرات الإطلاق، عدد الأخطاء غير الملتقَطة، إجمالي/متوسط زمن التنفيذ،
/// وآخر وقت إطلاق/خطأ.
class SyncTimerStatsSnapshot {
  const SyncTimerStatsSnapshot({
    this.fireCount = 0,
    this.errorCount = 0,
    this.totalExecutionMs = 0,
    this.lastFireAt,
    this.lastErrorAt,
    this.lastErrorMessage,
  });

  /// عدد مرات إطلاق المؤقّت.
  final int fireCount;

  /// عدد الأخطاء غير الملتقَطة التي هربت من callback المؤقّت.
  final int errorCount;

  /// إجمالي زمن التنفيذ بالمللي ثانية.
  final int totalExecutionMs;

  /// آخر وقت إطلاق.
  final DateTime? lastFireAt;

  /// آخر وقت خطأ.
  final DateTime? lastErrorAt;

  /// رسالة آخر خطأ.
  final String? lastErrorMessage;

  /// متوسط زمن التنفيذ — صفر إذا لم يُطلق بعد.
  Duration get averageExecutionTime => fireCount == 0
      ? Duration.zero
      : Duration(milliseconds: totalExecutionMs ~/ fireCount);

  Map<String, dynamic> toJson() => {
    'fireCount': fireCount,
    'errorCount': errorCount,
    'totalExecutionMs': totalExecutionMs,
    'averageExecutionMs': averageExecutionTime.inMilliseconds,
    'lastFireAt': lastFireAt?.toIso8601String(),
    'lastErrorAt': lastErrorAt?.toIso8601String(),
    'lastErrorMessage': lastErrorMessage,
  };

  @override
  String toString() =>
      'SyncTimerStats(fires=$fireCount, errors=$errorCount, '
      'avg=${averageExecutionTime.inMilliseconds}ms)';
}

/// تجميع داخلي قابل للتغيير — لا يُكشف خارج الوحدة.
class _TimerStat {
  int fireCount = 0;
  int errorCount = 0;
  int totalExecutionMs = 0;
  DateTime? lastFireAt;
  DateTime? lastErrorAt;
  String? lastErrorMessage;

  void recordFire() {
    fireCount++;
    lastFireAt = DateTime.now();
  }

  void recordError(Object error) {
    errorCount++;
    lastErrorAt = DateTime.now();
    lastErrorMessage = error.toString();
  }

  void recordExecution(int elapsedMs) {
    totalExecutionMs += elapsedMs;
  }

  SyncTimerStatsSnapshot snapshot() => SyncTimerStatsSnapshot(
    fireCount: fireCount,
    errorCount: errorCount,
    totalExecutionMs: totalExecutionMs,
    lastFireAt: lastFireAt,
    lastErrorAt: lastErrorAt,
    lastErrorMessage: lastErrorMessage,
  );
}

/// SyncTimers — يدير كل المؤقتات الدورية للمزامنة
///
/// تم استخراجه من AppwriteSyncManager (God Class) لفصل إدارة المؤقتات
/// عن منطق المزامنة.
///
/// المؤقتات المُدارة:
/// - syncTimer: مزامنة دورية (default: 5 min)
/// - failedRetryTimer: إعادة محاولة العناصر الفاشلة (5 min)
/// - stuckRecoveryTimer: استعادة العناصر العالقة (1 min)
/// - cleanupTimer: تنظيف outbox المنجز (24 hours)
/// - debouncePushTimer: دفع مؤجل بعد تغييرات outbox
///
/// ✅ P1 (تقرير 2026-09-11): كل callback يمرّ عبر [_tracked] لتسجيل
/// إحصائيات لكل مؤقّت (إطلاقات، أخطاء، زمن تنفيذ) — انظر [stats]
/// و[statsFor] و[resetStats]. أسماء المؤقّتات ثابتة عامة
/// ([SyncTimers.timerSync] ...) لتوحيد المرجعية في الواجهة والاختبارات.
class SyncTimers {
  SyncTimers({
    required this.outboxDao,
    required this.logger,
    required this.onSync,
    required this.onPushOnly,
  });

  static const String timerSync = 'sync';
  static const String timerFailedRetry = 'failedRetry';
  static const String timerStuckRecovery = 'stuckRecovery';
  static const String timerCleanup = 'cleanup';
  static const String timerDebouncePush = 'debouncePush';

  /// كل أسماء المؤقّتات المتتبَّعة.
  static const List<String> trackedTimers = [
    timerSync,
    timerFailedRetry,
    timerStuckRecovery,
    timerCleanup,
    timerDebouncePush,
  ];

  final OutboxDao outboxDao;
  final AppwriteLogger logger;

  /// دالة المزامنة الكاملة (push + pull) — تُرجع true عند النجاح
  final Future<bool> Function() onSync;

  /// دالة الرفع فقط (push only) — تُرجع true عند النجاح
  final Future<bool> Function() onPushOnly;

  final Map<String, _TimerStat> _stats = {};

  Timer? _syncTimer;
  Timer? _failedRetryTimer;
  Timer? _stuckRecoveryTimer;
  Timer? _cleanupTimer;
  Timer? _debouncePushTimer;

  Duration _debounceWindow = SyncConstants.outboxDebounceWindow;

  // ─── ✅ P1: إحصائيات المؤقتات ───

  _TimerStat _stat(String name) => _stats.putIfAbsent(name, _TimerStat.new);

  /// يغلّف أي callback بتسجيل الإطلاق والزمن والأخطاء الهاربة.
  Future<void> _tracked(String name, Future<void> Function() body) async {
    final stat = _stat(name);
    stat.recordFire();
    final watch = Stopwatch()..start();
    try {
      await body();
    } catch (e) {
      // الأخطاء غير الملتقَطة فقط تُحتسب — الالتقاط الداخلي المقصود
      // داخل الـ callbacks الأصلية يبقى كما هو (سلوك دون تغيير).
      stat.recordError(e);
      rethrow;
    } finally {
      watch.stop();
      stat.recordExecution(watch.elapsedMilliseconds);
    }
  }

  /// لقطة إحصائيات مؤقّت محدد (أو لقطة فارغة إن لم يُطلق بعد).
  SyncTimerStatsSnapshot statsFor(String name) =>
      _stats[name]?.snapshot() ?? const SyncTimerStatsSnapshot();

  /// لقطة إحصائيات كل المؤقّتات المتتبَّعة.
  Map<String, SyncTimerStatsSnapshot> get stats => {
    for (final name in trackedTimers) name: statsFor(name),
  };

  /// تصفير كل الإحصائيات (لا يمس المؤقّتات نفسها).
  void resetStats() => _stats.clear();

  // ─── المؤقتات ───

  /// بدء المزامنة التلقائية
  void startAutoSync({
    Duration interval = SyncConstants.defaultAutoSyncInterval,
  }) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (timer) async {
      // ✅ إصلاح جذري: Timer callback async بدون try-catch يُسبب
      // unhandled async error → Crashlytics Fatal عند أي استثناء.
      await _tracked(timerSync, () async {
        try {
          await onSync();
        } catch (e, st) {
          logger.error(
            '❌ Sync Timer: استثناء غير متوقع',
            error: e,
            stackTrace: st,
            tag: 'SYNC',
          );
          // لا rethrow — نمنع fatal crash
        }
      });
    });
    logger.info(
      'Auto sync started (interval: ${interval.inMinutes} min)',
      tag: 'SYNC',
    );
  }

  /// إيقاف المزامنة التلقائية
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    logger.info('Auto sync stopped', tag: 'SYNC');
  }

  /// مؤقت إعادة محاولة العناصر الفاشلة — كل 5 دقائق
  void startFailedRetryTimer() {
    _failedRetryTimer?.cancel();
    _failedRetryTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await _tracked(timerFailedRetry, () async {
        try {
          final failedCount = await outboxDao.count();
          if (failedCount == 0) return;

          final resetCount = await outboxDao.retryFailedWithBackoff();
          if (resetCount == 0) return;

          dlog(
            () =>
                '🔄 إعادة محاولة العناصر الفاشلة في outbox (عدد: $resetCount)',
          );

          final result = await onPushOnly();
          if (result) {
            dlog('✅ نجحت إعادة محاولة رفع العناصر الفاشلة');
          }
        } catch (e) {
          dlog(() => '⚠️ فشلت إعادة محاولة العناصر الفاشلة: $e');
        }
      });
    });
    dlog('🔄 تم تشغيل مؤقت إعادة محاولة العناصر الفاشلة (كل 5 دقائق)');

    // استعادة stuck 'processing' entries كل دقيقة
    _stuckRecoveryTimer?.cancel();
    _stuckRecoveryTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _tracked(timerStuckRecovery, () async {
        try {
          final recovered = await outboxDao.cleanupStuckEntries();
          if (recovered > 0) {
            logger.info(
              '🔧 تم استعادة $recovered عنصر عالق في outbox من "processing" إلى "pending"',
              tag: 'SYNC',
            );
          }
        } catch (e) {
          logger.warning('⚠️ فشل استعادة العناصر العالقة: $e', tag: 'SYNC');
        }
      });
    });
    dlog('🔧 تم تشغيل مؤقت استعادة العناصر العالقة (كل دقيقة)');

    // تنظيف outbox تلقائي كل 24 ساعة
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(hours: 24), (_) async {
      await _tracked(timerCleanup, () async {
        try {
          await outboxDao.cleanupCompleted();
          await outboxDao.cleanupOrphanedEntries();
        } catch (e) {
          logger.warning('⚠️ فشل تنظيف outbox الدوري: $e', tag: 'SYNC');
        }
      });
    });
  }

  /// تفعيل الدفع المؤجل
  void triggerDebouncedPush({Duration? window}) {
    if (window != null) {
      _debounceWindow = window;
    }
    _debouncePushTimer?.cancel();
    _debouncePushTimer = Timer(_debounceWindow, () async {
      logger.debug('Debounced push triggered', tag: 'SYNC');
      await _tracked(timerDebouncePush, () async {
        try {
          final result = await onPushOnly();
          if (!result) {
            logger.warning('Debounced push failed', tag: 'SYNC');
          }
        } catch (e) {
          logger.warning('Debounced push error: $e', tag: 'SYNC');
        }
      });
    });
  }

  /// إيقاف كل المؤقتات
  void dispose() {
    _syncTimer?.cancel();
    _failedRetryTimer?.cancel();
    _stuckRecoveryTimer?.cancel();
    _cleanupTimer?.cancel();
    _debouncePushTimer?.cancel();
    _syncTimer = null;
    _failedRetryTimer = null;
    _stuckRecoveryTimer = null;
    _cleanupTimer = null;
    _debouncePushTimer = null;
  }
}
