// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../logging/log_models.dart';

class DiagnosticsLogger extends ChangeNotifier {
  DiagnosticsLogger._internal();

  static final DiagnosticsLogger instance = DiagnosticsLogger._internal();

  final List<LogEntry> _logs = [];
  File? _logFile;
  bool _initialized = false;
  int _maxEntries = 500;

  Future<void> initialize({
    int maxEntries = 500,
    bool enableFile = true,
  }) async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _maxEntries = maxEntries;
    if (enableFile) {
      final directory = await getApplicationDocumentsDirectory();
      final logsDir = Directory('${directory.path}/diagnostics');
      if (!logsDir.existsSync()) {
        await logsDir.create(recursive: true);
      }
      final fileName =
          'diagnostics_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.log';
      _logFile = File('${logsDir.path}/$fileName');
    }
  }

  void recordFlutterError(FlutterErrorDetails details) {
    recordError(
      details.exception,
      details.stack,
      tag: 'FLUTTER',
      message: details.exceptionAsString(),
    );
  }

  void recordError(
    Object error,
    StackTrace? stackTrace, {
    String tag = 'APP',
    String? message,
    LogLevel level = LogLevel.error,
  }) {
    log(
      message ?? error.toString(),
      tag: tag,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void log(
    String message, {
    String tag = 'APP',
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
    _logs.add(entry);
    if (_logs.length > _maxEntries) {
      _logs.removeRange(0, _logs.length - _maxEntries);
    }
    _writeToFile(entry);
    notifyListeners();
  }

  void info(String message, {String tag = 'APP'}) {
    log(message, tag: tag);
  }

  void warning(String message, {String tag = 'APP', Object? error}) {
    log(message, tag: tag, level: LogLevel.warning, error: error);
  }

  void error(
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      tag: tag,
      level: LogLevel.error,
      error: error,
      stackTrace: stackTrace,
    );
  }

  List<LogEntry> getLogs({LogLevel? filter}) {
    if (filter == null) {
      return List.unmodifiable(_logs);
    }
    return _logs.where((e) => e.level == filter).toList();
  }

  Map<String, int> getStats() {
    final stats = {
      'total': _logs.length,
      'debug': 0,
      'info': 0,
      'warning': 0,
      'error': 0,
      'critical': 0,
    };
    for (final log in _logs) {
      stats[log.level.name] = (stats[log.level.name] ?? 0) + 1;
    }
    return stats;
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }

  Future<File?> exportLogs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'diagnostics_logs_${DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())}.txt';
      final file = File('${directory.path}/$fileName');
      final buffer = StringBuffer();
      for (final entry in _logs) {
        buffer.writeln(entry.toFormattedString());
        buffer.writeln('─' * 80);
      }
      await file.writeAsString(buffer.toString());
      return file;
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in diagnostics_logger.dart: ');
      return null;
    }
  }

  Future<void> _writeToFile(LogEntry entry) async {
    if (_logFile == null) {
      return;
    }
    try {
      await _logFile!.writeAsString(
        '${entry.toFormattedString()}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      debugPrint('⚠️ Swallowed error in diagnostics_logger.dart: ');}
  }

  /// ✅ إصلاح: إضافة dispose() لتنظيف المستمعين ومنع تسرب الذاكرة
  @override
  void dispose() {
    _logs.clear();
    super.dispose();
  }
}
