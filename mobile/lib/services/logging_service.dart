import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static LoggingService? _instance;
  static final Object _lock = Object();
  
  final Queue<LogEntry> _logs = Queue<LogEntry>();
  static const int _maxLogs = 500;
  static const String _storageKey = 'app_logs';
  
  SharedPreferences? _prefs;
  bool _isInitialized = false;

  LoggingService._internal();

  static LoggingService get instance {
    if (_instance == null) {
      synchronized(_lock, () {
        _instance ??= LoggingService._internal();
      });
    }
    return _instance!;
  }

  factory LoggingService() => instance;

  bool get isInitialized => _isInitialized;
  List<LogEntry> get logs => List.unmodifiable(_logs);

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadLogsFromStorage();
      _isInitialized = true;
      logDebug('LoggingService initialized', tag: 'Init');
    } catch (e) {
      if (kDebugMode) {
        developer.log('Failed to init LoggingService: $e', name: 'Error');
      }
    }
  }

  Future<void> _loadLogsFromStorage() async {
    try {
      final jsonList = _prefs?.getStringList(_storageKey);
      if (jsonList != null && jsonList.isNotEmpty) {
        _logs.clear();
        for (final jsonStr in jsonList) {
          try {
            final entry = LogEntry.fromJson(json.decode(jsonStr));
            _logs.add(entry);
          } catch (_) {}
        }
      }
    } catch (e) {
      if (kDebugMode) {
        developer.log('Failed to load logs: $e', name: 'Error');
      }
    }
  }

  Future<void> _saveLogsToStorage() async {
    if (_prefs == null) return;
    try {
      final jsonList = _logs.map((e) => json.encode(e.toJson())).toList();
      await _prefs!.setStringList(_storageKey, jsonList);
    } catch (_) {}
  }

  void log(String message, {LogLevel level = LogLevel.info, String? tag}) {
    final entry = LogEntry(
      message: message,
      level: level,
      tag: tag,
      timestamp: DateTime.now(),
    );
    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeFirst();
    }
    if (kDebugMode) {
      developer.log(message, name: tag ?? 'App', level: _levelToInt(level));
    }
    _saveLogsToStorage();
  }

  void logTransaction({
    required TransactionType type,
    required String entity,
    String? entityId,
    String? details,
    bool success = true,
  }) {
    final status = success ? '✓' : '✗';
    final idPart = entityId != null ? ' ($entityId)' : '';
    final detailsPart = details != null ? ' - $details' : '';
    final message = '$status [${type.name.toUpperCase()}] $entity$idPart$detailsPart';
    log(message, level: success ? LogLevel.info : LogLevel.error, tag: 'Transaction');
  }

  void logError(String message, {Object? error, StackTrace? stackTrace}) {
    log('$message${error != null ? ': $error' : ''}', level: LogLevel.error, tag: 'Error');
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

  Future<void> clearLogs() async {
    _logs.clear();
    await _prefs?.remove(_storageKey);
  }

  List<LogEntry> getLogsByLevel(LogLevel level) {
    return _logs.where((l) => l.level == level).toList();
  }

  List<LogEntry> getLogsByTag(String tag) {
    return _logs.where((l) => l.tag == tag).toList();
  }

  List<LogEntry> getRecentLogs(int count) {
    final list = _logs.toList();
    if (list.length <= count) return list;
    return list.sublist(list.length - count);
  }

  int _levelToInt(LogLevel level) {
    switch (level) {
      case LogLevel.debug: return 500;
      case LogLevel.info: return 800;
      case LogLevel.warning: return 900;
      case LogLevel.error: return 1000;
    }
  }
}

void synchronized(Object lock, void Function() action) => action();

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

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      message: json['message'] as String,
      level: LogLevel.values.firstWhere((l) => l.name == json['level'], orElse: () => LogLevel.info),
      tag: json['tag'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'message': message,
    'level': level.name,
    'tag': tag,
    'timestamp': timestamp.toIso8601String(),
  };

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return '[$formattedTime] [${level.name.toUpperCase()}] ${tag != null ? '[$tag] ' : ''}$message';
  }
}
