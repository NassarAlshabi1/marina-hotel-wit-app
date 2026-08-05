// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'logging/log_models.dart';

class GoogleDriveLogger extends ChangeNotifier {
  factory GoogleDriveLogger() => _instance;
  GoogleDriveLogger._internal();
  static final GoogleDriveLogger _instance = GoogleDriveLogger._internal();

  final List<LogEntry> _logs = [];
  static const int _maxLogEntries = 100;
  final Map<LogLevel, int> _logCounts = {};
  LogLevel _minLevel = LogLevel.info;
  bool _enableConsole = true;
  bool _enableFile = false;
  File? _logFile;

  @override
  void dispose() {
    _logs.clear();
    _logCounts.clear();
    super.dispose();
  }

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

  Future<void> _initializeLogFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logsDir = Directory('${directory.path}/drive_logs');
      if (!logsDir.existsSync()) {
        await logsDir.create(recursive: true);
      }
      final fileName =
          'drive_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.log';
      _logFile = File('${logsDir.path}/$fileName');
    } catch (e, st) {
      debugPrint('Error initializing drive log file: $e');
    }
  }

  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String tag = 'DRIVE',
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
    _logCounts[level] = (_logCounts[level] ?? 0) + 1;
    if (_enableConsole && kDebugMode) {
      _printToConsole(entry);
    }
    if (_enableFile && _logFile != null) {
      _writeToFile(entry);
    }
    notifyListeners();
  }

  void _printToConsole(LogEntry entry) {
    final emoji = _getEmojiForLevel(entry.level);
    debugPrint('$emoji ${entry.toFormattedString()}');
  }

  Future<void> _writeToFile(LogEntry entry) async {
    try {
      await _logFile?.writeAsString(
        '${entry.toFormattedString()}\n',
        mode: FileMode.append,
      );
    } catch (e, st) {
      debugPrint('Error writing drive log: $e');
    }
  }

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

  void debug(String message, {String tag = 'DRIVE'}) {
    log(message, level: LogLevel.debug, tag: tag);
  }

  void info(String message, {String tag = 'DRIVE'}) {
    log(message, tag: tag);
  }

  void warning(String message, {String tag = 'DRIVE', dynamic error}) {
    log(message, level: LogLevel.warning, tag: tag, error: error);
  }

  void error(
    String message, {
    String tag = 'DRIVE',
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
    String tag = 'DRIVE',
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

  List<LogEntry> getLogs({LogLevel? filterLevel}) {
    if (filterLevel == null) {
      return List.unmodifiable(_logs);
    }
    return _logs.where((log) => log.level == filterLevel).toList();
  }

  Map<String, int> getStatistics() {
    final total = _logCounts.values.fold<int>(0, (sum, count) => sum + count);
    return {
      'total': total,
      'debug': _logCounts[LogLevel.debug] ?? 0,
      'info': _logCounts[LogLevel.info] ?? 0,
      'warning': _logCounts[LogLevel.warning] ?? 0,
      'error': _logCounts[LogLevel.error] ?? 0,
      'critical': _logCounts[LogLevel.critical] ?? 0,
    };
  }

  void clearLogs() {
    _logs.clear();
    _logCounts.clear();
    notifyListeners();
  }

  Future<File?> exportLogs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'drive_logs_${DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())}.txt';
      final file = File('${directory.path}/$fileName');
      final buffer = StringBuffer();
      for (final log in _logs) {
        buffer.writeln(log.toFormattedString());
        buffer.writeln('─' * 80);
      }
      await file.writeAsString(buffer.toString());
      return file;
    } catch (e, st) {
      error('Failed to export drive logs', error: e);
      return null;
    }
  }

  String? get currentLogFilePath => _logFile?.path;
}
