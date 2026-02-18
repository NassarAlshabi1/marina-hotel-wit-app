import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/appwrite_service.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/appwrite_sync_manager_enhanced.dart';
import '../services/appwrite_cache_manager.dart';
import '../services/unified_sync_orchestrator.dart';
import '../services/smart_sync_manager.dart';
import '../services/appwrite_logger.dart';
import '../services/appwrite_error_handler.dart';
import '../services/providers.dart';
import '../services/daos/outbox_dao.dart';
import '../services/unified_conflict_resolver.dart';
import '../services/google_drive_unified_sync_coordinator.dart';

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

  ref.onDispose(() {
    manager.dispose();
  });

  return manager;
});

/// مزود مدير المزامنة المتقدم مع حل التعارضات
final enhancedSyncManagerProvider = Provider<AppwriteSyncManagerEnhanced>((ref) {
  final service = ref.watch(appwriteServiceProvider);
  final database = ref.watch(databaseProvider);

  // استراتيجيات حل التعارضات مُعرفة داخلياً في المدير المتقدم
  // - fieldLevel: للجداول الحساسة (bookings, payments, cash_transactions, expenses, debts)
  // - lastWriteWins: للجداول العادية

  final manager = AppwriteSyncManagerEnhanced(
    appwriteService: service,
    database: database,
  );

  ref.onDispose(() {
    manager.dispose();
  });

  return manager;
});

/// مزود المنسق الموحد للمزامنة - يستخدم المدير المتقدم مع حل التعارضات
final unifiedSyncOrchestratorProvider = Provider<UnifiedSyncOrchestrator>((
  ref,
) {
  // استخدام المدير المتقدم افتراضياً لتفعيل حل التعارضات
  final enhancedSync = ref.watch(enhancedSyncManagerProvider);
  final db = ref.watch(databaseProvider);
  final smart = SmartSyncManager.instance;
  final orch = UnifiedSyncOrchestrator.instance;
  orch.initialize(appwrite: enhancedSync, smart: smart, database: db);
  return orch;
});

final unifiedSyncStateProvider = StreamProvider<UnifiedSyncState>((ref) {
  final orch = ref.watch(unifiedSyncOrchestratorProvider);
  ref.onDispose(() => orch.dispose());
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
  final bool isConnected;
  final bool isChecking;
  final String? errorMessage;

  ConnectionState({
    required this.isConnected,
    this.isChecking = false,
    this.errorMessage,
  });

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
  final Ref ref;

  ConnectionStatusNotifier(this.ref)
    : super(ConnectionState(isConnected: false));

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
        errorMessage: 'خطأ في الاتصال: ${e.toString()}',
      );
    }
  }
}

// ============ Data Providers ============

/// مزود إحصائيات المزامنة - يستخدم المدير المتقدم
final syncStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final syncManager = ref.watch(enhancedSyncManagerProvider);
  return await syncManager.getSyncStatistics();
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

/// مزود قائمة الأجهزة المسجلة - يستخدم المدير المتقدم
final devicesListProvider = FutureProvider((ref) async {
  final syncManager = ref.watch(enhancedSyncManagerProvider);
  final devices = await syncManager.getRegisteredDevices();
  devices.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  return devices.take(3).toList(growable: false);
});

/// مزود السجلات
final logsProvider = Provider((ref) {
  final logger = ref.watch(appwriteLoggerProvider);
  return logger.getLogs();
});

// ============ Conflict Resolution Providers ============

/// مزود محلل التعارضات الموحد
final unifiedConflictResolverProvider = Provider<UnifiedConflictResolver>((ref) {
  final db = ref.watch(databaseProvider);
  // التأكد من التهيئة
  UnifiedConflictResolver.instance.initialize(database: db);
  return UnifiedConflictResolver.instance;
});

/// مزود تيار التعارضات المعلقة
final pendingConflictsStreamProvider = StreamProvider<List<UnifiedConflictRecord>>((ref) {
  final resolver = ref.watch(unifiedConflictResolverProvider);
  return resolver.conflictsStream;
});

/// مزود عدد التعارضات المعلقة
final pendingConflictsCountProvider = Provider<int>((ref) {
  final resolver = ref.watch(unifiedConflictResolverProvider);
  return resolver.pendingCount;
});

/// مزود إحصائيات التعارضات
final conflictStatisticsProvider = Provider<Map<String, dynamic>>((ref) {
  final resolver = ref.watch(unifiedConflictResolverProvider);
  return resolver.getStatistics();
});

/// مزود المنسق الموحد لـ Google Drive
final googleDriveCoordinatorProvider = Provider<GoogleDriveUnifiedSyncCoordinator>((ref) {
  return GoogleDriveUnifiedSyncCoordinator.instance;
});

/// مزود تيار نتائج مزامنة Google Drive
final googleDriveSyncResultsProvider = StreamProvider<SyncResult>((ref) {
  final coordinator = ref.watch(googleDriveCoordinatorProvider);
  return coordinator.syncResults;
});

/// مزود تيار التعارضات من Google Drive
final googleDriveConflictsProvider = StreamProvider<UnifiedConflictRecord?>((ref) {
  final coordinator = ref.watch(googleDriveCoordinatorProvider);
  return coordinator.conflictStream;
});
