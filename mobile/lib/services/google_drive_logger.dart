import 'package:flutter/foundation.dart';

import 'logging/log_models.dart';

class GoogleDriveLogger extends ChangeNotifier {
  final List<LogEntry> _logs = [];

  Future<void> initialize({LogLevel minLevel = LogLevel.info}) async {
    // Stub implementation
  }

  void info(String message, {String tag = 'GOOGLE_DRIVE'}) {
    _addLog(LogLevel.info, message, tag);
  }

  void debug(String message, {String tag = 'GOOGLE_DRIVE'}) {
    _addLog(LogLevel.debug, message, tag);
  }

  void warning(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {
    _addLog(LogLevel.warning, message, tag, error: error, stackTrace: stackTrace);
  }

  void error(String message, {String tag = 'GOOGLE_DRIVE', Object? error, StackTrace? stackTrace}) {
    _addLog(LogLevel.error, message, tag, error: error, stackTrace: stackTrace);
  }

  void _addLog(LogLevel level, String message, String tag, {Object? error, StackTrace? stackTrace}) {
    _logs.add(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    ));
    notifyListeners();
  }

  List<LogEntry> getLogs() => List.unmodifiable(_logs);

  Map<String, int> getStatistics() {
    final stats = <String, int>{};
    for (final level in LogLevel.values) {
      stats[level.name] = _logs.where((l) => l.level == level).length;
    }
    return stats;
  }
}
