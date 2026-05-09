/// Sync Providers
/// Providers Riverpod للمزامنة

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/sync_models.dart';
import '../vector_clock.dart';
import '../delta_sync_engine.dart';
import '../processors/outbox_processor.dart';
import '../orchestrator/sync_orchestrator.dart';
import '../strategies/conflict_strategies.dart';
import '../services/background_sync_service.dart';
import '../services/realtime_sync_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Configuration Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider لإعدادات المزامنة
final syncConfigurationProvider = Provider<SyncConfiguration>((ref) {
  return const SyncConfiguration(
    enabled: true,
    defaultDirection: SyncDirection.bidirectional,
    batchSize: 50,
    autoSyncInterval: Duration(minutes: 15),
    backgroundSyncEnabled: true,
    realtimeSyncEnabled: true,
    maxRetries: 3,
    conflictStrategy: ConflictStrategy.newerWins,
    requireWifi: false,
    requireCharging: false,
  );
});

/// Provider قابل للتعديل لإعدادات المزامنة
final syncConfigurationNotifierProvider =
    StateNotifierProvider<SyncConfigurationNotifier, SyncConfiguration>((ref) {
  return SyncConfigurationNotifier(ref.watch(syncConfigurationProvider));
});

class SyncConfigurationNotifier extends StateNotifier<SyncConfiguration> {
  SyncConfigurationNotifier(super.initialConfig);

  void updateConfig(SyncConfiguration config) => state = config;

  void setEnabled(bool enabled) => state = state.copyWith(enabled: enabled);
  void setAutoSyncInterval(Duration interval) =>
      state = state.copyWith(autoSyncInterval: interval);
  void setConflictStrategy(ConflictStrategy strategy) =>
      state = state.copyWith(conflictStrategy: strategy);
  void setRequireWifi(bool require) => state = state.copyWith(requireWifi: require);
  void setRequireCharging(bool require) =>
      state = state.copyWith(requireCharging: require);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Core Services Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider لمعرف الجهاز
final deviceIdProvider = Provider<String>((ref) {
  // يمكن استبدال هذا بـ SharedPreferences أو FlutterSecureStorage
  // للحصول على معرف ثابت للجهاز
  return const Uuid().v4();
});

/// Provider لمدير Vector Clock
final vectorClockManagerProvider = Provider<VectorClockManager>((ref) {
  final deviceId = ref.watch(deviceIdProvider);
  return VectorClockManager(deviceId: deviceId);
});

/// Provider لمحلل التعارضات
final conflictResolverProvider = Provider<ConflictResolver>((ref) {
  final config = ref.watch(syncConfigurationProvider);
  return ConflictResolver(
    defaultStrategy: config.conflictStrategy,
    smartMergeResolver: DefaultSmartMergeResolver(),
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// Data Source Providers (Abstract - Implementation Required)
// ═══════════════════════════════════════════════════════════════════════════════

// ⚠️ DEPRECATED: placeholder provider — لا تستخدم مباشرة، يجب تخصيصه قبل تفعيل delta sync
// يقوم بإرجاع null بدلاً من رمي استثناء لتجنب تعطل التطبيق عند المشاهدة بالخطأ
@Deprecated('يجب تخصيص outboxDataSourceProvider قبل تفعيل delta sync')
final outboxDataSourceProvider = Provider<OutboxDataSource?>((ref) {
  // Placeholder provider لعمارة delta sync المستقبلية — لم يتم التخصيص بعد
  return null;
});

// ⚠️ DEPRECATED: placeholder provider — لا تستخدم مباشرة، يجب تخصيصه قبل تفعيل delta sync
// يقوم بإرجاع null بدلاً من رمي استثناء لتجنب تعطل التطبيق عند المشاهدة بالخطأ
@Deprecated('يجب تخصيص inboxDataSourceProvider قبل تفعيل delta sync')
final inboxDataSourceProvider = Provider<InboxDataSource?>((ref) {
  // Placeholder provider لعمارة delta sync المستقبلية — لم يتم التخصيص بعد
  return null;
});

// ⚠️ DEPRECATED: placeholder provider — لا تستخدم مباشرة، يجب تخصيصه قبل تفعيل delta sync
// يقوم بإرجاع null بدلاً من رمي استثناء لتجنب تعطل التطبيق عند المشاهدة بالخطأ
@Deprecated('يجب تخصيص remoteDataSourceProvider قبل تفعيل delta sync')
final remoteDataSourceProvider = Provider<RemoteDataSource?>((ref) {
  // Placeholder provider لعمارة delta sync المستقبلية — لم يتم التخصيص بعد
  return null;
});

// ⚠️ DEPRECATED: placeholder provider — لا تستخدم مباشرة، يجب تخصيصه قبل تفعيل delta sync
// يقوم بإرجاع null بدلاً من رمي استثناء لتجنب تعطل التطبيق عند المشاهدة بالخطأ
@Deprecated('يجب تخصيص outboxStorageProvider قبل تفعيل delta sync')
final outboxStorageProvider = Provider<OutboxStorage?>((ref) {
  // Placeholder provider لعمارة delta sync المستقبلية — لم يتم التخصيص بعد
  return null;
});

// ═══════════════════════════════════════════════════════════════════════════════
// Sync Engine Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider لمحرك المزامنة
final deltaSyncEngineProvider = Provider<DeltaSyncEngine>((ref) {
  return DeltaSyncEngine(
    config: ref.watch(syncConfigurationProvider),
    clockManager: ref.watch(vectorClockManagerProvider),
    // ignore: deprecated_member_use — placeholder providers يتم تخصيصها لاحقاً
    outbox: ref.watch(outboxDataSourceProvider)!, // TODO: تخصيص before enabling delta sync
    inbox: ref.watch(inboxDataSourceProvider)!, // TODO: تخصيص before enabling delta sync
    remote: ref.watch(remoteDataSourceProvider)!, // TODO: تخصيص before enabling delta sync
    conflictResolver: ref.watch(conflictResolverProvider),
  );
});

/// Provider لمعالج Outbox
final outboxProcessorProvider = Provider<OutboxProcessor>((ref) {
  return OutboxProcessor(
    // ignore: deprecated_member_use — placeholder provider يتم تخصيصه لاحقاً
    storage: ref.watch(outboxStorageProvider)!, // TODO: تخصيص before enabling delta sync
    clockManager: ref.watch(vectorClockManagerProvider),
    config: ref.watch(syncConfigurationProvider),
  );
});

/// Provider لمنسق المزامنة
final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) {
  return SyncOrchestrator(
    syncEngine: ref.watch(deltaSyncEngineProvider),
    outbox: ref.watch(outboxProcessorProvider),
    clockManager: ref.watch(vectorClockManagerProvider),
    config: ref.watch(syncConfigurationProvider),
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// State Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider لحالة المزامنة
final syncStateProvider = StreamProvider<SyncState>((ref) {
  final orchestrator = ref.watch(syncOrchestratorProvider);

  // تهيئة عند أول استماع
  Future(() async {
    await orchestrator.initialize();
    orchestrator.startAutoSync();
  });

  // إيقاف عند التخلص
  ref.onDispose(() {
    orchestrator.stopAutoSync();
  });

  return orchestrator.stateStream;
});

/// Provider للحالة الحالية (AsyncValue)
final syncStateAsyncProvider = Provider<AsyncValue<SyncState>>((ref) {
  return ref.watch(syncStateProvider);
});

/// Provider لتقدم المزامنة
final syncProgressProvider = StreamProvider<SyncProgress>((ref) {
  return ref.watch(syncOrchestratorProvider).progressStream;
});

/// Provider للتعارضات
final syncConflictsProvider = StreamProvider<List<SyncConflict>>((ref) {
  final stream = ref.watch(syncOrchestratorProvider).conflictStream;

  // تحويل Stream<SyncConflict> إلى Stream<List<SyncConflict>>
  final conflicts = <SyncConflict>[];

  return stream.map((conflict) {
    conflicts.add(conflict);
    return List.unmodifiable(conflicts);
  });
});

/// Provider لعدد التغييرات المعلقة
final pendingChangesCountProvider = StreamProvider<int>((ref) {
  return ref.watch(outboxProcessorProvider).pendingCountStream;
});

/// Provider لحالة Outbox
final outboxStatusProvider = StreamProvider<OutboxStatus>((ref) {
  return ref.watch(outboxProcessorProvider).statusStream;
});

// ═══════════════════════════════════════════════════════════════════════════════
// Background & Realtime Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider لإعدادات Realtime
final realtimeConfigProvider = Provider<RealtimeConfig>((ref) {
  return const RealtimeConfig(
    wsUrl: 'wss://your-server.com/ws/sync',
    tablesToWatch: [
      'bookings',
      'rooms',
      'guests',
      'payments',
      'expenses',
      'inventory',
    ],
    pingInterval: Duration(seconds: 30),
    enabled: true,
  );
});

/// Provider لخدمة Realtime Sync
final realtimeSyncServiceProvider = Provider<RealtimeSyncService>((ref) {
  return RealtimeSyncService(
    orchestrator: ref.watch(syncOrchestratorProvider),
    config: ref.watch(realtimeConfigProvider),
  );
});

/// Provider لخدمة Background Sync
final backgroundSyncServiceProvider = Provider<BackgroundSyncService>((ref) {
  return BackgroundSyncService();
});

/// Provider لتهيئة Background Sync
final backgroundSyncInitProvider = Provider<Future<void>>((ref) async {
  final service = ref.watch(backgroundSyncServiceProvider);
  final orchestrator = ref.watch(syncOrchestratorProvider);
  final config = ref.watch(syncConfigurationProvider);

  await service.initialize(
    orchestrator: orchestrator,
    config: config,
  );

  await service.schedulePeriodicSync();
  await service.scheduleCleanup();
});

// ═══════════════════════════════════════════════════════════════════════════════
// Action Providers (For UI interaction)
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider لتنفيذ مزامنة يدوية
final manualSyncProvider = FutureProvider.family<DeltaSyncResult, SyncDirection?>(
  (ref, direction) async {
    final orchestrator = ref.read(syncOrchestratorProvider);
    return await orchestrator.performFullSync(
      direction: direction ?? SyncDirection.bidirectional,
    );
  },
);

/// Provider لإضافة تغيير للمزامنة
final queueChangeProvider = Provider<Future<String> Function({
  required String table,
  required String uuid,
  required SyncOperation operation,
  required Map<String, dynamic> data,
})>((ref) {
  return ({
    required String table,
    required String uuid,
    required SyncOperation operation,
    required Map<String, dynamic> data,
  }) async {
    final orchestrator = ref.read(syncOrchestratorProvider);
    return await orchestrator.queueLocalChange(
      table: table,
      uuid: uuid,
      operation: operation,
      data: data,
    );
  };
});

/// Provider للتحكم في Realtime Sync
final realtimeSyncControlProvider = Provider<RealtimeSyncControl>((ref) {
  final service = ref.watch(realtimeSyncServiceProvider);

  return RealtimeSyncControl(
    start: () => service.start(),
    stop: () => service.stop(),
    reconnect: () => service.reconnect(),
  );
});

class RealtimeSyncControl {
  final Future<void> Function() start;
  final Future<void> Function() stop;
  final Future<void> Function() reconnect;

  RealtimeSyncControl({
    required this.start,
    required this.stop,
    required this.reconnect,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Stats & Info Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider لإحصائيات المزامنة
final syncStatsProvider = FutureProvider<SyncStats>((ref) async {
  // يمكن تنفيذ هذا لجمع إحصائيات من المصادر المختلفة
  return SyncStats(
    lastSyncAt: DateTime.now(),
    totalSynced: 0,
    totalConflicts: 0,
    totalErrors: 0,
    averageSyncTime: Duration.zero,
  );
});

/// Provider لحالة الاتصال بالمزامنة
final syncConnectionProvider = Provider<SyncConnectionState>((ref) {
  final state = ref.watch(syncStateAsyncProvider);

  return state.when(
    data: (asyncState) {
      if (asyncState.isSyncing) return SyncConnectionState.syncing;
      if (asyncState.hasError) return SyncConnectionState.error;
      return SyncConnectionState.connected;
    },
    loading: () => SyncConnectionState.connecting,
    error: (_, __) => SyncConnectionState.error,
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// Helper Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider للتحقق مما إذا كانت المزامنة ممكنة
final canSyncProvider = Provider<bool>((ref) {
  final config = ref.watch(syncConfigurationProvider);
  final state = ref.watch(syncStateAsyncProvider);

  if (!config.enabled) return false;
  if (state.isLoading) return false;
  if (state.valueOrNull?.isSyncing ?? false) return false;

  return true;
});

/// Provider لعدد التعارضات النشطة
final activeConflictsCountProvider = Provider<int>((ref) {
  final conflicts = ref.watch(syncConflictsProvider);
  return conflicts.valueOrNull?.length ?? 0;
});

/// Provider للتحقق من وجود تغييرات معلقة
final hasPendingChangesProvider = Provider<bool>((ref) {
  final count = ref.watch(pendingChangesCountProvider);
  return (count.valueOrNull ?? 0) > 0;
});
