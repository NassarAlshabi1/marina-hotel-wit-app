import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

enum TransactionType {
  create,
  update,
  delete,
  sync,
  payment,
  checkout,
  login,
  logout,
  backup,
  restore,
}

class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  final List<LogEntry> _logs = [];
  static const int _maxLogs = 500;

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void log(String message, {LogLevel level = LogLevel.info, String? tag}) {
    final entry = LogEntry(
      message: message,
      level: level,
      tag: tag,
      timestamp: DateTime.now(),
    );
    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
    if (kDebugMode) {
      developer.log(
        message,
        name: tag ?? 'App',
        level: _levelToInt(level),
      );
    }
  }

  void logTransaction({
    required TransactionType type,
    required String entity,
    String? entityId,
    String? details,
    bool success = true,
  }) {
    final status = success ? '✓' : '✗';
    final message = '$status [${type.name.toUpperCase()}] $entity${entityId != null ? ' ($entityId)' : ''}${details != null ? ' - $details' : ''}';
    log(
      message,
      level: success ? LogLevel.info : LogLevel.error,
      tag: 'Transaction',
    );
  }

  void logError(String message, {Object? error, StackTrace? stackTrace}) {
    log(
      '$message${error != null ? ': $error' : ''}',
      level: LogLevel.error,
      tag: 'Error',
    );
    if (kDebugMode && stackTrace != null) {
      developer.log(stackTrace.toString(), name: 'StackTrace');
    }
  }

  void logDebug(String message, {String? tag}) {
    log(message, level: LogLevel.debug, tag: tag ?? 'Debug');
  }

  void logWarning(String message, {String? tag}) {
    log(message, level: LogLevel.warning, tag: tag ?? 'Warning');
  }

  void clearLogs() {
    _logs.clear();
  }

  List<LogEntry> getLogsByLevel(LogLevel level) {
    return _logs.where((l) => l.level == level).toList();
  }

  List<LogEntry> getLogsByTag(String tag) {
    return _logs.where((l) => l.tag == tag).toList();
  }

  int _levelToInt(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }
}

class LogEntry {
  final String message;
  final LogLevel level;
  final String? tag;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.level,
    this.tag,
    required this.timestamp,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return '[$formattedTime] [${level.name.toUpperCase()}] ${tag != null ? '[$tag] ' : ''}$message';
  }
}
