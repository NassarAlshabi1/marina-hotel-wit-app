import 'dart:async';

class SyncManager {
  final dynamic db;
  final dynamic driveService;

  static SyncManager? _instance;

  SyncManager({this.db, this.driveService});

  static SyncManager get instance {
    _instance ??= SyncManager();
    return _instance!;
  }

  static void configureSingleton(SyncManager manager) {
    _instance = manager;
  }

  Future<void> initSyncService({bool allowInteractiveSignIn = false}) async {}
  Future<void> startOutboxDebouncedSync({Duration? debounce}) async {}
  Future<void> stopOutboxDebouncedSync() async {}

  Stream<dynamic> onSyncStatus() => const Stream.empty();

  Future<void> setDevicePriority(int priority) async {}

  Future<void> consumePendingAndSync() async {}
  Future<void> syncAllTables({bool force = false}) async {}

  Future<void> restart() async {}
  Future<void> stop() async {}
}
