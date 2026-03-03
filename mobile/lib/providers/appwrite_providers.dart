// DEPRECATED: Use appwriteConfigProvider for unified state
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/appwrite_service.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/appwrite_cache_manager.dart';
import '../services/unified_sync_orchestrator.dart';
import '../services/smart_sync_manager.dart';
import '../services/appwrite_logger.dart';
import '../services/appwrite_error_handler.dart';
import '../services/providers.dart';
import '../services/daos/outbox_dao.dart';

// ============ Service Providers ============

/// مزود خدمة Appwrite
final appwriteServiceProvider = Provider<AppwriteService>((ref) {
  return AppwriteService();
});

/// مزود مدير المزامنة
final appwriteSyncManagerProvider = Provider<AppwriteSyncManager>((ref) {
  final service = ref.watch(appwriteServiceProvider);
  final database = ref.watch(databaseProvider);
  final manager = AppwriteSyncManager(
    appwriteService: service,
    database: database,
  );

  ref.onDispose(manager.dispose);

  return manager;
});

final unifiedSyncOrchestratorProvider = Provider<UnifiedSyncOrchestrator>((
  ref,
) {
  final appwriteSync = ref.watch(appwriteSyncManagerProvider);
  final db = ref.watch(databaseProvider);
  final smart = SmartSyncManager.instance;
  final orch = UnifiedSyncOrchestrator.instance;
  orch.initialize(appwrite: appwriteSync, smart: smart, database: db);
  return orch;
});

final unifiedSyncStateProvider = StreamProvider<UnifiedSyncState>((ref) {
  final orch = ref.watch(unifiedSyncOrchestratorProvider);
  ref.onDispose(orch.dispose);
  return orch.stateStream;
});

/// مزود مدير الذاكرة المؤقتة
final appwriteCacheManagerProvider = Provider<AppwriteCacheManager>((ref) {
  return AppwriteCacheManager();
});

/// مزود المسجل
final appwriteLoggerProvider = Provider<AppwriteLogger>((ref) {
  return AppwriteLogger();
});

/// مزود معالج الأخطاء
final appwriteErrorHandlerProvider = Provider<AppwriteErrorHandler>((ref) {
  return AppwriteErrorHandler();
});

// ============ State Providers ============

/// مزود حالة الاتصال
final connectionStatusProvider =
    StateNotifierProvider<ConnectionStatusNotifier, ConnectionState>((ref) {
  return ConnectionStatusNotifier(ref);
});

class ConnectionState {
  ConnectionState({
    required this.isConnected,
    this.isChecking = false,
    this.errorMessage,
  });
  final bool isConnected;
  final bool isChecking;
  final String? errorMessage;

  ConnectionState copyWith({
    bool? isConnected,
    bool? isChecking,
    String? errorMessage,
  }) {
    return ConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isChecking: isChecking ?? this.isChecking,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ConnectionStatusNotifier extends StateNotifier<ConnectionState> {
  ConnectionStatusNotifier(this.ref)
      : super(ConnectionState(isConnected: false));
  final Ref ref;

  Future<void> checkConnection() async {
    state = state.copyWith(isChecking: true, errorMessage: null);

    try {
      final service = ref.read(appwriteServiceProvider);
      await service.initialize();
      final connectionResult = await service.testConnection();
      final isConnected = connectionResult['overall_success'] == true;
      final failureMessage = isConnected
          ? null
          : (connectionResult['error'] as String?) ?? 'فشل الاتصال بـ Appwrite';

      state = ConnectionState(
        isConnected: isConnected,
        isChecking: false,
        errorMessage: failureMessage,
      );
    } catch (e) {
      state = ConnectionState(
        isConnected: false,
        isChecking: false,
        errorMessage: 'خطأ في الاتصال: $e',
      );
    }
  }
}

// ============ Data Providers ============

/// مزود إحصائيات المزامنة
final syncStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final syncManager = ref.watch(appwriteSyncManagerProvider);
  return syncManager.getSyncStatistics();
});

final outboxCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  final dao = OutboxDao(db);
  return dao.watchCount();
});

/// مزود إحصائيات الذاكرة المؤقتة
final cacheStatsProvider = Provider<CacheStatistics>((ref) {
  final cacheManager = ref.watch(appwriteCacheManagerProvider);
  return cacheManager.getStatistics();
});

/// مزود إحصائيات السجلات
final logStatsProvider = Provider<Map<String, int>>((ref) {
  final logger = ref.watch(appwriteLoggerProvider);
  return logger.getStatistics();
});

/// مزود معلومات المشروع
final projectInfoProvider = Provider<Map<String, String>>((ref) {
  final service = ref.watch(appwriteServiceProvider);
  return service.getProjectInfo();
});

/// مزود قائمة الأجهزة المسجلة (أحدث ثلاثة أجهزة فقط)
final devicesListProvider = FutureProvider((ref) async {
  final syncManager = ref.watch(appwriteSyncManagerProvider);
  final devices = await syncManager.getRegisteredDevices();
  devices.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  return devices.take(3).toList(growable: false);
});

/// مزود السجلات
final logsProvider = Provider((ref) {
  final logger = ref.watch(appwriteLoggerProvider);
  return logger.getLogs();
});


/// State model for Appwrite configuration
class AppwriteConfigState {
  final bool isConnected;
  final bool isChecking;
  final String? errorMessage;
  final Map<String, dynamic> syncStats;
  final CacheStatistics? cacheStats;
  final int outboxCount;

  AppwriteConfigState({
    this.isConnected = false,
    this.isChecking = false,
    this.errorMessage,
    this.syncStats = const {},
    this.cacheStats,
    this.outboxCount = 0,
  });

  AppwriteConfigState copyWith({
    bool? isConnected,
    bool? isChecking,
    String? errorMessage,
    Map<String, dynamic>? syncStats,
    CacheStatistics? cacheStats,
    int? outboxCount,
  }) {
    return AppwriteConfigState(
      isConnected: isConnected ?? this.isConnected,
      isChecking: isChecking ?? this.isChecking,
      errorMessage: errorMessage ?? this.errorMessage,
      syncStats: syncStats ?? this.syncStats,
      cacheStats: cacheStats ?? this.cacheStats,
      outboxCount: outboxCount ?? this.outboxCount,
    );
  }
}

class AppwriteConfigNotifier extends StateNotifier<AppwriteConfigState> {
  final Ref ref;

  AppwriteConfigNotifier(this.ref) : super(AppwriteConfigState()) {
    _initListeners();
  }

  void _initListeners() {
    ref.listen(outboxCountProvider, (previous, next) {
      next.whenData((count) {
        state = state.copyWith(outboxCount: count);
      });
    });
  }

  Future<void> refreshAll() async {
    await checkConnection();
    await updateStats();
  }

  Future<void> checkConnection() async {
    state = state.copyWith(isChecking: true, errorMessage: null);
    try {
      final service = ref.read(appwriteServiceProvider);
      await service.initialize();
      final result = await service.testConnection();
      state = state.copyWith(
        isConnected: result['overall_success'] == true,
        isChecking: false,
        errorMessage: result['overall_success'] == true ? null : result['error'],
      );
    } catch (e) {
      state = state.copyWith(isConnected: false, isChecking: false, errorMessage: e.toString());
    }
  }

  Future<void> updateStats() async {
    final syncManager = ref.read(appwriteSyncManagerProvider);
    final stats = await syncManager.getSyncStatistics();
    final cacheManager = ref.read(appwriteCacheManagerProvider);
    final cStats = cacheManager.getStatistics();
    
    state = state.copyWith(
      syncStats: stats,
      cacheStats: cStats,
    );
  }
}

/// Unified provider for Appwrite configuration and stats
final appwriteConfigProvider = StateNotifierProvider<AppwriteConfigNotifier, AppwriteConfigState>((ref) {
  return AppwriteConfigNotifier(ref);
});
