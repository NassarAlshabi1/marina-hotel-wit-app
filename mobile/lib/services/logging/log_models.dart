import 'package:intl/intl.dart';

enum LogLevel {
  debug(0),
  info(1),
  warning(2),
  error(3),
  critical(4);

  const LogLevel(this.value);
  final int value;
}

class LogEntry {

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    required this.tag,
    this.error,
    this.stackTrace,
  });
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String tag;
  final dynamic error;
  final StackTrace? stackTrace;

  String toFormattedString() {
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
    final levelStr = level.name.toUpperCase().padRight(8);
    var log = '[$timeStr] [$levelStr] [$tag] $message';
    if (error != null) {
      log += '\nError: $error';
    }
    if (stackTrace != null) {
      log += '\nStack Trace:\n$stackTrace';
    }
    return log;
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'message': message,
      'tag': tag,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
    };
  }
}
