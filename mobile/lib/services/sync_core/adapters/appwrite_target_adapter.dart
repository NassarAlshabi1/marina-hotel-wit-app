import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../appwrite_delta_sync.dart';
import '../../appwrite_service.dart';
import '../../appwrite_sync_manager.dart';
import '../../local_db.dart';
import '../events/sync_event.dart';
import 'sync_target_adapter.dart';

class AppwriteTargetAdapter extends SyncTargetAdapter {
  final AppDatabase _database;
  AppwriteService? _service;
  AppwriteSyncManager? _syncManager;
  AppwriteDeltaSync? _deltaSync;
  bool _initialized = false;
  bool _enabled = true;
  bool _useDelta = true;
  DateTime? _lastSyncAt;
  String? _lastError;

  AppwriteTargetAdapter({
    required AppDatabase database,
    AppwriteService? service,
    AppwriteSyncManager? syncManager,
  })  : _database = database,
        _service = service,
        _syncManager = syncManager;

  @override
  SyncTargetType get type => SyncTargetType.appwrite;

  @override
  String get name => 'appwrite';

  @override
  String get displayName => 'Appwrite Cloud';

  @override
  bool get isAvailable => _service != null;

  @override
  bool get isEnabled => _enabled;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _service ??= AppwriteService();
      await _service!.initialize();

      _syncManager ??= AppwriteSyncManager(
        appwriteService: _service!,
        database: _database,
      );
      await _syncManager!.initialize();

      _deltaSync = AppwriteDeltaSync.instance;
      await _deltaSync!.initialize(_service!, _database);

      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('appwrite_sync_enabled') ?? true;
      _useDelta = await AppwriteDeltaSync.instance.isEnabled();

      _initialized = true;
      debugPrint('AppwriteTargetAdapter: Initialized successfully');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('AppwriteTargetAdapter: Initialization failed: $e');
      rethrow;
    }
  }

  @override
  Future<bool> checkConnection() async {
    if (_service == null) return false;
    try {
      return await _service!.quickConnectionTest();
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  @override
  Future<SyncTargetStatus> getStatus() async {
    final isConnected = await checkConnection();
    final pendingCount = await _getPendingCount();

    return SyncTargetStatus(
      type: type,
      isAvailable: isAvailable,
      isEnabled: _enabled,
      isConnected: isConnected,
      lastSyncAt: _lastSyncAt,
      lastError: _lastError,
      pendingCount: pendingCount,
      metadata: {
        'useDelta': _useDelta,
      },
    );
  }

  @override
  Future<SyncPushResult> push(List<EnhancedSyncEvent> events) async {
    if (!_initialized || !_enabled) {
      return SyncPushResult.failure(
        error: 'Adapter not initialized or disabled',
        failedIds: events.map((e) => e.id).toList(),
      );
    }

    final stopwatch = Stopwatch()..start();
    final syncedIds = <String>[];
    final failedIds = <String>[];

    try {
      if (_useDelta && _deltaSync != null) {
        for (final event in events) {
          try {
            await _pushEventDelta(event);
            syncedIds.add(event.id);
          } catch (e) {
            failedIds.add(event.id);
            debugPrint('AppwriteTargetAdapter: Failed to push ${event.id}: $e');
          }
        }
      } else if (_syncManager != null) {
        final success = await _syncManager!.pushLocalChanges();
        if (success) {
          syncedIds.addAll(events.map((e) => e.id));
        } else {
          failedIds.addAll(events.map((e) => e.id));
        }
      }

      stopwatch.stop();
      _lastSyncAt = DateTime.now();

      return SyncPushResult.partial(
        syncedIds: syncedIds,
        failedIds: failedIds,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      _lastError = e.toString();
      return SyncPushResult.failure(
        error: e.toString(),
        duration: stopwatch.elapsed,
        failedIds: events.map((e) => e.id).toList(),
      );
    }
  }

  Future<void> _pushEventDelta(EnhancedSyncEvent event) async {
    if (_deltaSync == null) return;

    switch (event.operation) {
      case SyncOperation.create:
      case SyncOperation.update:
        await _deltaSync!.pushDeltaChanges();
        break;
      case SyncOperation.delete:
        await _deltaSync!.pushDeltaChanges();
        break;
      default:
        await _deltaSync!.pushDeltaChanges();
    }
  }

  @override
  Future<SyncPullResult> pull({
    DateTime? since,
    List<String>? tables,
    int? limit,
  }) async {
    if (!_initialized || !_enabled) {
      return SyncPullResult.failure(
        error: 'Adapter not initialized or disabled',
      );
    }

    final stopwatch = Stopwatch()..start();

    try {
      if (_useDelta && _deltaSync != null) {
        await _deltaSync!.pullDeltaChanges();
      } else if (_syncManager != null) {
        await _syncManager!.pullRemoteChanges();
      }

      stopwatch.stop();
      _lastSyncAt = DateTime.now();

      return SyncPullResult.success(
        duration: stopwatch.elapsed,
        lastSyncTimestamp: _lastSyncAt,
      );
    } catch (e) {
      stopwatch.stop();
      _lastError = e.toString();
      return SyncPullResult.failure(
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appwrite_sync_enabled', enabled);
  }

  @override
  Future<void> reset() async {
    _lastSyncAt = null;
    _lastError = null;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }

  Future<int> _getPendingCount() async {
    try {
      final outbox = await (_database.select(_database.outbox)).get();
      return outbox.length;
    } catch (e) {
      return 0;
    }
  }

  Future<void> setUseDelta(bool useDelta) async {
    _useDelta = useDelta;
    if (_deltaSync != null) {
      await _deltaSync!.setEnabled(useDelta);
    }
  }

  Future<bool> syncNow({bool push = true, bool pull = true}) async {
    if (!_initialized || !_enabled || _syncManager == null) return false;

    final result = await _syncManager!.sync(push: push, pull: pull);
    _lastSyncAt = DateTime.now();
    return result.isSuccess;
  }
}
