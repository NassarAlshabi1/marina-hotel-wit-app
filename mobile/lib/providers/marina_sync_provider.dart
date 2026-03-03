import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sync/marina_sync_manager.dart';
import '../services/local_db.dart';
import 'core_providers.dart';

/// ==================== Marina Sync Provider ====================
///
/// الـ Provider الموحد للمزامنة - يوفر API نظيف للتعامل مع MarinaSyncManager
/// يستبدل: smartSyncManagerProvider, syncProvider, appwriteSyncProvider

/// Provider أساسي للـ MarinaSyncManager
final marinaSyncManagerProvider = Provider<MarinaSyncManager>((ref) {
  return MarinaSyncManager.instance;
});

/// Provider لحالة المزامنة الحالية (Stream)
final marinaSyncStatusStreamProvider = StreamProvider<SyncStatus>((ref) {
  final manager = ref.watch(marinaSyncManagerProvider);
  return manager.watchStatus();
});

/// Provider لتقدم المزامنة
final marinaSyncProgressProvider = StreamProvider<SyncProgress>((ref) {
  final manager = ref.watch(marinaSyncManagerProvider);
  return manager.watchProgress();
});

/// Provider للتضاربات
final marinaSyncConflictsProvider = StreamProvider<SyncConflict>((ref) {
  final manager = ref.watch(marinaSyncManagerProvider);
  return manager.watchConflicts();
});

/// Provider لحالة المزامنة الحالية (Async)
final marinaSyncStateProvider = StateProvider<SyncState>((ref) {
  final manager = ref.watch(marinaSyncManagerProvider);
  return SyncState(
    status: manager.currentStatus,
    isSyncing: manager.isSyncing,
  );
});

/// Provider لتهيئة المزامنة
final marinaSyncInitProvider = FutureProvider<void>((ref) async {
  final manager = ref.watch(marinaSyncManagerProvider);
  final db = ref.watch(dbProvider);

  await manager.initialize(
    database: db,
    enableAutoSync: true,
  );
});

/// Provider لتنفيذ مزامنة كاملة
final marinaSyncNowProvider = FutureProvider.family<SyncResult, SyncParams>((
  ref,
  params,
) async {
  final manager = ref.watch(marinaSyncManagerProvider);
  return await manager.sync(
    force: params.force,
    reason: params.reason,
  );
});

/// Provider لرفع التغييرات
final marinaPushProvider = FutureProvider<SyncResult>((ref) async {
  final manager = ref.watch(marinaSyncManagerProvider);
  return await manager.push(reason: 'manual');
});

/// Provider لسحب التغييرات
final marinaPullProvider = FutureProvider<SyncResult>((ref) async {
  final manager = ref.watch(marinaSyncManagerProvider);
  return await manager.pull(reason: 'manual');
});

/// Provider لإنشاء Snapshot
final marinaSnapshotProvider = FutureProvider.family<SyncResult, bool>((
  ref,
  force,
) async {
  final manager = ref.watch(marinaSyncManagerProvider);
  return await manager.snapshot(force: force);
});

/// Provider لتهيئة المزامنة التلقائية
final marinaAutoSyncProvider = Provider<AutoSyncConfig>((ref) {
  final manager = ref.watch(marinaSyncManagerProvider);
  final config = manager.config;

  return AutoSyncConfig(
    enabled: config.autoSyncEnabled,
    intervalMinutes: config.autoSyncIntervalMinutes,
    syncOnConnect: config.autoSyncOnConnect,
  );
});

/// Provider لتفعيل/تعطيل المزامنة التلقائية
final marinaSetAutoSyncProvider = Provider<Future<void> Function(bool)>((ref) {
  final manager = ref.watch(marinaSyncManagerProvider);
  return (bool enabled) async {
    await manager.setAutoSyncEnabled(enabled);
  };
});

/// Provider لحل التضارب
final marinaResolveConflictProvider = Provider<
    Future<void> Function(SyncConflict, ConflictResolution)>((ref) {
  final manager = ref.watch(marinaSyncManagerProvider);
  return (SyncConflict conflict, ConflictResolution resolution) async {
    await manager.resolveConflict(conflict, resolution: resolution);
  };
});

/// Provider لرفض التضارب
final marinaDismissConflictProvider = Provider<Future<void> Function(SyncConflict)>((
  ref,
) {
  final manager = ref.watch(marinaSyncManagerProvider);
  return (SyncConflict conflict) async {
    await manager.dismissConflict(conflict);
  };
});

/// ==================== Data Classes ====================

class SyncState {
  final SyncStatus status;
  final bool isSyncing;

  const SyncState({
    required this.status,
    required this.isSyncing,
  });

  bool get isIdle => status == SyncStatus.idle;
  bool get isSuccess => status == SyncStatus.success;
  bool get isFailed => status == SyncStatus.failed;
  bool get isPartial => status == SyncStatus.partial;

  String get statusText {
    switch (status) {
      case SyncStatus.idle:
        return 'جاهز';
      case SyncStatus.syncing:
        return 'جاري المزامنة...';
      case SyncStatus.success:
        return 'تمت المزامنة';
      case SyncStatus.failed:
        return 'فشلت المزامنة';
      case SyncStatus.partial:
        return 'مزامنة جزئية';
    }
  }
}

class SyncParams {
  final bool force;
  final String reason;

  const SyncParams({
    this.force = false,
    this.reason = 'manual',
  });
}

class AutoSyncConfig {
  final bool enabled;
  final int intervalMinutes;
  final bool syncOnConnect;

  const AutoSyncConfig({
    required this.enabled,
    required this.intervalMinutes,
    required this.syncOnConnect,
  });
}

/// ==================== Helper Widgets (Optional) ====================
///
/// مثال على استخدام الـ Provider في Widget:
///
/// ```dart
/// class SyncButton extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     final syncState = ref.watch(marinaSyncStateProvider);
///
///     return ElevatedButton(
///       onPressed: syncState.isSyncing
///         ? null
///         : () async {
///             final result = await ref.read(marinaSyncNowProvider(
///               const SyncParams(force: false, reason: 'manual'),
///             ).future);
///
///             if (result.isSuccess) {
///               ScaffoldMessenger.of(context).showSnackBar(
///                 SnackBar(content: Text('تمت المزامنة بنجاح')),
///               );
///             }
///           },
///       child: Text(syncState.statusText),
///     );
///   }
/// }
/// ```
