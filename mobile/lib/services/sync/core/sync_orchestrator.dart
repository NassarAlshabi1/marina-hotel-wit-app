import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sync_state.dart';
import '../models/sync_result.dart';
import '../strategies/retry_strategy.dart';
import '../adapters/sync_adapter.dart';
import 'network_connectivity_listener.dart';

/// منسق المزامنة الموحد - نقطة الدخول الوحيدة لكل عمليات المزامنة
class SyncOrchestrator {

  SyncOrchestrator._();
  static SyncOrchestrator? _instance;
  static SyncOrchestrator get instance => _instance ??= SyncOrchestrator._();

  final List<SyncAdapter> _adapters = [];
  
  // Mock outbox for compatibility with existing UI code
  final outbox = _MockOutbox();
  final StreamController<SyncState> _stateController = StreamController<SyncState>.broadcast();
  final RetryStrategy _retryStrategy = ExponentialBackoffStrategy();
  
  SyncState _state = SyncState.idle();
  SyncState get currentState => _state;
  
  Stream<SyncState> get stateStream => _stateController.stream;
  
  bool _isInitialized = false;
  bool _isSyncing = false;

  /// تهيئة المنظم
  Future<void> initialize(List<SyncAdapter> adapters) async {
    if (_isInitialized) return;
    
    _adapters.addAll(adapters);
    
    // تهيئة جميع المحولات
    for (final adapter in _adapters) {
      await adapter.initialize();
    }
    
    _isInitialized = true;
    _emitState(SyncState.idle());

    // بدء مراقبة حالة الشبكة تلقائياً عند التهيئة
    NetworkConnectivityListener.instance.startMonitoring();
  }

  /// مزامنة فورية مع جميع المحولات
  Future<SyncResult> syncNow({
    bool push = true,
    bool pull = true,
    SyncPriority priority = SyncPriority.normal,
    String? reason,
  }) async {
    if (_isSyncing) {
      return SyncResult.conflict('المزامنة قيد التقدم بالفعل');
    }

    _isSyncing = true;
    _emitState(SyncState.syncing(progress: 0));

    final results = <String, SyncResult>{};
    int completed = 0;

    try {
      for (final adapter in _adapters) {
        if (!adapter.isEnabled) continue;

        _emitState(SyncState.syncing(
          progress: (completed / _adapters.length * 100).toInt(),
          message: 'مزامنة ${adapter.name}...',
        ));

        final result = await _syncWithRetry(adapter, push: push, pull: pull);
        results[adapter.name] = result;
        
        if (result.isSuccess) {
          completed++;
        }
      }

      final allSuccess = results.values.every((r) => r.isSuccess ?? false);
      final totalPushed = results.values.fold<int>(0, (sum, r) => sum + (r.pushedCount ?? 0));
      final totalPulled = results.values.fold<int>(0, (sum, r) => sum + (r.pulledCount ?? 0));

      final result = SyncResult.success(
        pushed: totalPushed,
        pulled: totalPulled,
        adapters: results,
      );

      _emitState(allSuccess ? SyncState.idle() : SyncState.error(result.message));
      return result;
    } catch (e) {
      final errorResult = SyncResult.error('خطأ في المزامنة: $e');
      _emitState(SyncState.error(errorResult.message));
      return errorResult;
    } finally {
      _isSyncing = false;
    }
  }

  /// مزامنة مع إعادة محاولة
  Future<SyncResult> _syncWithRetry(
    SyncAdapter adapter, {
    required bool push,
    required bool pull,
  }) async {
    return _retryStrategy.execute(() async {
      return adapter.sync(push: push, pull: pull);
    });
  }

  /// دفع التغييرات المحلية فقط (بدون سحب)
  Future<SyncResult> pushOnly() async {
    return syncNow(push: true, pull: false);
  }

  /// سحب التغييرات من السحابة فقط (بدون دفع)
  Future<SyncResult> pullOnly() async {
    return syncNow(push: false, pull: true);
  }

  /// الحصول على حالة المزامنة الحالية
  Future<SyncStatus> getCurrentStatus() async {
    if (_isSyncing) return SyncStatus.syncing;
    
    final anyEnabled = _adapters.any((a) => a.isEnabled);
    if (!anyEnabled) return SyncStatus.disabled;
    
    return SyncStatus.idle;
  }

  /// تفعيل/تعطيل محول معين
  Future<void> setAdapterEnabled(String adapterName, bool enabled) async {
    final adapter = _adapters.firstWhere(
      (a) => a.name == adapterName,
      orElse: () => throw StateError('المحول $adapterName غير موجود'),
    );
    await adapter.setEnabled(enabled);
  }

  /// إضافة مستمع للتغيرات
  void addStateListener(void Function(SyncState) listener) {
    _stateController.stream.listen(listener);
  }

  void _emitState(SyncState state) {
    _state = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  void dispose() {
    NetworkConnectivityListener.instance.stopMonitoring();
    _stateController.close();
    for (final adapter in _adapters) {
      adapter.dispose();
    }
  }
}

class _MockOutbox {
  final StreamController<int> _controller = StreamController<int>.broadcast();
  Stream<int> get pendingCountStream => _controller.stream;
  Future<int> get pendingCount async => 0;
}

/// Provider Riverpod للمزامنة
final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) {
  return SyncOrchestrator.instance;
});

final syncStateProvider = StreamProvider<SyncState>((ref) {
  return SyncOrchestrator.instance.stateStream;
});
