import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/appwrite_cache_manager.dart';
import '../services/appwrite_error_handler.dart';
import '../services/appwrite_logger.dart';
import '../services/appwrite_service.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/daos/outbox_dao.dart';
import '../services/providers.dart';
import '../services/smart_sync_manager.dart';
import '../services/unified_sync_orchestrator.dart';

// ============ Service Providers ============

/// مزود خدمة Appwrite
final appwriteServiceProvider = Provider.autoDispose<AppwriteService>((ref) {
  return AppwriteService();
});

/// مزود مدير المزامنة
final appwriteSyncManagerProvider = Provider.autoDispose<AppwriteSyncManager>((ref) {
  // 🔴 keepAlive: المزامنة تعمل في الخلفية مع timers
  ref.keepAlive();
  
  final service = ref.watch(appwriteServiceProvider);
  final database = ref.watch(databaseProvider);
  final manager = AppwriteSyncManager(
    appwriteService: service,
    database: database,
  );

  ref.onDispose(manager.dispose);

  return manager;
});

final unifiedSyncOrchestratorProvider = Provider.autoDispose<UnifiedSyncOrchestrator>((
  ref,
) {
  // 🔴 keepAlive: المنسق يدير stateStream
  ref.keepAlive();
  
  final appwriteSync = ref.watch(appwriteSyncManagerProvider);
  final db = ref.watch(databaseProvider);
  final smart = SmartSyncManager.instance();
  final orch = UnifiedSyncOrchestrator.instance;
  orch.initialize(appwrite: appwriteSync, smart: smart, database: db);
  return orch;
});

final unifiedSyncStateProvider = StreamProvider.autoDispose<UnifiedSyncState>((ref) {
  final orch = ref.watch(unifiedSyncOrchestratorProvider);
  ref.onDispose(orch.dispose);
  return orch.stateStream;
});

/// مزود مدير الذاكرة المؤقتة
final appwriteCacheManagerProvider = Provider.autoDispose<AppwriteCacheManager>((ref) {
  // 🔴 keepAlive: cache manager لديه Timer للتنظيف الدوري
  ref.keepAlive();
  return AppwriteCacheManager();
});

/// مزود المسجل
///
/// ⚠️ صار ChangeNotifierProvider منذ 2026-06-26 لتمكين إعادة بناء
/// الشاشات فوراً عند مسح السجلات (clearLogs() → notifyListeners()).
/// لا نستخدم autoDispose لأن AppwriteLogger singleton — لا يجب أن
/// يُدمّر عند مغادرة شاشة (سيقطع مستمعي السجلات في الخلفية).
final appwriteLoggerProvider =
    ChangeNotifierProvider<AppwriteLogger>((ref) {
  final logger = AppwriteLogger();
  // تنظيف المستمعين عند إتلاف المزود (يحدث فقط عند إغلاق التطبيق)
  ref.onDispose(logger.dispose);
  return logger;
});

/// مزود معالج الأخطاء
final appwriteErrorHandlerProvider = Provider.autoDispose<AppwriteErrorHandler>((ref) {
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
    state = state.copyWith(isChecking: true);

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
        errorMessage: failureMessage,
      );
    } catch (e) {
      state = ConnectionState(
        isConnected: false,
        errorMessage: 'خطأ في الاتصال: $e',
      );
    }
  }
}

// ============ Data Providers ============

/// مزود إحصائيات المزامنة
final syncStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final syncManager = ref.watch(appwriteSyncManagerProvider);
  return syncManager.getSyncStatistics();
});

final outboxCountProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(databaseProvider);
  final dao = OutboxDao(db);
  // ✅ فصل هندسي: نراقب فقط عناصر source='local' (تغييرات محلية)
  return dao.watchCount(sources: const ['local']);
});

/// مزود إحصائيات الذاكرة المؤقتة
final cacheStatsProvider = Provider.autoDispose<CacheStatistics>((ref) {
  final cacheManager = ref.watch(appwriteCacheManagerProvider);
  return cacheManager.getStatistics();
});

/// مزود إحصائيات السجلات
final logStatsProvider = Provider.autoDispose<Map<String, int>>((ref) {
  final logger = ref.watch(appwriteLoggerProvider);
  return logger.getStatistics();
});

/// مزود معلومات المشروع
final projectInfoProvider = Provider.autoDispose<Map<String, String>>((ref) {
  final service = ref.watch(appwriteServiceProvider);
  return service.getProjectInfo();
});

/// مزود قائمة الأجهزة المسجلة (أحدث جهازين فقط)
final devicesListProvider = FutureProvider((ref) async {
  final syncManager = ref.watch(appwriteSyncManagerProvider);
  return syncManager.getRegisteredDevices();
});

/// مزود السجلات
final logsProvider = Provider((ref) {
  final logger = ref.watch(appwriteLoggerProvider);
  return logger.getLogs();
});
