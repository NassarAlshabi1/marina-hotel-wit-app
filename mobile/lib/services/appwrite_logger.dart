import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'logging/log_models.dart';

export 'logging/log_models.dart';

/// نظام التسجيل المتقدم
class AppwriteLogger {
  factory AppwriteLogger() => _instance;
  AppwriteLogger._internal();
  static final AppwriteLogger _instance = AppwriteLogger._internal();

  final List<LogEntry> _logs = [];
  static const int _maxLogEntries = 100;
  LogLevel _minLevel = LogLevel.info;
  bool _enableConsole = true;
  bool _enableFile = false;
  File? _logFile;

  /// تهيئة المسجل
  Future<void> initialize({
    LogLevel minLevel = LogLevel.info,
    bool enableConsole = true,
    bool enableFile = false,
  }) async {
    _minLevel = minLevel;
    _enableConsole = enableConsole;
    _enableFile = enableFile;

    if (_enableFile) {
      await _initializeLogFile();
    }
  }

  /// تهيئة ملف السجل
  Future<void> _initializeLogFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logsDir = Directory('${directory.path}/appwrite_logs');

      if (!logsDir.existsSync()) {
        await logsDir.create(recursive: true);
      }

      final fileName =
          'appwrite_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.log';
      _logFile = File('${logsDir.path}/$fileName');
    } catch (e) {
      debugPrint('Error initializing log file: $e');
    }
  }

  /// تسجيل رسالة
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String tag = 'APPWRITE',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    if (level.value < _minLevel.value) {
      return;
    }

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );

    _logs.add(entry);
    if (_logs.length > _maxLogEntries) {
      _logs.removeRange(0, _logs.length - _maxLogEntries);
    }

    // طباعة في وضع Debug
    if (_enableConsole && kDebugMode) {
      _printToConsole(entry);
    }

    // كتابة إلى الملف
    if (_enableFile && _logFile != null) {
      _writeToFile(entry);
    }
  }

  /// طباعة إلى Console
  void _printToConsole(LogEntry entry) {
    final emoji = _getEmojiForLevel(entry.level);
    debugPrint('$emoji ${entry.toFormattedString()}');
  }

  /// كتابة إلى الملف
  Future<void> _writeToFile(LogEntry entry) async {
    try {
      await _logFile?.writeAsString(
        '${entry.toFormattedString()}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      debugPrint('Error writing to log file: $e');
    }
  }

  /// الحصول على Emoji حسب المستوى
  String _getEmojiForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '🐛';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
      case LogLevel.critical:
        return '🔥';
    }
  }

  // Convenience methods
  void debug(String message, {String tag = 'APPWRITE'}) {
    log(message, level: LogLevel.debug, tag: tag);
  }

  void info(String message, {String tag = 'APPWRITE'}) {
    log(message, tag: tag);
  }

  void warning(
    String message, {
    String tag = 'APPWRITE',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      level: LogLevel.warning,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void error(
    String message, {
    String tag = 'APPWRITE',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      level: LogLevel.error,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void critical(
    String message, {
    String tag = 'APPWRITE',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      level: LogLevel.critical,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// الحصول على جميع السجلات
  List<LogEntry> getLogs({LogLevel? filterLevel}) {
    if (filterLevel == null) {
      return List.unmodifiable(_logs);
    }
    return _logs.where((log) => log.level == filterLevel).toList();
  }

  /// الحصول على إحصائيات السجلات
  Map<String, int> getStatistics() {
    return {
      'total': _logs.length,
      'debug': _logs.where((l) => l.level == LogLevel.debug).length,
      'info': _logs.where((l) => l.level == LogLevel.info).length,
      'warning': _logs.where((l) => l.level == LogLevel.warning).length,
      'error': _logs.where((l) => l.level == LogLevel.error).length,
      'critical': _logs.where((l) => l.level == LogLevel.critical).length,
    };
  }

  /// مسح السجلات
  void clearLogs() {
    _logs.clear();
  }

  /// تصدير السجلات
  Future<File?> exportLogs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'appwrite_logs_export_${DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())}.txt';
      final file = File('${directory.path}/$fileName');

      final buffer = StringBuffer();
      for (final log in _logs) {
        buffer.writeln(log.toFormattedString());
        buffer.writeln('─' * 80);
      }

      await file.writeAsString(buffer.toString());
      return file;
    } catch (e) {
      error('Failed to export logs', error: e);
      return null;
    }
  }

  /// الحصول على مسار ملف السجل الحالي
  String? get currentLogFilePath => _logFile?.path;
}
