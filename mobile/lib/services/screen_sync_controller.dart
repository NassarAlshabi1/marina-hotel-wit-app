import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

import 'sync_core/circuit_breaker.dart';
import 'sync_core/retry_strategy.dart';
import 'sync_core/sync_error_handler.dart';
import 'sync_core/sync_validator.dart';
import 'sync_locks.dart';
import 'unified_sync_orchestrator.dart';

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
    AppLogger.info('[$screenId] تم تسجيل تغيير - إعادة ضبط المؤقت');
  }

  void _resetDebounceTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () {
      AppLogger.debug('[$screenId] انتهى المؤقت - بدء المزامنة التلقائية');
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
      debugPrint('✓ [$screenId] لا توجد تغييرات للمزامنة');
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
      debugPrint('⏳ [$screenId] المزامنة جارية بالفعل');
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
        debugPrint('📴 [$screenId] ${networkValidation.error}');
        return false;
      }

      if (networkValidation.warnings.isNotEmpty) {
        for (final warning in networkValidation.warnings) {
          AppLogger.warning('[$screenId] $warning');
        }
      }

      // SmartSyncManager تمت إزالته — استخدام UnifiedSyncOrchestrator
      final success = await _retryStrategy.executeWithFallback(
        operation: () async {
          return _circuitBreaker.execute(() async {
            AppLogger.debug('[$screenId] بدء المزامنة مع الحماية...');
            return UnifiedSyncOrchestrator.instance.syncNow(push: true, pull: false);
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
          debugPrint(
            '⚠️ [$screenId] استخدام القيمة الاحتياطية بعد فشل المحاولات',
          );
          return false;
        },
        onRetry: (attempt, error) {
          AppLogger.debug('[$screenId] إعادة المحاولة $attempt');
        },
      );

      if (success ?? false) {
        _hasChanges = false;
        _emitStatus(SyncStatus.synced);
        AppLogger.info('[$screenId] تمت المزامنة بنجاح');
        return true;
      } else {
        debugPrint(
          '⚠️ [$screenId] فشل الرفع - سيتم المحاولة لاحقاً عبر Outbox',
        );
        return false;
      }
    } on CircuitBreakerOpenException catch (e) {
      debugPrint('🔌 [$screenId] Circuit breaker مفتوح: $e');
      _emitStatus(SyncStatus.error);
      return false;
    } catch (e, stackTrace) {
      SyncErrorHandler.instance.handleError(
        e,
        stackTrace: stackTrace,
        context: {'screenId': screenId, 'operation': 'syncNow'},
      );
      AppLogger.error('[$screenId] خطأ في المزامنة: $e');
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
    AppLogger.debug('[$screenId] الخروج من الشاشة...');
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
    if (!_syncStatusController.isClosed) {
      _syncStatusController.close();
    }
    _circuitBreaker.dispose();
  }
}

enum SyncStatus { idle, pending, syncing, synced, queued, error }
