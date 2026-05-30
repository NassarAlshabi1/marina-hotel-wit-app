import 'local_db.dart';

enum ConflictResolutionStrategy { newerWins, olderWins, localWins, remoteWins }

class GoogleDriveConflictResolver {
  static final instance = GoogleDriveConflictResolver();
  
  void initialize(GoogleDriveLogger logger) {}
  
  Future<void> setStrategy(ConflictResolutionStrategy strategy) async {}
  
  Future<void> setConflictThreshold(int threshold) async {}
}

class GoogleDriveLogger {
  Future<void> initialize({LogLevel minLevel = LogLevel.info}) async {}
  void info(String message, {String tag = 'GOOGLE_DRIVE'}) {}
  void debug(String message, {String tag = 'GOOGLE_DRIVE'}) {}
  void warning(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {}
  void error(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {}
}