import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sync_state.dart';
import '../models/sync_result.dart';
import '../strategies/retry_strategy.dart';
import '../adapters/sync_adapter.dart';

/// منسق المزامنة الموحد - نقطة الدخول الوحيدة لكل عمليات المزامنة
class SyncOrchestrator {
  SyncOrchestrator._();
  static SyncOrchestrator? _instance;
  static SyncOrchestrator get instance => _instance ??= SyncOrchestrator._();

  final List<SyncAdapter> _adapters = [];
  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();
  final RetryStrategy _retryStrategy = ExponentialBackoffStrategy();

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
    unawaited(_emitState(SyncState.idle()));
  }

  /// مزامنة فورية مع جميع المحولات
  Future<SyncResult> syncNow({
    bool push = true,
    bool pull = true,
    SyncPriority priority = SyncPriority.normal,
  }) async {
    if (_isSyncing) {
      return SyncResult.conflict('المزامنة قيد التقدم بالفعل');
    }

    _isSyncing = true;
    unawaited(_emitState(SyncState.syncing(progress: 0)));

    final results = <String, SyncResult>{};
    final resultsFutures = <Future<MapEntry<String, SyncResult>>>[];

    try {
      for (final adapter in _adapters) {
        if (!adapter.isEnabled) continue;
        resultsFutures.add(
          _syncWithRetry(adapter, push: push, pull: pull)
              .then((result) => MapEntry(adapter.name, result)),
        );
      }

      final allResults = await Future.wait(resultsFutures);
      for (final entry in allResults) {
        results[entry.key] = entry.value;
      }

      final totalEnabledAdapters = _adapters.where((a) => a.isEnabled).length;
      final successfulAdapters = results.values.where((r) => r.isSuccess).length;
      final allSuccess = successfulAdapters == totalEnabledAdapters; // All enabled adapters succeeded

      final totalPushed = results.values.fold<int>(0, (sum, r) => sum + (r.pushedCount));
      final totalPulled = results.values.fold<int>(0, (sum, r) => sum + (r.pulledCount));

      final result = SyncResult.success(
        pushed: totalPushed,
        pulled: totalPulled,
        adapters: results,
      );

      unawaited(_emitState(
          allSuccess ? SyncState.idle() : SyncState.error(result.message)));
      return result;
    } catch (e) {
      final errorResult = SyncResult.error('خطأ في المزامنة: $e');
      unawaited(_emitState(SyncState.error(errorResult.message)));
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
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  void dispose() {
    _stateController.close();
    for (final adapter in _adapters) {
      adapter.dispose();
    }
  }
}

/// Provider Riverpod للمزامنة
final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) {
  return SyncOrchestrator.instance;
});

final syncStateProvider = StreamProvider<SyncState>((ref) {
  return SyncOrchestrator.instance.stateStream;
});
