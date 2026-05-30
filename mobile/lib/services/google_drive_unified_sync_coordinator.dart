import 'local_db.dart';
import 'google_drive_backup_service.dart';

class GoogleDriveLogger {
  Future<void> initialize({LogLevel minLevel = LogLevel.info}) async {}
  void info(String message, {String tag = 'GOOGLE_DRIVE'}) {}
  void debug(String message, {String tag = 'GOOGLE_DRIVE'}) {}
  void warning(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {}
  void error(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {}
}

class GoogleDriveUnifiedSyncCoordinator {
  static final instance = GoogleDriveUnifiedSyncCoordinator();
  
  GoogleDriveUnifiedSyncCoordinator();
  
  String get deviceId => 'disabled';
  bool get isInitialized => false;
  bool get isSyncing => false;
  List<dynamic> get syncResults => [];
  
  Future<void> initialize({
    required GoogleDriveBackupService backupService,
    required AppDatabase database,
    required GoogleDriveLogger logger,
  }) async {}
  
  Future<void> disposeInstance() async {}
  Future<void> onAppForeground() async {}
  Future<void> onAppBackground() async {}
  Future<void> setPushEnabled(bool enabled) async {}
}