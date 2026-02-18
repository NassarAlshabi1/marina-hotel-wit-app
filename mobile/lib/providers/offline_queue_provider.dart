import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline_queue/offline_queue_manager.dart';
import '../services/offline_queue/offline_queue_processor.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';
import 'core_providers.dart';

/// Provider لمدير قائمة الانتظار (Singleton)
final offlineQueueManagerProvider = Provider<OfflineQueueManager>((ref) {
  return OfflineQueueManager.instance;
});

/// Provider لمعالج قائمة الانتظار
final offlineQueueProcessorProvider = Provider<OfflineQueueProcessor>((ref) {
  return OfflineQueueProcessor.instance;
});

/// Provider لحالة تهيئة قائمة الانتظار
final offlineQueueInitProvider = FutureProvider<void>((ref) async {
  final db = ref.read(dbProvider);
  final syncService = ref.read(syncProvider);
  final manager = ref.read(offlineQueueManagerProvider);
  final processor = ref.read(offlineQueueProcessorProvider);

  await manager.initialize(database: db);
  await processor.initialize(
    database: db,
    syncService: syncService,
  );

  // تسجيل المعالجات مع المدير
  for (final entry in processor.allHandlers.entries) {
    manager.registerHandler(entry.key, entry.value);
  }
});

/// Provider لبث الإحصائيات
final offlineQueueStatsProvider = StreamProvider<OfflineQueueStats>((ref) {
  final manager = ref.watch(offlineQueueManagerProvider);
  return manager.statsStream;
});

/// Provider لبث قائمة العناصر
final offlineQueueItemsProvider = StreamProvider<List<OfflineQueueItem>>((ref) {
  final manager = ref.watch(offlineQueueManagerProvider);
  return manager.queueStream;
});

/// Provider لحالة المعالجة
final offlineQueueProcessingProvider = StreamProvider<bool>((ref) {
  final manager = ref.watch(offlineQueueManagerProvider);
  return manager.processingStream;
});

/// Provider لعدد العناصر المعلقة (للاستخدام السريع في الواجهة)
final offlineQueuePendingCountProvider = Provider<AsyncValue<int>>((ref) {
  final statsAsync = ref.watch(offlineQueueStatsProvider);
  return statsAsync.when(
    data: (stats) => AsyncValue.data(stats.pendingCount),
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

/// Provider لحالة الاتصال مع العمليات المعلقة
final offlineQueueStatusProvider = Provider<AsyncValue<OfflineQueueStatus>>((ref) {
  final statsAsync = ref.watch(offlineQueueStatsProvider);
  return statsAsync.when(
    data: (stats) => AsyncValue.data(OfflineQueueStatus.fromStats(stats)),
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

/// حالة موجزة لقائمة الانتظار للواجهة
class OfflineQueueStatus {
  final int pendingCount;
  final int failedCount;
  final bool isOnline;
  final bool isProcessing;
  final bool hasItems;

  OfflineQueueStatus({
    required this.pendingCount,
    required this.failedCount,
    required this.isOnline,
    required this.isProcessing,
    required this.hasItems,
  });

  factory OfflineQueueStatus.fromStats(OfflineQueueStats stats) {
    return OfflineQueueStatus(
      pendingCount: stats.pendingCount,
      failedCount: stats.failedCount,
      isOnline: stats.isOnline,
      isProcessing: stats.processingCount > 0,
      hasItems: stats.pendingCount > 0 || stats.failedCount > 0,
    );
  }

  bool get needsAttention => failedCount > 0 || (pendingCount > 0 && !isOnline);
  bool get canSync => isOnline && pendingCount > 0 && !isProcessing;

  String get displayText {
    if (isProcessing) {
      return 'جاري المزامنة...';
    }
    if (!isOnline && pendingCount > 0) {
      return '$pendingCount عملية معلقة (غير متصل)';
    }
    if (failedCount > 0) {
      return '$failedCount فشل | $pendingCount معلقة';
    }
    if (pendingCount > 0) {
      return '$pendingCount عملية للمزامنة';
    }
    return 'تمت المزامنة';
  }
}
