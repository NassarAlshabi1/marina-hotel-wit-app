import 'local_db.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_auto_sync_engine.dart';
import 'google_drive_logger.dart';

enum SyncTrigger { manual, localChange, periodic, scheduled }

enum SyncMode { full, deltaOnly }

class GoogleDriveUnifiedSyncCoordinator {
  static final instance = GoogleDriveUnifiedSyncCoordinator();

  GoogleDriveUnifiedSyncCoordinator();

  String get deviceId => 'disabled';
  bool get isInitialized => false;
  bool get isSyncing => false;
  Stream<SyncResult> get syncResults => const Stream.empty();

  Future<void> initialize({
    required GoogleDriveBackupService backupService,
    required AppDatabase database,
    required GoogleDriveLogger logger,
  }) async {}

  Future<SyncResult> performSync({
    SyncTrigger trigger = SyncTrigger.manual,
    SyncMode mode = SyncMode.full,
  }) async {
    return SyncResult(success: false, error: 'Google Drive sync disabled');
  }

  Future<void> disposeInstance() async {}
  Future<void> onAppForeground() async {}
  Future<void> onAppBackground() async {}
  Future<void> setPushEnabled(bool enabled) async {}
}
