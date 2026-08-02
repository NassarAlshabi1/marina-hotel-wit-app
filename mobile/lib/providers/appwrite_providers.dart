import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/appwrite_cache_manager.dart';
import '../services/appwrite_models.dart';
import '../services/appwrite_service.dart';
import '../services/appwrite_sync_manager.dart';

// ─── Backward-compatible providers (used by all settings screens) ───

// Replaces appwriteSyncManagerProvider. Returns the singleton
// CloudflareSyncManager (aliased as AppwriteSyncManager).
final appwriteSyncManagerProvider = Provider<AppwriteSyncManager>((ref) {
  return AppwriteSyncManager();
});

// Stub providers for backward compat with screens that still reference them
final appwriteServiceProvider = Provider<AppwriteService?>((ref) => null);
final appwriteLoggerProvider = Provider<_StubLogger>((ref) => _StubLogger());
final appwriteCacheManagerProvider = Provider<AppwriteCacheManager>((ref) {
  return AppwriteCacheManager();
});

// ─── Connection status (returns a ConnectionState-like value) ───
//
// Many screens expect:
//   - ref.read(connectionStatusProvider.notifier).checkConnection()
//   - ref.watch(connectionStatusProvider).isConnected
// We provide a NotifierFamily that yields a ConnectionState value.
final connectionStatusProvider =
    NotifierProvider<ConnectionStatusNotifier, ConnectionState>(
        ConnectionStatusNotifier.new);

class ConnectionState {
  const ConnectionState({
    this.isConnected = false,
    this.isChecking = false,
    this.status = 'unknown',
    this.latencyMs,
    this.lastChecked,
    this.errorMessage,
  });

  final bool isConnected;
  final bool isChecking;
  final String status;
  final int? latencyMs;
  final DateTime? lastChecked;
  final String? errorMessage;

  ConnectionState copyWith({
    bool? isConnected,
    bool? isChecking,
    String? status,
    int? latencyMs,
    DateTime? lastChecked,
    String? errorMessage,
  }) {
    return ConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isChecking: isChecking ?? this.isChecking,
      status: status ?? this.status,
      latencyMs: latencyMs ?? this.latencyMs,
      lastChecked: lastChecked ?? this.lastChecked,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ConnectionStatusNotifier extends Notifier<ConnectionState> {
  @override
  ConnectionState build() {
    // Kick off a background connection check.
    Future.microtask(checkConnection);
    return const ConnectionState();
  }

  Future<void> checkConnection() async {
    state = state.copyWith(isChecking: true);
    try {
      final manager = ref.read(appwriteSyncManagerProvider);
      await manager.initialize();
      state = ConnectionState(
        isConnected: manager.isAvailable,
        
        status: manager.isAvailable ? 'connected' : 'disconnected',
        lastChecked: DateTime.now(),
        errorMessage: manager.initError,
      );
    } catch (e) {
      state = ConnectionState(
        status: 'error',
        errorMessage: e.toString(),
        lastChecked: DateTime.now(),
      );
    }
  }
}

// ─── Sync statistics provider (returns a Map<String,dynamic>) ───
//
// appwrite_sync_stats_screen.dart expects:
//   ref.watch(syncStatsProvider).when(data: (stats) => ...)
//   stats['outboxCount'], stats['lastSyncAt'], etc.
// We return a Map so existing screens work without changes.
final syncStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final manager = ref.read(appwriteSyncManagerProvider);
  await manager.initialize();
  return {
    'outboxCount': 0,
    'lastSyncAt': DateTime.now().toIso8601String(),
    'lastError': manager.lastError,
    'totalPushed': 0,
    'totalPulled': 0,
    'conflicts': 0,
    'successRate': 100.0,
    // Extra fields expected by appwrite_sync_stats_screen
    'totalSyncs': 0,
    'successfulSyncs': 0,
    'failedSyncs': 0,
    'totalRecordsPushed': 0,
    'totalRecordsPulled': 0,
    'totalConflicts': 0,
  };
});

// ─── Cache statistics provider (returns CacheStatistics) ───
final cacheStatsProvider = Provider<CacheStatistics>((ref) {
  final cache = ref.read(appwriteCacheManagerProvider);
  return cache.getStatistics();
});

// ─── Log statistics provider (returns Map<String,int>) ───
final logStatsProvider = Provider<Map<String, int>>((ref) {
  return {'total': 0, 'error': 0, 'warning': 0, 'info': 0, 'debug': 0};
});

// ─── Project info provider (returns Map<String,String>) ───
final projectInfoProvider = Provider<Map<String, String>>((ref) {
  return {
    'name': 'Marina Hotel',
    'version': '1.0.0',
    'database': 'cloudflare-d1',
    'endpoint': 'https://marina-hotel-api.adenmarina2.workers.dev',
  };
});

// ─── Devices list provider ───
final devicesListProvider = FutureProvider<List<AppwriteDevice>>((ref) async {
  // Currently returns an empty list — CloudflareSyncManager does not yet
  // implement a "list registered devices" endpoint. The settings screen
  // handles the empty case gracefully.
  return <AppwriteDevice>[];
});

// ─── Stub logger (used by appwrite_settings_screen for clearLogs/exportLogs) ───
class _StubLogger {
  void clearLogs() {}
  Future<dynamic> exportLogs() async => null;
  List<dynamic> getLogs() => const [];
}
