import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'smart_sync_manager.dart';
import 'sync_queue_service.dart';
import 'sync_core/sync_error_handler.dart';
import 'sync_core/retry_strategy.dart';
import 'sync_core/circuit_breaker.dart';
import 'sync_core/sync_validator.dart';

class ScreenSyncController {
  final String screenId;
  final Duration debounceDelay;
  
  late final CircuitBreaker _circuitBreaker;
  late final RetryStrategy _retryStrategy;
  
  ScreenSyncController({
    required this.screenId,
    this.debounceDelay = const Duration(seconds: 15),
  }) {
    _circuitBreaker = CircuitBreaker(
      name: 'sync_$screenId',
      config: const CircuitBreakerConfig(
        failureThreshold: 3,
        timeout: Duration(seconds: 30),
        resetTimeout: Duration(minutes: 2),
      ),
    );
    
    _retryStrategy = RetryStrategy(
      config: RetryConfig.balanced,
    );
  }
  
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
    debugPrint('📝 [$screenId] تم تسجيل تغيير - إعادة ضبط المؤقت');
  }
  
  void _resetDebounceTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () {
      debugPrint('⏰ [$screenId] انتهى المؤقت - بدء المزامنة التلقائية');
      syncNow();
    });
  }
  
  void cancelTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
  
  Future<bool> syncNow() async {
    if (!_hasChanges) {
      debugPrint('✓ [$screenId] لا توجد تغييرات للمزامنة');
      return true;
    }
    
    if (_isSyncing) {
      debugPrint('⏳ [$screenId] المزامنة جارية بالفعل');
      return false;
    }
    
    cancelTimer();
    _isSyncing = true;
    _emitStatus(SyncStatus.syncing);
    
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResults.any((r) => r != ConnectivityResult.none);
      
      final networkValidation = SyncValidator.instance.validateNetworkConditions(
        hasConnection: hasConnection,
      );
      
      if (!networkValidation.isValid) {
        debugPrint('📴 [$screenId] ${networkValidation.error}');
        await _addToQueue();
        return false;
      }
      
      if (networkValidation.warnings.isNotEmpty) {
        for (final warning in networkValidation.warnings) {
          debugPrint('⚠️ [$screenId] $warning');
        }
      }
      
      final success = await _retryStrategy.executeWithFallback(
        operation: () async {
          return await _circuitBreaker.execute(() async {
            debugPrint('🌐 [$screenId] بدء المزامنة مع الحماية...');
            return await SmartSyncManager.instance.pushLocalChanges();
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
          debugPrint('⚠️ [$screenId] استخدام القيمة الاحتياطية بعد فشل المحاولات');
          return false;
        },
        onRetry: (attempt, error) {
          debugPrint('🔄 [$screenId] إعادة المحاولة $attempt');
        },
      );
      
      if (success == true) {
        _hasChanges = false;
        _emitStatus(SyncStatus.synced);
        debugPrint('✅ [$screenId] تمت المزامنة بنجاح');
        return true;
      } else {
        debugPrint('⚠️ [$screenId] فشل الرفع - إضافة للطابور');
        await _addToQueue();
        return false;
      }
    } on CircuitBreakerOpenException catch (e) {
      debugPrint('🔌 [$screenId] Circuit breaker مفتوح: $e');
      _emitStatus(SyncStatus.error);
      await _addToQueue();
      return false;
    } catch (e, stackTrace) {
      SyncErrorHandler.instance.handleError(
        e,
        stackTrace: stackTrace,
        context: {'screenId': screenId, 'operation': 'syncNow'},
      );
      debugPrint('❌ [$screenId] خطأ في المزامنة: $e');
      _emitStatus(SyncStatus.error);
      await _addToQueue();
      return false;
    } finally {
      _isSyncing = false;
    }
  }
  
  Future<void> _addToQueue() async {
    try {
      final data = {'timestamp': DateTime.now().toIso8601String(), 'screenId': screenId};
      
      final validation = SyncValidator.instance.validateSyncData(data);
      SyncValidator.instance.logValidationResult('Queue data', validation);
      
      if (!validation.isValid) {
        debugPrint('❌ [$screenId] بيانات غير صالحة: ${validation.error}');
        _emitStatus(SyncStatus.error);
        return;
      }
      
      await SyncQueueService.instance.addToQueue(
        screenId: screenId,
        data: data,
      );
      _hasChanges = false;
      _emitStatus(SyncStatus.queued);
    } catch (e, stackTrace) {
      SyncErrorHandler.instance.handleError(
        e,
        stackTrace: stackTrace,
        context: {'screenId': screenId, 'operation': 'addToQueue'},
      );
      _emitStatus(SyncStatus.error);
    }
  }
  
  void _emitStatus(SyncStatus status) {
    _syncStatusController.add(status);
  }
  
  Future<bool> syncOnExit() async {
    debugPrint('🚪 [$screenId] الخروج من الشاشة...');
    cancelTimer();
    return await syncNow();
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
    
    // محاولة مزامنة نهائية بشكل fire-and-forget
    // لن ننتظرها لتجنب state leak، لكن نعطيها فرصة للعمل
    if (_hasChanges && !_isSyncing) {
      syncNow().catchError((error) {
        debugPrint('⚠️ [$screenId] خطأ في المزامنة النهائية عند dispose: $error');
      });
    }
    
    // إغلاق الموارد فوراً
    if (!_syncStatusController.isClosed) {
      _syncStatusController.close();
    }
    _circuitBreaker.dispose();
  }
}

enum SyncStatus {
  idle,
  pending,
  syncing,
  synced,
  queued,
  error,
}
