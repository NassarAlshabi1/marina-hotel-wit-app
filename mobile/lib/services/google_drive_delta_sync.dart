import 'google_drive_backup_service.dart';
import 'google_drive_auto_sync_engine.dart' show SyncResult;
import 'local_db.dart';

class GoogleDriveDeltaSync {
  static final instance = GoogleDriveDeltaSync();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initialize(
    GoogleDriveBackupService backupService,
    AppDatabase database,
  ) async {
    _initialized = true;
  }

  Future<List<GoogleDriveBackupFile>> listBackupFiles() async {
    return [];
  }

  Future<String?> downloadBackup(String fileId, String destinationPath) async {
    return null;
  }

  Future<bool> restoreFromBackup(String fileId, AppDatabase database) async {
    return false;
  }

  /// Push delta changes to Google Drive
  Future<SyncResult> pushDeltaChanges() async {
    return SyncResult(success: true, changesCount: 0);
  }
}
