import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'secondary_appwrite_config.dart';
// ✅ Sync Simplification (2026-08-10): secondary_sync_manager.dart معطّل
// بالكامل. لا حاجة لاستيراده هنا.
import 'smart_sync_manager.dart';
import 'sync_core/circuit_breaker.dart';
import 'sync_core/retry_strategy.dart';
import 'sync_core/sync_error_handler.dart';
import 'sync_core/sync_validator.dart';
import 'sync_locks.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class ScreenSyncController {
  ScreenSyncController({
    required this.screenId,
    this.debounceDelay = const Duration(seconds: 15),
  }) {
    _circuitBreaker = CircuitBreaker(
      name: 'sync_$screenId',
      config: const CircuitBreakerConfig(
        failureThreshold: 3,
        resetTimeout: Duration(minutes: 2),
      ),
    );

    _retryStrategy = RetryStrategy(config: RetryConfig.balanced);
  }
  final String screenId;
  final Duration debounceDelay;

  late final CircuitBreaker _circuitBreaker;
  late final RetryStrategy _retryStrategy;

  bool _hasChanges = false;
  Timer? _debounceTimer;
  bool _isSyncing = false;

  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  bool get hasChanges => _hasChanges;
  bool get isSyncing => _isSyncing;

  void markChanged() {
    _hasChanges = true;
    _emitStatus(SyncStatus.pending);
    _resetDebounceTimer();
    dlog(() => '📝 [$screenId] تم تسجيل تغيير - إعادة ضبط المؤقت');
  }

  void _resetDebounceTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () {
      dlog(() => '⏰ [$screenId] انتهى المؤقت - بدء المزامنة التلقائية');
      syncNow();
    });
  }

  void cancelTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// إعادة ضبط علم التغييرات بعد الحفظ الناجح محلياً
  void markSaved() {
    _hasChanges = false;
    cancelTimer();
    _emitStatus(SyncStatus.synced);
  }

  Future<bool> syncNow() async {
    if (!_hasChanges) {
      dlog(() => '✓ [$screenId] لا توجد تغييرات للمزامنة');
      return true;
    }

    final canStart = await SyncLocks.screenSyncLock.synchronized(() async {
      if (_isSyncing) {
        return false;
      }
      _isSyncing = true;
      return true;
    });

    if (!canStart) {
      dlog(() => '⏳ [$screenId] المزامنة جارية بالفعل');
      return false;
    }

    cancelTimer();
    _emitStatus(SyncStatus.syncing);

    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResults.any(
        (r) => r != ConnectivityResult.none,
      );

      final networkValidation = SyncValidator.instance
          .validateNetworkConditions(hasConnection: hasConnection);

      if (!networkValidation.isValid) {
        dlog(() => '📴 [$screenId] ${networkValidation.error}');
        // تم إلغاء SyncQueue لصالح Outbox - سيتم المزامنة تلقائياً عند عودة الاتصال
        return false;
      }

      if (!SmartSyncManager.instance.isDriveSignedIn) {
        dlog(() => '🔒 [$screenId] المستخدم غير مسجل في Google Drive');
        return false;
      }

      if (networkValidation.warnings.isNotEmpty) {
        for (final warning in networkValidation.warnings) {
          dlog(() => '⚠️ [$screenId] $warning');
        }
      }

      final success = await _retryStrategy.executeWithFallback(
        operation: () async {
          return _circuitBreaker.execute(() async {
            dlog(() => '🌐 [$screenId] بدء المزامنة مع الحماية...');
            return SmartSyncManager.instance.pushLocalChanges();
          });
        },
        shouldRetry: (error) {
          final syncError = SyncErrorHandler.instance.handleError(
            error,
            context: {'screenId': screenId, 'operation': 'syncNow'},
          );
          return syncError.isRetryable;
        },
        fallback: () {
          dlog(
            () => '⚠️ [$screenId] استخدام القيمة الاحتياطية بعد فشل المحاولات',
          );
          return false;
        },
        onRetry: (attempt, error) {
          dlog(() => '🔄 [$screenId] إعادة المحاولة $attempt');
        },
      );

      if (success ?? false) {
        _hasChanges = false;
        _emitStatus(SyncStatus.synced);
        dlog(() => '✅ [$screenId] تمت المزامنة بنجاح');

        // ✅ إصلاح (2026-06-28): رفع التغييرات للوجهة الثانوية أيضاً
        // بدون هذا، Secondary لا يُفعّل إلا عبر:
        //   1. زر المزامنة اليدوي في Dashboard
        //   2. المؤقت التلقائي (كل 15 دقيقة)
        // الآن: أي markDataChanged → syncNow → Primary + Secondary
        await _pushToSecondary();

        return true;
      } else {
        dlog(
          () => '⚠️ [$screenId] فشل الرفع - سيتم المحاولة لاحقاً عبر Outbox',
        );
        return false;
      }
    } on CircuitBreakerOpenException catch (e) {
      dlog(() => '🔌 [$screenId] Circuit breaker مفتوح: $e');
      _emitStatus(SyncStatus.error);
      return false;
    } catch (e, stackTrace) {
      SyncErrorHandler.instance.handleError(
        e,
        stackTrace: stackTrace,
        context: {'screenId': screenId, 'operation': 'syncNow'},
      );
      dlog(() => '❌ [$screenId] خطأ في المزامنة: $e');
      _emitStatus(SyncStatus.error);
      return false;
    } finally {
      await SyncLocks.screenSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  void _emitStatus(SyncStatus status) {
    _syncStatusController.add(status);
  }

  Future<bool> syncOnExit() async {
    dlog(() => '🚪 [$screenId] الخروج من الشاشة...');
    cancelTimer();
    return syncNow();
  }

  /// ✅ رفع التغييرات للوجهة الثانوية (Secondary Appwrite)
  ///
  /// يُستدعى بعد نجاح Primary sync لضمان رفع التغييرات للوجهتين معاً.
  /// إذا فشل Secondary، لا يُعطل Primary — السجل يبقى في outbox
  /// حتى تنجح محاولة Secondary التالية (auto-sync timer أو مزامنة يدوية).
  Future<void> _pushToSecondary() async {
    try {
      // ✅ Sync Simplification (2026-08-10): Secondary sync مُعطّل بالكامل.
      // لا حاجة لرفع للوجهة الثانوية. العودة مباشرة.
      return;
    } catch (e) {
      dlog(() => '⚠️ [$screenId] خطأ غير متوقع: $e');
    }
  }

  Map<String, dynamic> getHealthStatus() {
    return {
      'screenId': screenId,
      'hasChanges': _hasChanges,
      'isSyncing': _isSyncing,
      'circuitBreaker': _circuitBreaker.getStatus(),
    };
  }

  void dispose() {
    cancelTimer();

    // إغلاق الموارد فوراً
    // المزامنة عند الخروج تتم عبر PopScope في SyncOnExitMixin
    if (!_syncStatusController.isClosed) {
      _syncStatusController.close();
    }
    _circuitBreaker.dispose();
  }
}

enum SyncStatus { idle, pending, syncing, synced, queued, error }
