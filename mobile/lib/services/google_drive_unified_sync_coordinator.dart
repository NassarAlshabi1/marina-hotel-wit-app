import 'local_db.dart';

class GoogleDriveUnifiedSyncCoordinator {
  static final instance = GoogleDriveUnifiedSyncCoordinator();
  
  Future<void> initialize({
    required GoogleDriveBackupService backupService,
    required AppDatabase database,
    required GoogleDriveLogger logger,
  }) async {}
}

class GoogleDriveLogger {
  Future<void> initialize({LogLevel minLevel = LogLevel.info}) async {}
  void info(String message, {String tag = 'GOOGLE_DRIVE'}) {}
  void debug(String message, {String tag = 'GOOGLE_DRIVE'}) {}
  void warning(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {}
  void error(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {}
}