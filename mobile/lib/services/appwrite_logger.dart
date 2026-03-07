import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'logging/log_models.dart';

export 'logging/log_models.dart';

/// نظام التسجيل المتقدم
class AppwriteLogger {
  factory AppwriteLogger() => _instance;
  AppwriteLogger._internal();
  static final AppwriteLogger _instance = AppwriteLogger._internal();

  final List<LogEntry> _logs = [];
  static const int _maxLogEntries = 200;
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

      if (!await logsDir.exists()) {
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
    OperationType operationType = OperationType.general,
    String? entity,
    String? recordId,
    int? duration,
    int? retryCount,
    int? statusCode,
  }) {
    if (level.value < _minLevel.value) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      operationType: operationType,
      entity: entity,
      recordId: recordId,
      duration: duration,
      retryCount: retryCount,
      statusCode: statusCode,
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

  // ==================== دوال التسجيل حسب نوع العملية ====================

  /// تسجيل خطأ اتصال
  void connectionError(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    int? statusCode,
    int? duration,
  }) {
    log(
      message,
      level: LogLevel.error,
      tag: 'CONNECTION',
      operationType: OperationType.connection,
      error: error,
      stackTrace: stackTrace,
      statusCode: statusCode,
      duration: duration,
    );
  }

  /// تسجيل نجاح اتصال
  void connectionSuccess({
    int? duration,
  }) {
    log(
      'تم الاتصال بنجاح',
      level: LogLevel.info,
      tag: 'CONNECTION',
      operationType: OperationType.connection,
      duration: duration,
    );
  }

  /// تسجيل خطأ رفع
  void pushError(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    String? entity,
    String? recordId,
    int? statusCode,
    int? retryCount,
    int? duration,
  }) {
    log(
      message,
      level: LogLevel.error,
      tag: 'PUSH',
      operationType: OperationType.push,
      error: error,
      stackTrace: stackTrace,
      entity: entity,
      recordId: recordId,
      statusCode: statusCode,
      retryCount: retryCount,
      duration: duration,
    );
  }

  /// تسجيل نجاح رفع
  void pushSuccess({
    String? entity,
    int? count,
    int? duration,
  }) {
    log(
      count != null ? 'تم رفع $count سجل بنجاح' : 'تم الرفع بنجاح',
      level: LogLevel.info,
      tag: 'PUSH',
      operationType: OperationType.push,
      entity: entity,
      duration: duration,
    );
  }

  /// تسجيل خطأ سحب
  void pullError(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    String? entity,
    String? recordId,
    int? statusCode,
    int? retryCount,
    int? duration,
  }) {
    log(
      message,
      level: LogLevel.error,
      tag: 'PULL',
      operationType: OperationType.pull,
      error: error,
      stackTrace: stackTrace,
      entity: entity,
      recordId: recordId,
      statusCode: statusCode,
      retryCount: retryCount,
      duration: duration,
    );
  }

  /// تسجيل نجاح سحب
  void pullSuccess({
    String? entity,
    int? count,
    int? duration,
  }) {
    log(
      count != null ? 'تم سحب $count سجل بنجاح' : 'تم السحب بنجاح',
      level: LogLevel.info,
      tag: 'PULL',
      operationType: OperationType.pull,
      entity: entity,
      duration: duration,
    );
  }

  // ==================== دوال التسجيل العامة ====================

  // Convenience methods
  void debug(String message, {String tag = 'APPWRITE'}) {
    log(message, level: LogLevel.debug, tag: tag);
  }

  void info(String message, {String tag = 'APPWRITE'}) {
    log(message, level: LogLevel.info, tag: tag);
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
  List<LogEntry> getLogs({LogLevel? filterLevel, OperationType? filterOperation}) {
    var logs = _logs;
    
    if (filterLevel != null) {
      logs = logs.where((log) => log.level == filterLevel).toList();
    }
    
    if (filterOperation != null) {
      logs = logs.where((log) => log.operationType == filterOperation).toList();
    }
    
    return List.unmodifiable(logs);
  }

  /// الحصول على أخطاء العمليات فقط
  List<LogEntry> getOperationErrors({OperationType? operationType}) {
    var errors = _logs.where((log) => 
      log.level == LogLevel.error || log.level == LogLevel.critical
    );
    
    if (operationType != null) {
      errors = errors.where((log) => log.operationType == operationType);
    }
    
    return errors.toList();
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
      'connection_errors': _logs.where((l) => 
        l.operationType == OperationType.connection && 
        (l.level == LogLevel.error || l.level == LogLevel.critical)
      ).length,
      'push_errors': _logs.where((l) => 
        l.operationType == OperationType.push && 
        (l.level == LogLevel.error || l.level == LogLevel.critical)
      ).length,
      'pull_errors': _logs.where((l) => 
        l.operationType == OperationType.pull && 
        (l.level == LogLevel.error || l.level == LogLevel.critical)
      ).length,
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
