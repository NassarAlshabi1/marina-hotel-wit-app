import 'google_drive_backup_service.dart';
import 'google_drive_delta_sync.dart';
import 'local_db.dart';

class SmartSyncManager {
  static final SmartSyncManager instance = SmartSyncManager();
  
  Future<void> initialize(GoogleDriveBackupService backupService) async {}
  Future<void> onGoogleDriveSignInChanged(bool signedIn) async {}
}