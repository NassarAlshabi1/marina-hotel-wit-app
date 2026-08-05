// CircularBufferLogger — replaces unbounded in-memory logging with a
// fixed-size circular buffer that writes to a file on disk.
//
// Benefits:
//   - No memory leaks (fixed max size)
//   - Logs survive app restart (persisted to file)
//   - Thread-safe (synchronized writes)
//   - Automatic rotation (oldest entries overwritten)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

class CircularBufferLogger {
  CircularBufferLogger._();
  static final CircularBufferLogger instance = CircularBufferLogger._();

  static const int _maxEntries = 500;
  static const String _fileName = 'app_logs.jsonl';

  final List<_LogEntry> _buffer = [];
  final Lock _lock = Lock();
  File? _logFile;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_fileName');
      await _loadExistingLogs();
      _initialized = true;
    } catch (_) {
      _initialized = true;
    }
  }

  Future<void> _loadExistingLogs() async {
    if (_logFile == null || !await _logFile!.exists()) return;
    try {
      final lines = await _logFile!.readAsLines();
      final recent = lines.length > _maxEntries
          ? lines.sublist(lines.length - _maxEntries)
          : lines;
      for (final line in recent) {
        final json = jsonDecode(line) as Map<String, dynamic>;
        _buffer.add(_LogEntry.fromJson(json));
      }
    } catch (_) {
      // Corrupt log file — start fresh
    }
  }

  void debug(String message, {String? tag}) =>
      _log(LogLevel.debug, message, tag);
  void info(String message, {String? tag}) => _log(LogLevel.info, message, tag);
  void warning(String message, {String? tag, Object? error}) =>
      _log(LogLevel.warning, message, tag, error);
  void error(String message, {String? tag, Object? error, StackTrace? stack}) =>
      _log(LogLevel.error, message, tag, error, stack);

  void _log(
    LogLevel level,
    String message,
    String? tag, [
    Object? error,
    StackTrace? stack,
  ]) {
    final entry = _LogEntry(
      level: level,
      message: message,
      tag: tag ?? 'APP',
      timestamp: DateTime.now().toIso8601String(),
      error: error?.toString(),
      stackTrace: stack?.toString(),
    );

    _buffer.add(entry);
    while (_buffer.length > _maxEntries) {
      _buffer.removeAt(0);
    }

    unawaited(_persistEntry(entry));
  }

  Future<void> _persistEntry(_LogEntry entry) async {
    if (_logFile == null) return;
    await _lock.synchronized(() async {
      try {
        await _logFile!.writeAsString(
          '${jsonEncode(entry.toJson())}\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Best-effort
      }
    });
  }

  List<Map<String, dynamic>> readLast(int count) {
    final start = _buffer.length > count ? _buffer.length - count : 0;
    return _buffer.sublist(start).map((e) => e.toJson()).toList();
  }

  Future<void> clear() async {
    _buffer.clear();
    if (_logFile != null) {
      try {
        await _logFile!.writeAsString('', flush: true);
      } catch (_) {}
    }
  }

  int get bufferSize => _buffer.length;
}

enum LogLevel { debug, info, warning, error }

class _LogEntry {
  const _LogEntry({
    required this.level,
    required this.message,
    required this.tag,
    required this.timestamp,
    this.error,
    this.stackTrace,
  });

  factory _LogEntry.fromJson(Map<String, dynamic> json) {
    return _LogEntry(
      level: LogLevel.values.byName(json['level'] as String? ?? 'info'),
      message: json['message'] as String? ?? '',
      tag: json['tag'] as String? ?? 'APP',
      timestamp: json['timestamp'] as String? ?? '',
      error: json['error'] as String?,
      stackTrace: json['stackTrace'] as String?,
    );
  }

  final LogLevel level;
  final String message;
  final String tag;
  final String timestamp;
  final String? error;
  final String? stackTrace;

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'message': message,
    'tag': tag,
    'timestamp': timestamp,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stackTrace': stackTrace,
  };
}
