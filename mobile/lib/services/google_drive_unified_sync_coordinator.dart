import 'dart:async';

import 'local_db.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_auto_sync_engine.dart' show SyncResult;
import 'logging/log_models.dart';

/// وضع المزامنة
enum SyncMode {
  full,
  deltaOnly,
  pushOnly,
  pullOnly,
}

/// محفز المزامنة
enum SyncTrigger {
  manual,
  localChange,
  periodic,
  appForeground,
  connectivityRestored,
}

class GoogleDriveLogger {
  Future<void> initialize({LogLevel minLevel = LogLevel.info}) async {}
  void info(String message, {String tag = 'GOOGLE_DRIVE'}) {}
  void debug(String message, {String tag = 'GOOGLE_DRIVE'}) {}
  void warning(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {}
  void error(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {}
}

class GoogleDriveUnifiedSyncCoordinator {
  static final instance = GoogleDriveUnifiedSyncCoordinator();

  final _syncResultController = StreamController<SyncResult>.broadcast();

  GoogleDriveUnifiedSyncCoordinator();

  String get deviceId => 'disabled';
  bool get isInitialized => false;
  bool get isSyncing => false;

  /// Stream of sync results
  Stream<SyncResult> get syncResults => _syncResultController.stream;

  /// Legacy getter for backward compatibility (returns empty list)
  List<dynamic> get syncResultsList => [];

  Future<void> initialize({
    required GoogleDriveBackupService backupService,
    required AppDatabase database,
    required GoogleDriveLogger logger,
  }) async {}

  Future<void> disposeInstance() async {
    await _syncResultController.close();
  }

  Future<void> onAppForeground() async {}
  Future<void> onAppBackground() async {}
  Future<void> setPushEnabled(bool enabled) async {}

  Future<void> onSignInChanged(bool isSignedIn) async {}

  Future<void> setDebounceSeconds(int seconds) async {}
  Future<void> setPullInterval(int minutes) async {}

  /// Perform sync with trigger and mode — DISABLED (use backup/restore instead)
  Future<SyncResult> performSync({
    SyncTrigger trigger = SyncTrigger.manual,
    SyncMode mode = SyncMode.full,
  }) async {
    return SyncResult(success: false, error: 'Google Drive sync is disabled — use backup/restore instead');
  }
}
