import 'package:marina_hotel_mobile/services/sync_core/adapters/sync_target_adapter.dart';
import 'package:marina_hotel_mobile/services/sync_core/events/sync_event.dart';

class FakeSyncAdapter extends SyncTargetAdapter {
  @override
  final SyncTargetType type;
  @override
  final String name;
  @override
  final String displayName;

  bool _enabled;
  bool _initialized = false;
  bool _available;

  final List<EnhancedSyncEvent> pushedEvents = [];
  int pullCount = 0;

  Future<SyncPushResult> Function(List<EnhancedSyncEvent> events)? onPush;
  Future<SyncPullResult> Function()? onPull;

  FakeSyncAdapter({
    required this.type,
    String? name,
    String? displayName,
    bool enabled = true,
    bool available = true,
    this.onPush,
    this.onPull,
  })  : name = name ?? type.name,
        displayName = displayName ?? type.name,
        _enabled = enabled,
        _available = available;

  @override
  bool get isAvailable => _available;

  @override
  bool get isEnabled => _enabled;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkConnection() async => true;

  @override
  Future<SyncTargetStatus> getStatus() async {
    return SyncTargetStatus(
      type: type,
      isAvailable: _available,
      isEnabled: _enabled,
      isConnected: true,
      pendingCount: 0,
    );
  }

  @override
  Future<SyncPushResult> push(List<EnhancedSyncEvent> events) async {
    if (onPush != null) {
      return onPush!(events);
    }
    pushedEvents.addAll(events);
    return SyncPushResult.success(
      affectedCount: events.length,
      syncedIds: events.map((e) => e.id).toList(),
    );
  }

  @override
  Future<SyncPullResult> pull({
    DateTime? since,
    List<String>? tables,
    int? limit,
  }) async {
    pullCount += 1;
    if (onPull != null) {
      return onPull!();
    }
    return const SyncPullResult.success();
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
  }

  @override
  Future<void> reset() async {
    pushedEvents.clear();
    pullCount = 0;
  }

  @override
  Future<void> dispose() async {}
}
