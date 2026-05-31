import 'dart:async';
import 'local_db.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_logger.dart';
import 'google_drive_conflict_resolver.dart' show ConflictResolutionStrategy;

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
  final DateTime timestamp;
  final String? message;
  final int? pushedChanges;
  final int? pulledChanges;

  SyncResult({
    required this.success,
    this.error,
    this.changesCount,
    this.message,
    this.pushedChanges,
    this.pulledChanges,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AutoSyncEngine {
  static final instance = AutoSyncEngine();

  final _stateController = StreamController<EngineState>.broadcast();
  Stream<EngineState> get stateStream => _stateController.stream;
  EngineState get state => EngineState();
  EngineState get currentState => EngineState();
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

  Future<void> setDebounceSeconds(int seconds) async {}
  Future<void> setPullInterval(int minutes) async {}
  Future<void> setRetryEnabled(bool enabled) async {}
  Future<void> setConflictStrategy(ConflictResolutionStrategy strategy) async {}
  Future<void> onSignInChanged(bool signedIn) async {}

  Future<SyncResult> forceSyncNow() async {
    return SyncResult(success: false, error: 'Google Drive sync is disabled — use backup/restore instead');
  }

  Future<void> resetFailedAttempts() async {}

  Future<Map<String, dynamic>> getEngineStatus() async => {
    'is_running': false,
    'is_signed_in': false,
    'pending_changes': 0,
    'failed_attempts': 0,
    'last_sync': null,
    'coordinator': {
      'pull_interval_minutes': 2,
      'debounce_seconds': 5,
    },
  };

  /// Dispose resources — called during app shutdown
  Future<void> disposeInstance() async {
    try {
      await _stateController.close();
    } catch (_) {
      // Already closed
    }
  }
}
