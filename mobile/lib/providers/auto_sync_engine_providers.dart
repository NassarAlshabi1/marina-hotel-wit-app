import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/google_drive_auto_sync_engine.dart';
import '../services/google_drive_conflict_resolver.dart';
import '../services/google_drive_unified_sync_coordinator.dart';

final autoSyncEngineProvider = Provider<AutoSyncEngine>((ref) {
  ref.keepAlive();
  return AutoSyncEngine.instance;
});

final autoSyncEngineStateProvider = StreamProvider<AutoSyncEngineState>((ref) {
  final engine = ref.watch(autoSyncEngineProvider);
  return engine.stateStream;
});

final unifiedSyncCoordinatorProvider = Provider<GoogleDriveUnifiedSyncCoordinator>((ref) {
  ref.keepAlive();
  return GoogleDriveUnifiedSyncCoordinator.instance;
});

final syncResultsStreamProvider = StreamProvider<SyncResult>((ref) {
  final coordinator = ref.watch(unifiedSyncCoordinatorProvider);
  return coordinator.syncResults;
});

final conflictResolverProvider = Provider<GoogleDriveConflictResolver>((ref) {
  ref.keepAlive();
  return GoogleDriveConflictResolver.instance;
});

final autoSyncEngineStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final engine = ref.watch(autoSyncEngineProvider);
  return engine.getEngineStatus();
});

final conflictStatisticsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final resolver = ref.watch(conflictResolverProvider);
  return resolver.getConflictStatistics();
});

final conflictHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final resolver = ref.watch(conflictResolverProvider);
  return resolver.getConflictHistory(limit: 50);
});

class AutoSyncEngineController extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  AutoSyncEngineController(this.engine) : super(const AsyncValue.loading()) {
    _loadStatus();
  }

  final AutoSyncEngine engine;

  Future<void> _loadStatus() async {
    state = const AsyncValue.loading();
    try {
      final status = await engine.getEngineStatus();
      state = AsyncValue.data(status);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> refresh() => _loadStatus();

  Future<void> setDebounceSeconds(int seconds) async {
    await engine.setDebounceSeconds(seconds);
    await _loadStatus();
  }

  Future<void> setPullInterval(int minutes) async {
    await engine.setPullInterval(minutes);
    await _loadStatus();
  }

  Future<void> setConflictStrategy(ConflictResolutionStrategy strategy) async {
    await engine.setConflictStrategy(strategy);
    await _loadStatus();
  }

  Future<void> setRetryEnabled(bool enabled) async {
    await engine.setRetryEnabled(enabled);
    await _loadStatus();
  }

  Future<SyncResult> forceSyncNow() async {
    final result = await engine.forceSyncNow();
    await _loadStatus();
    return result;
  }

  Future<void> resetFailedAttempts() async {
    await engine.resetFailedAttempts();
    await _loadStatus();
  }
}

final autoSyncEngineControllerProvider =
    StateNotifierProvider<AutoSyncEngineController, AsyncValue<Map<String, dynamic>>>((ref) {
      final engine = ref.watch(autoSyncEngineProvider);
      return AutoSyncEngineController(engine);
    });

final isSyncingProvider = Provider<bool>((ref) {
  final coordinatorState = ref.watch(unifiedSyncCoordinatorProvider);
  return coordinatorState.isSyncing;
});

final hasPendingChangesProvider = Provider<bool>((ref) {
  final engineState = ref.watch(autoSyncEngineStateProvider);
  return engineState.when(
    data: (state) => state.pendingChangesCount > 0,
    loading: () => false,
    error: (_, __) => false,
  );
});

final pendingChangesCountProvider = Provider<int>((ref) {
  final engineState = ref.watch(autoSyncEngineStateProvider);
  return engineState.when(data: (state) => state.pendingChangesCount, loading: () => 0, error: (_, __) => 0);
});

final lastSyncTimeProvider = Provider<DateTime?>((ref) {
  final engineState = ref.watch(autoSyncEngineStateProvider);
  return engineState.when(data: (state) => state.lastSuccessfulSync, loading: () => null, error: (_, __) => null);
});

/// ✅ إصلاح: إعادة تسمية من syncHealthProvider لتجنب التعارض مع
/// StreamProvider<SyncHealthSnapshot> في repository_providers.dart
final autoSyncHealthSummaryProvider = Provider<String>((ref) {
  final engineState = ref.watch(autoSyncEngineStateProvider);
  return engineState.when(
    data: (state) {
      if (!state.isRunning) {
        return '🔴 متوقف';
      }
      if (!state.hasNetworkConnection) {
        return '📴 بدون شبكة';
      }
      if (!state.isSignedIn) {
        return '🔓 غير مسجل';
      }
      if (state.failedAttempts > 0) {
        return '⚠️ محاولات فاشلة: ${state.failedAttempts}';
      }
      if (state.pendingChangesCount > 0) {
        return '⏳ معلق: ${state.pendingChangesCount}';
      }
      return '🟢 جاهز';
    },
    loading: () => '⏳ جارٍ التحميل',
    error: (_, __) => '❌ خطأ',
  );
});
