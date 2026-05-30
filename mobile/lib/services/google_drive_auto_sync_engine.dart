import 'dart:async';
import 'local_db.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_logger.dart';
import 'logging/log_models.dart';

class EngineState {
  bool isRunning = false;
  bool hasNetworkConnection = true;
  bool isSignedIn = false;
  int pendingChangesCount = 0;
  DateTime? lastSuccessfulSync;
  int failedAttempts = 0;
  DateTime? nextRetryAt;
  String? lastError;
}

// Alias for compatibility
typedef AutoSyncEngineState = EngineState;

class SyncResult {
  final bool success;
  final String? error;
  final int? changesCount;
  final int? pushedChanges;
  final int? pulledChanges;
  final String? message;
  final DateTime timestamp;
  SyncResult({
    required this.success,
    this.error,
    this.changesCount,
    this.pushedChanges,
    this.pulledChanges,
    this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AutoSyncEngine {
  static final instance = AutoSyncEngine();

  final _stateController = StreamController<EngineState>.broadcast();
  Stream<EngineState> get stateStream => _stateController.stream;
  EngineState get state => _stateController.hasListener ? EngineState() : EngineState();
  AutoSyncEngineState get currentState => EngineState();
  bool get isRunning => false;
  bool get isSignedIn => false;

  Future<void> initialize({
    required GoogleDriveBackupService backupService,
    required AppDatabase database,
    required GoogleDriveLogger logger,
  }) async {}

  Future<void> start() async {}
  Future<void> stop() async {}
  Future<void> restart() async {}

  Future<SyncResult> forceSyncNow() async {
    return SyncResult(success: false, error: 'Google Drive sync disabled');
  }

  Future<void> setDebounceSeconds(int seconds) async {}
  Future<void> setPullInterval(int minutes) async {}
  Future<void> setRetryEnabled(bool enabled) async {}
  Future<void> setConflictStrategy(dynamic strategy) async {}
  Future<void> onSignInChanged(bool signedIn) async {}
}
