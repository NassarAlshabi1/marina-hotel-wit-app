// ignore_for_file: sort_constructors_first

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../appwrite_logger.dart';
import '../daos/outbox_dao.dart';
import '../sync_constants.dart';

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
class SyncTimers {
  SyncTimers({required this.outboxDao, required this.logger, required this.onSync, required this.onPushOnly});

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

  /// بدء المزامنة التلقائية
  void startAutoSync({Duration interval = SyncConstants.defaultAutoSyncInterval}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (timer) async {
      // ✅ إصلاح جذري: Timer callback async بدون try-catch يُسبب
      // unhandled async error → Crashlytics Fatal عند أي استثناء.
      try {
        await onSync();
      } catch (e, st) {
        logger.error('❌ Sync Timer: استثناء غير متوقع', error: e, stackTrace: st, tag: 'SYNC');
        // لا rethrow — نمنع fatal crash
      }
    });
    logger.info('Auto sync started (interval: ${interval.inMinutes} min)', tag: 'SYNC');
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
      try {
        final failedCount = await outboxDao.count();
        if (failedCount == 0) return;

        final resetCount = await outboxDao.retryFailedWithBackoff();
        if (resetCount == 0) return;

        debugPrint('🔄 إعادة محاولة العناصر الفاشلة في outbox (عدد: $resetCount)');

        final result = await onPushOnly();
        if (result) {
          debugPrint('✅ نجحت إعادة محاولة رفع العناصر الفاشلة');
        }
      } catch (e) {
        debugPrint('⚠️ فشلت إعادة محاولة العناصر الفاشلة: $e');
      }
    });
    debugPrint('🔄 تم تشغيل مؤقت إعادة محاولة العناصر الفاشلة (كل 5 دقائق)');

    // استعادة stuck 'processing' entries كل دقيقة
    _stuckRecoveryTimer?.cancel();
    _stuckRecoveryTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      try {
        final recovered = await outboxDao.cleanupStuckEntries();
        if (recovered > 0) {
          logger.info('🔧 تم استعادة $recovered عنصر عالق في outbox من "processing" إلى "pending"', tag: 'SYNC');
        }
      } catch (e) {
        logger.warning('⚠️ فشل استعادة العناصر العالقة: $e', tag: 'SYNC');
      }
    });
    debugPrint('🔧 تم تشغيل مؤقت استعادة العناصر العالقة (كل دقيقة)');

    // تنظيف outbox تلقائي كل 24 ساعة
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(hours: 24), (_) async {
      try {
        await outboxDao.cleanupCompleted();
        await outboxDao.cleanupOrphanedEntries();
      } catch (e) {
        logger.warning('⚠️ فشل تنظيف outbox الدوري: $e', tag: 'SYNC');
      }
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
      try {
        final result = await onPushOnly();
        if (!result) {
          logger.warning('Debounced push failed', tag: 'SYNC');
        }
      } catch (e) {
        logger.warning('Debounced push error: $e', tag: 'SYNC');
      }
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
