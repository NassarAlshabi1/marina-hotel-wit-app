import 'dart:async';

import '../../utils/debug_log.dart';
import '../appwrite_logger.dart';
import '../daos/outbox_dao.dart';
import '../sync_constants.dart';

/// ✅ P1: إحصائيات مؤقّت واحد — تُجمَع تلقائياً عند كل إطلاق.
///
/// المقاييس المُتتبّعة لكل مؤقت:
/// - [fireCount]: عدد مرات الإطلاق
/// - [errorCount]: عدد الأخطاء غير المتوقعة
/// - [totalExecutionMs]/[averageExecutionMs]: مدة التنفيذ التراكمية/المتوسطة
/// - [lastFireAt]/[lastErrorAt]/[lastError]: آخر إطلاق/خطأ
class SyncTimerStats {
  SyncTimerStats(this.name);

  /// اسم المؤقت: 'auto_sync', 'failed_retry', 'stuck_recovery',
  /// 'cleanup', 'debounced_push'.
  final String name;

  /// عدد مرات إطلاق الـ callback.
  int fireCount = 0;

  /// عدد الأخطاء التي التقطها غلاف التتبّع.
  int errorCount = 0;

  /// إجمالي مدة التنفيذ بالمللي ثانية (يشمل النجاح والفشل).
  int totalExecutionMs = 0;

  /// وقت آخر إطلاق.
  DateTime? lastFireAt;

  /// وقت آخر خطأ.
  DateTime? lastErrorAt;

  /// نص آخر خطأ.
  String? lastError;

  /// متوسط مدة التنفيذ بالمللي ثانية (0 إذا لم يُطلق بعد).
  double get averageExecutionMs =>
      fireCount == 0 ? 0 : totalExecutionMs / fireCount;

  Map<String, dynamic> toMap() => {
    'name': name,
    'fireCount': fireCount,
    'errorCount': errorCount,
    'totalExecutionMs': totalExecutionMs,
    'averageExecutionMs': averageExecutionMs,
    'lastFireAt': lastFireAt?.toIso8601String(),
    'lastErrorAt': lastErrorAt?.toIso8601String(),
    'lastError': lastError,
  };

  @override
  String toString() =>
      'SyncTimerStats($name: fires=$fireCount, errors=$errorCount, '
      'avg=${averageExecutionMs.toStringAsFixed(1)}ms)';
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
/// ✅ P1: كل callback يمرّ عبر [_tracked] لتجميع [SyncTimerStats]
/// (عدد الإطلاقات/الأخطاء/متوسط المدة) — السلوك ورسائل السجل نفسها
/// لم تتغير، والإحصائيات إضافة مراقبة فقط.
class SyncTimers {
  SyncTimers({
    required this.outboxDao,
    required this.logger,
    required this.onSync,
    required this.onPushOnly,
  });

  final OutboxDao outboxDao;
  final AppwriteLogger logger;

  /// دالة المزامنة الكاملة (push + pull) — تُرجع true عند النجاح
  final Future<bool> Function() onSync;

  /// دالة الرفع فقط (push only) — تُرجع true عند النجاح
  final Future<bool> Function() onPushOnly;

  Timer? _syncTimer;
  Timer? _failedRetryTimer;
  Timer? _stuckRecoveryTimer;
  Timer? _cleanupTimer;
  Timer? _debouncePushTimer;

  Duration _debounceWindow = SyncConstants.outboxDebounceWindow;

  /// ✅ P1: إحصائيات كل مؤقت حسب اسمه.
  final Map<String, SyncTimerStats> _stats = <String, SyncTimerStats>{};

  /// ✅ P1: إحصائيات المؤقتات (عرض للقراءة فقط).
  Map<String, SyncTimerStats> get timerStats => Map.unmodifiable(_stats);

  /// ✅ P1: لقطة إحصائيات جاهزة للعرض/التصدير.
  Map<String, dynamic> get statsSnapshot =>
      _stats.map((key, value) => MapEntry(key, value.toMap()));

  /// ✅ P1: تصفير الإحصائيات (للاختبارات أو بعد تصديرها).
  void resetStats() {
    for (final s in _stats.values) {
      s
        ..fireCount = 0
        ..errorCount = 0
        ..totalExecutionMs = 0
        ..lastFireAt = null
        ..lastErrorAt = null
        ..lastError = null;
    }
  }

  /// ✅ P1: غلاف تتبّع موحّد — يقيس المدة ويعدّ الأخطاء ثم يمرّرها إلى
  /// [onError] (نفس معالجة السجل القديمة). لا يعيد رمي الخطأ — نفس ضمانة
  /// "لا unhandled async error" القديمة.
  Future<void> _tracked(
    String key,
    Future<void> Function() body, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final s = _stats.putIfAbsent(key, () => SyncTimerStats(key));
    s.fireCount++;
    s.lastFireAt = DateTime.now();
    final sw = Stopwatch()..start();
    try {
      await body();
    } catch (e, st) {
      s.errorCount++;
      s.lastErrorAt = DateTime.now();
      s.lastError = e.toString();
      onError?.call(e, st);
    } finally {
      s.totalExecutionMs += sw.elapsedMilliseconds;
    }
  }

  /// بدء المزامنة التلقائية
  void startAutoSync({
    Duration interval = SyncConstants.defaultAutoSyncInterval,
  }) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (timer) {
      // ✅ إصلاح جذري: Timer callback async بدون try-catch يُسبب
      // unhandled async error → Crashlytics Fatal عند أي استثناء.
      // ✅ P1: التتبّع عبر _tracked (نفس المعالجة: logger.error بلا rethrow).
      unawaited(
        _tracked(
          'auto_sync',
          onSync,
          onError: (e, st) => logger.error(
            '❌ Sync Timer: استثناء غير متوقع',
            error: e,
            stackTrace: st,
            tag: 'SYNC',
          ),
        ),
      );
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
    _failedRetryTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(
        _tracked(
          'failed_retry',
          () async {
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
          },
          onError: (e, _) {
            dlog(() => '⚠️ فشلت إعادة محاولة العناصر الفاشلة: $e');
          },
        ),
      );
    });
    dlog('🔄 تم تشغيل مؤقت إعادة محاولة العناصر الفاشلة (كل 5 دقائق)');

    // استعادة stuck 'processing' entries كل دقيقة
    _stuckRecoveryTimer?.cancel();
    _stuckRecoveryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(
        _tracked(
          'stuck_recovery',
          () async {
            final recovered = await outboxDao.cleanupStuckEntries();
            if (recovered > 0) {
              logger.info(
                '🔧 تم استعادة $recovered عنصر عالق في outbox من "processing" إلى "pending"',
                tag: 'SYNC',
              );
            }
          },
          onError: (e, _) {
            logger.warning('⚠️ فشل استعادة العناصر العالقة: $e', tag: 'SYNC');
          },
        ),
      );
    });
    dlog('🔧 تم تشغيل مؤقت استعادة العناصر العالقة (كل دقيقة)');

    // تنظيف outbox تلقائي كل 24 ساعة
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(hours: 24), (_) {
      unawaited(
        _tracked(
          'cleanup',
          () async {
            await outboxDao.cleanupCompleted();
            await outboxDao.cleanupOrphanedEntries();
          },
          onError: (e, _) {
            logger.warning('⚠️ فشل تنظيف outbox الدوري: $e', tag: 'SYNC');
          },
        ),
      );
    });
  }

  /// تفعيل الدفع المؤجل
  void triggerDebouncedPush({Duration? window}) {
    if (window != null) {
      _debounceWindow = window;
    }
    _debouncePushTimer?.cancel();
    _debouncePushTimer = Timer(_debounceWindow, () {
      unawaited(
        _tracked(
          'debounced_push',
          () async {
            logger.debug('Debounced push triggered', tag: 'SYNC');
            final result = await onPushOnly();
            if (!result) {
              logger.warning('Debounced push failed', tag: 'SYNC');
            }
          },
          onError: (e, _) {
            logger.warning('Debounced push error: $e', tag: 'SYNC');
          },
        ),
      );
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
