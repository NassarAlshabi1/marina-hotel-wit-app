import 'dart:async';

import '../google_drive_unified_sync_coordinator.dart';

enum SyncBackendKind { googleDrive, restApi, appwrite }

abstract class SyncBackend {
  SyncBackendKind get kind;
  Stream<SyncResult> get results;
  bool get isReady;

  Future<SyncResult> performSync({required SyncTrigger trigger, SyncMode mode});
  Future<void> notifyLocalChange({String? table, String? operation, int count});
  Future<void> onSignInChanged(bool isSignedIn);
  Future<void> onAppForeground();
  Future<Map<String, dynamic>> status();
}

class GoogleDriveSyncBackend implements SyncBackend {
  GoogleDriveSyncBackend(this._coordinator);

  final GoogleDriveUnifiedSyncCoordinator _coordinator;

  @override
  SyncBackendKind get kind => SyncBackendKind.googleDrive;

  @override
  Stream<SyncResult> get results => _coordinator.syncResults;

  @override
  bool get isReady => _coordinator.isInitialized;

  @override
  Future<SyncResult> performSync({required SyncTrigger trigger, SyncMode mode = SyncMode.smart}) {
    return _coordinator.performSync(trigger: trigger, mode: mode);
  }

  @override
  Future<void> notifyLocalChange({String? table, String? operation, int count = 1}) async {
    _coordinator.notifyLocalChange(table: table, operation: operation, count: count);
  }

  @override
  Future<void> onSignInChanged(bool isSignedIn) {
    return _coordinator.onSignInChanged(isSignedIn);
  }

  @override
  Future<void> onAppForeground() {
    return _coordinator.onAppForeground();
  }

  @override
  Future<Map<String, dynamic>> status() {
    return _coordinator.getStatus();
  }
}

class SyncBackendManager {
  SyncBackendManager._();

  static final instance = SyncBackendManager._();

  final Map<SyncBackendKind, SyncBackend> _backends = {};
  SyncBackendKind? _activeKind;

  void register(SyncBackend backend, {bool activate = false}) {
    _backends[backend.kind] = backend;
    if (activate || _activeKind == null) {
      _activeKind = backend.kind;
    }
  }

  bool hasBackend(SyncBackendKind kind) => _backends.containsKey(kind);

  SyncBackend get active {
    final kind = _activeKind;
    if (kind == null || !_backends.containsKey(kind)) {
      throw StateError('No active sync backend');
    }
    return _backends[kind]!;
  }

  void activate(SyncBackendKind kind) {
    if (!_backends.containsKey(kind)) {
      throw StateError('Sync backend $kind is not registered');
    }
    _activeKind = kind;
  }

  void reset() {
    _backends.clear();
    _activeKind = null;
  }
}
