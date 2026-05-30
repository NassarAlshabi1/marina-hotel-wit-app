import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/google_drive_auto_sync_engine.dart';
import '../services/google_drive_conflict_resolver.dart';
import '../services/google_drive_unified_sync_coordinator.dart';

// ═══════════════════════════════════════════════════════════════════
// ⚠️ Google Drive Auto-Sync is DISABLED
// All providers below return safe defaults / stub values.
// They are kept for compilation compatibility — any code that
// references them will get "disabled" responses.
// Manual backup/restore via GoogleDriveBackupService still works.
// ═══════════════════════════════════════════════════════════════════

/// [DISABLED] Returns the stubbed AutoSyncEngine instance.
/// The engine's methods are all no-ops that return disabled results.
final autoSyncEngineProvider = Provider<AutoSyncEngine>((ref) {
  ref.keepAlive();
  return AutoSyncEngine.instance;
});

/// [DISABLED] Returns a never-emitting stream (engine is stopped).
final autoSyncEngineStateProvider = StreamProvider<AutoSyncEngineState>((ref) {
  final engine = ref.watch(autoSyncEngineProvider);
  return engine.stateStream;
});

/// [DISABLED] Returns the stubbed coordinator instance.
final unifiedSyncCoordinatorProvider =
    Provider<GoogleDriveUnifiedSyncCoordinator>((ref) {
      ref.keepAlive();
      return GoogleDriveUnifiedSyncCoordinator.instance;
    });

/// [DISABLED] Returns a never-emitting stream of sync results.
final syncResultsStreamProvider = StreamProvider<SyncResult>((ref) {
  final coordinator = ref.watch(unifiedSyncCoordinatorProvider);
  return coordinator.syncResults;
});

/// [DISABLED] Returns the stubbed conflict resolver instance.
final conflictResolverProvider = Provider<GoogleDriveConflictResolver>((ref) {
  ref.keepAlive();
  return GoogleDriveConflictResolver.instance;
});

/// [DISABLED] Returns engine status with all-zero / disabled values.
final autoSyncEngineStatusProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final engine = ref.watch(autoSyncEngineProvider);
  return engine.getEngineStatus();
});

/// [DISABLED] Returns zero conflict statistics.
final conflictStatisticsProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final resolver = ref.watch(conflictResolverProvider);
  return resolver.getConflictStatistics();
});

/// [DISABLED] Returns empty conflict history.
final conflictHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final resolver = ref.watch(conflictResolverProvider);
  return resolver.getConflictHistory(limit: 50);
});

/// [DISABLED] Controller for the auto-sync engine.
/// All operations are no-ops on the stubbed engine.
class AutoSyncEngineController
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
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

  /// [DISABLED] No-op on stubbed engine.
  Future<void> setDebounceSeconds(int seconds) async {
    await engine.setDebounceSeconds(seconds);
    await _loadStatus();
  }

  /// [DISABLED] No-op on stubbed engine.
  Future<void> setPullInterval(int minutes) async {
    await engine.setPullInterval(minutes);
    await _loadStatus();
  }

  /// [DISABLED] No-op on stubbed engine.
  Future<void> setConflictStrategy(ConflictResolutionStrategy strategy) async {
    await engine.setConflictStrategy(strategy);
    await _loadStatus();
  }

  /// [DISABLED] No-op on stubbed engine.
  Future<void> setRetryEnabled(bool enabled) async {
    await engine.setRetryEnabled(enabled);
    await _loadStatus();
  }

  /// [DISABLED] Returns failure result on stubbed engine.
  Future<SyncResult> forceSyncNow() async {
    final result = await engine.forceSyncNow();
    await _loadStatus();
    return result;
  }

  /// [DISABLED] No-op on stubbed engine.
  Future<void> resetFailedAttempts() async {
    await engine.resetFailedAttempts();
    await _loadStatus();
  }
}

final autoSyncEngineControllerProvider =
    StateNotifierProvider<
      AutoSyncEngineController,
      AsyncValue<Map<String, dynamic>>
    >((ref) {
      final engine = ref.watch(autoSyncEngineProvider);
      return AutoSyncEngineController(engine);
    });

/// [DISABLED] Always returns false (coordinator is never syncing).
final isSyncingProvider = Provider<bool>((ref) {
  final coordinatorState = ref.watch(unifiedSyncCoordinatorProvider);
  return coordinatorState.isSyncing;
});

/// [DISABLED] Always returns false (no pending changes).
final hasPendingChangesProvider = Provider<bool>((ref) {
  final engineState = ref.watch(autoSyncEngineStateProvider);
  return engineState.when(
    data: (state) => state.pendingChangesCount > 0,
    loading: () => false,
    error: (_, __) => false,
  );
});

/// [DISABLED] Always returns 0.
final pendingChangesCountProvider = Provider<int>((ref) {
  final engineState = ref.watch(autoSyncEngineStateProvider);
  return engineState.when(
    data: (state) => state.pendingChangesCount,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

/// [DISABLED] Always returns null (no sync ever happened).
final lastSyncTimeProvider = Provider<DateTime?>((ref) {
  final engineState = ref.watch(autoSyncEngineStateProvider);
  return engineState.when(
    data: (state) => state.lastSuccessfulSync,
    loading: () => null,
    error: (_, __) => null,
  );
});

/// [DISABLED] Always returns "disabled" status.
/// ✅ إصلاح: إعادة تسمية من syncHealthProvider لتجنب التعارض مع
/// StreamProvider<SyncHealthSnapshot> في repository_providers.dart
final autoSyncHealthSummaryProvider = Provider<String>((ref) {
  final engineState = ref.watch(autoSyncEngineStateProvider);
  return engineState.when(
    data: (state) {
      // Google Drive sync is disabled — always report disabled
      return '⛔ معطل (Google Drive Sync)';
    },
    loading: () => '⛔ معطل (Google Drive Sync)',
    error: (_, __) => '⛔ معطل (Google Drive Sync)',
  );
});
