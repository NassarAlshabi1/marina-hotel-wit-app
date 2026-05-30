import 'local_db.dart';
import 'google_drive_backup_service.dart';

class GoogleDriveDeltaSync {
  static final instance = GoogleDriveDeltaSync();

  bool get isInitialized => false;

  Future<List<GoogleDriveBackupFile>> listBackupFiles() async {
    return [];
  }

  Future<String?> downloadBackup(String fileId, String destinationPath) async {
    return null;
  }

  Future<bool> restoreFromBackup(String fileId, AppDatabase database) async {
    return false;
  }
}
