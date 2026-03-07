import 'package:intl/intl.dart';

enum LogLevel {
  debug(0),
  info(1),
  warning(2),
  error(3),
  critical(4);

  final int value;
  const LogLevel(this.value);
}

/// نوع العملية للتسجيل
enum OperationType {
  connection, // اتصال
  push, // رفع
  pull, // سحب
  general, // عام
}

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    required this.tag,
    this.error,
    this.stackTrace,
    this.operationType = OperationType.general,
    this.entity,
    this.recordId,
    this.duration,
    this.retryCount,
    this.statusCode,
  });
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String tag;
  final dynamic error;
  final StackTrace? stackTrace;

  /// نوع العملية (اتصال، رفع، سحب)
  final OperationType operationType;

  /// اسم الكيان المتأثر (bookings, payments, etc.)
  final String? entity;

  /// معرف السجل المتأثر
  final String? recordId;

  /// مدة العملية بالميلي ثانية
  final int? duration;

  /// عدد محاولات الإعادة
  final int? retryCount;

  /// رمز حالة HTTP
  final int? statusCode;

  String toFormattedString() {
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
    final levelStr = level.name.toUpperCase().padRight(8);
    final opStr = _getOperationIcon();
    var log = '[$timeStr] [$levelStr] $opStr [$tag] $message';
    if (error != null) {
      log += '\nError: $error';
    }
    if (stackTrace != null) {
      log += '\nStack Trace:\n$stackTrace';
    }
    return log;
  }

  String _getOperationIcon() {
    switch (operationType) {
      case OperationType.connection:
        return '🔗';
      case OperationType.push:
        return '📤';
      case OperationType.pull:
        return '📥';
      case OperationType.general:
        return '📝';
    }
  }

  String get operationName {
    switch (operationType) {
      case OperationType.connection:
        return 'اتصال';
      case OperationType.push:
        return 'رفع';
      case OperationType.pull:
        return 'سحب';
      case OperationType.general:
        return 'عام';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'message': message,
      'tag': tag,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
      'operationType': operationType.name,
      'entity': entity,
      'recordId': recordId,
      'duration': duration,
      'retryCount': retryCount,
      'statusCode': statusCode,
    };
  }
}
