import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/appwrite_service.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/appwrite_cache_manager.dart';
import '../services/appwrite_logger.dart';
import '../services/appwrite_error_handler.dart';
import '../services/providers.dart';

// ============ Service Providers ============

/// مزود خدمة Appwrite
final appwriteServiceProvider = Provider<AppwriteService>((ref) {
  return AppwriteService();
});

/// مزود مدير المزامنة
final appwriteSyncManagerProvider = Provider<AppwriteSyncManager>((ref) {
  final service = ref.watch(appwriteServiceProvider);
  final database = ref.watch(databaseProvider);
  return AppwriteSyncManager(appwriteService: service, database: database);
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
final connectionStatusProvider = StateNotifierProvider<ConnectionStatusNotifier, ConnectionState>((ref) {
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

  ConnectionStatusNotifier(this.ref) : super(ConnectionState(isConnected: false));

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

/// مزود إحصائيات المزامنة
final syncStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final syncManager = ref.watch(appwriteSyncManagerProvider);
  return await syncManager.getSyncStatistics();
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

/// مزود قائمة الأجهزة المسجلة
final devicesListProvider = FutureProvider((ref) async {
  final syncManager = ref.watch(appwriteSyncManagerProvider);
  return await syncManager.getRegisteredDevices();
});

/// مزود السجلات
final logsProvider = Provider((ref) {
  final logger = ref.watch(appwriteLoggerProvider);
  return logger.getLogs();
});
