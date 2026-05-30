import 'logging/log_models.dart';

class GoogleDriveLogger {
  Future<void> initialize({LogLevel minLevel = LogLevel.info}) async {}
  void dispose() {}
  void info(String message, {String tag = 'GOOGLE_DRIVE'}) {}
  void debug(String message, {String tag = 'GOOGLE_DRIVE'}) {}
  void warning(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {}
  void error(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {}
}
