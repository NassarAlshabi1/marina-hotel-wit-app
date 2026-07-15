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

      final fileName = 'appwrite_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.log';
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

    if (_enableConsole) {
      _printToConsole(entry);
    }

    if (_enableFile && _logFile != null) {
      _writeToFile(entry);
    }
  }

  /// تسجيل خطأ في الجدول
  void logTableError({
    required String tableName,
    required String operation,
    required String errorMessage,
    String? recordId,
    Map<String, dynamic>? recordData,
    StackTrace? stackTrace,
  }) {
    final message = StringBuffer();
    message.writeln('❌ خطأ في الجدول: $tableName');
    message.writeln('   العملية: $operation');
    if (recordId != null) {
      message.writeln('   معرف السجل: $recordId');
    }
    if (recordData != null) {
      message.writeln('   البيانات: $recordData');
    }
    message.write('   الخطأ: $errorMessage');

    log(message.toString(), level: LogLevel.error, tag: 'TABLE_ERROR', error: errorMessage, stackTrace: stackTrace);
  }

  /// تسجيل خطأ في الحقل
  void logFieldError({
    required String tableName,
    required String fieldName,
    required String errorMessage,
    String? recordId,
    dynamic fieldValue,
    StackTrace? stackTrace,
  }) {
    final message = StringBuffer();
    message.writeln('❌ خطأ في الحقل: $tableName.$fieldName');
    message.writeln('   نوع الخطأ: $errorMessage');
    if (recordId != null) {
      message.writeln('   معرف السجل: $recordId');
    }
    if (fieldValue != null) {
      message.writeln('   قيمة الحقل: $fieldValue');
    }

    log(message.toString(), level: LogLevel.error, tag: 'FIELD_ERROR', error: errorMessage, stackTrace: stackTrace);
  }

  /// تسجيل خطأ في المخطط (Schema)
  void logSchemaError({
    required String collectionName,
    required String errorMessage,
    String? expectedField,
    String? actualField,
    StackTrace? stackTrace,
  }) {
    final message = StringBuffer();
    message.writeln('⚠️ خطأ في مخطط Appwrite: $collectionName');
    message.writeln('   الرسالة: $errorMessage');
    if (expectedField != null) {
      message.writeln('   الحقل المتوقع: $expectedField');
    }
    if (actualField != null) {
      message.writeln('   الحقل الفعلي: $actualField');
    }

    log(message.toString(), level: LogLevel.warning, tag: 'SCHEMA_ERROR', error: errorMessage, stackTrace: stackTrace);
  }

  /// تسجيل عدم تطابق الحقول
  void logFieldMismatch({
    required String tableName,
    required List<String> missingFields,
    required List<String> extraFields,
    StackTrace? stackTrace,
  }) {
    final message = StringBuffer();
    message.writeln('🔍 عدم تطابق الحقول: $tableName');
    if (missingFields.isNotEmpty) {
      message.writeln('   حقول مفقودة: ${missingFields.join(', ')}');
    }
    if (extraFields.isNotEmpty) {
      message.writeln('   حقول إضافية: ${extraFields.join(', ')}');
    }

    log(
      message.toString(),
      level: LogLevel.warning,
      tag: 'FIELD_MISMATCH',
      error: 'Missing: ${missingFields.length}, Extra: ${extraFields.length}',
      stackTrace: stackTrace,
    );
  }

  /// تسجيل فشل المزامنة
  void logSyncError({
    required String tableName,
    required String operation,
    required String errorMessage,
    String? localId,
    String? serverId,
    StackTrace? stackTrace,
  }) {
    final message = StringBuffer();
    message.writeln('🔄 فشل المزامنة: $tableName');
    message.writeln('   العملية: $operation');
    if (localId != null) {
      message.writeln('   المحلي ID: $localId');
    }
    if (serverId != null) {
      message.writeln('   السيرفر ID: $serverId');
    }
    message.write('   الخطأ: $errorMessage');

    log(message.toString(), level: LogLevel.error, tag: 'SYNC_ERROR', error: errorMessage, stackTrace: stackTrace);
  }

  /// طباعة إلى Console
  void _printToConsole(LogEntry entry) {
    final emoji = _getEmojiForLevel(entry.level);
    debugPrint('$emoji ${entry.toFormattedString()}');
  }

  /// كتابة إلى الملف
  Future<void> _writeToFile(LogEntry entry) async {
    try {
      await _logFile?.writeAsString('${entry.toFormattedString()}\n', mode: FileMode.append);
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

  void warning(String message, {String tag = 'APPWRITE', dynamic error, StackTrace? stackTrace}) {
    log(message, level: LogLevel.warning, tag: tag, error: error, stackTrace: stackTrace);
  }

  void error(String message, {String tag = 'APPWRITE', dynamic error, StackTrace? stackTrace}) {
    log(message, level: LogLevel.error, tag: tag, error: error, stackTrace: stackTrace);
  }

  void critical(String message, {String tag = 'APPWRITE', dynamic error, StackTrace? stackTrace}) {
    log(message, level: LogLevel.critical, tag: tag, error: error, stackTrace: stackTrace);
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
      final fileName = 'appwrite_logs_export_${DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now())}.txt';
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
