import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/sync_adapter.dart';
import '../models/sync_result.dart';
import '../models/sync_state.dart';

/// منسق المزامنة الموحد - نقطة الدخول الوحيدة لكل عمليات المزامنة
class SyncOrchestrator {
  SyncOrchestrator._();
  static SyncOrchestrator? _instance;
  // ignore: prefer_constructors_over_static_methods
  static SyncOrchestrator get instance => _instance ??= SyncOrchestrator._();

  final List<SyncAdapter> _adapters = [];
  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();

  // إعدادات إعادة المحاولة المضمنة (تم حذف ملف strategies/retry_strategy.dart
  // أثناء التنظيف المعماري — أُبقيت المنطق هنا لأنه الواجهة الوحيدة المستخدمة).
  static const int _maxAttempts = 5;
  static const Duration _initialDelay = Duration(seconds: 1);
  static const Duration _maxDelay = Duration(minutes: 5);
  static const double _backoffMultiplier = 2.0;

  Stream<SyncState> get stateStream => _stateController.stream;

  bool _isInitialized = false;
  bool _isSyncing = false;

  /// تهيئة المنظم
  Future<void> initialize(List<SyncAdapter> adapters) async {
    if (_isInitialized) {
      return;
    }

    _adapters.addAll(adapters);

    // تهيئة جميع المحولات
    for (final adapter in _adapters) {
      await adapter.initialize();
    }

    _isInitialized = true;
    _emitState(SyncState.idle());
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
    _emitState(SyncState.syncing());

    final results = <String, SyncResult>{};
    int completed = 0;

    try {
      for (final adapter in _adapters) {
        if (!adapter.isEnabled) {
          continue;
        }

        _emitState(
          SyncState.syncing(
            progress: (completed / _adapters.length * 100).toInt(),
            message: 'مزامنة ${adapter.name}...',
          ),
        );

        final result = await _syncWithRetry(adapter, push: push, pull: pull);
        results[adapter.name] = result;

        if (result.isSuccess) {
          completed++;
        }
      }

      final allSuccess = results.values.every((r) => r.isSuccess);
      final totalPushed = results.values.fold<int>(
        0,
        (sum, r) => sum + r.pushedCount,
      );
      final totalPulled = results.values.fold<int>(
        0,
        (sum, r) => sum + r.pulledCount,
      );

      final result = SyncResult.success(
        pushed: totalPushed,
        pulled: totalPulled,
        adapters: results,
      );

      _emitState(
        allSuccess ? SyncState.idle() : SyncState.error(result.message),
      );
      return result;
    } catch (e) {
      final errorResult = SyncResult.error('خطأ في المزامنة: $e');
      _emitState(SyncState.error(errorResult.message));
      return errorResult;
    } finally {
      _isSyncing = false;
    }
  }

  /// مزامنة مع إعادة محاولة (Exponential Backoff + Jitter).
  Future<SyncResult> _syncWithRetry(
    SyncAdapter adapter, {
    required bool push,
    required bool pull,
  }) async {
    int attempt = 0;
    Duration currentDelay = _initialDelay;

    while (true) {
      try {
        return await adapter.sync(push: push, pull: pull);
      } catch (e) {
        attempt++;
        if (attempt >= _maxAttempts) {
          return SyncResult.error(
            'فشلت المزامنة بعد $_maxAttempts محاولات: $e',
          );
        }
        final jitter = Random().nextInt(1000);
        await Future<void>.delayed(
          currentDelay + Duration(milliseconds: jitter),
        );
        currentDelay = Duration(
          milliseconds: min(
            (currentDelay.inMilliseconds * _backoffMultiplier).toInt(),
            _maxDelay.inMilliseconds,
          ),
        );
      }
    }
  }

  /// دفع التغييرات المحلية فقط (بدون سحب)
  Future<SyncResult> pushOnly() async {
    return syncNow(pull: false);
  }

  /// سحب التغييرات من السحابة فقط (بدون دفع)
  Future<SyncResult> pullOnly() async {
    return syncNow(push: false);
  }

  /// الحصول على حالة المزامنة الحالية
  Future<SyncStatus> getCurrentStatus() async {
    if (_isSyncing) {
      return SyncStatus.syncing;
    }

    final anyEnabled = _adapters.any((a) => a.isEnabled);
    if (!anyEnabled) {
      return SyncStatus.disabled;
    }

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
    unawaited(_stateController.close());
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
