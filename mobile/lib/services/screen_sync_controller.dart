import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'smart_sync_manager.dart';
import 'sync_core/circuit_breaker.dart';
import 'sync_core/retry_strategy.dart';
import 'sync_core/sync_error_handler.dart';
import 'sync_core/sync_validator.dart';
import 'sync_locks.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

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
    AppLogger.info('📝 [$screenId] تم تسجيل تغيير - إعادة ضبط المؤقت', tag: 'APP');
  }

  void _resetDebounceTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () {
      AppLogger.info('⏰ [$screenId] انتهى المؤقت - بدء المزامنة التلقائية', tag: 'APP');
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
      AppLogger.info('✓ [$screenId] لا توجد تغييرات للمزامنة', tag: 'APP');
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
      AppLogger.info('⏳ [$screenId] المزامنة جارية بالفعل', tag: 'APP');
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
        AppLogger.info('📴 [$screenId] ${networkValidation.error}', tag: 'APP');
        // تم إلغاء SyncQueue لصالح Outbox - سيتم المزامنة تلقائياً عند عودة الاتصال
        return false;
      }

      if (!SmartSyncManager.instance().isDriveSignedIn) {
        AppLogger.info('🔒 [$screenId] المستخدم غير مسجل في Google Drive', tag: 'APP');
        return false;
      }

      if (networkValidation.warnings.isNotEmpty) {
        for (final warning in networkValidation.warnings) {
          AppLogger.warning('⚠️ [$screenId] $warning', tag: 'APP');
        }
      }

      final success = await _retryStrategy.executeWithFallback(
        operation: () async {
          return _circuitBreaker.execute(() async {
            AppLogger.info('🌐 [$screenId] بدء المزامنة مع الحماية...', tag: 'APP');
            return SmartSyncManager.instance().pushLocalChanges();
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
          AppLogger.warning(
  '⚠️ [$screenId] استخدام القيمة الاحتياطية بعد فشل المحاولات',,
  tag: 'APP',
);
          return false;
        },
        onRetry: (attempt, error) {
          AppLogger.info('🔄 [$screenId] إعادة المحاولة $attempt', tag: 'APP');
        },
      );

      if (success ?? false) {
        _hasChanges = false;
        _emitStatus(SyncStatus.synced);
        AppLogger.info('✅ [$screenId] تمت المزامنة بنجاح', tag: 'APP');
        return true;
      } else {
        AppLogger.warning(
  '⚠️ [$screenId] فشل الرفع - سيتم المحاولة لاحقاً عبر Outbox',,
  tag: 'APP',
);
        return false;
      }
    } on CircuitBreakerOpenException catch (e) {
      AppLogger.info('🔌 [$screenId] Circuit breaker مفتوح: $e', tag: 'APP');
      _emitStatus(SyncStatus.error);
      return false;
    } catch (e, stackTrace) {
      SyncErrorHandler.instance.handleError(
        e,
        stackTrace: stackTrace,
        context: {'screenId': screenId, 'operation': 'syncNow'},
      );
      AppLogger.warning('❌ [$screenId] خطأ في المزامنة: $e', tag: 'APP');
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
    AppLogger.info('🚪 [$screenId] الخروج من الشاشة...', tag: 'APP');
    cancelTimer();
    return syncNow();
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
