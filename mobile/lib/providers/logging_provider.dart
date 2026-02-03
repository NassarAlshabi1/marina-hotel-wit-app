import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/logging_service.dart';

export '../services/logging_service.dart' show LogLevel, TransactionType, LogEntry;

final loggingServiceProvider = Provider<LoggingService>((ref) {
  return LoggingService.instance;
});

final logsProvider = Provider<List<LogEntry>>((ref) {
  return ref.watch(loggingServiceProvider).logs;
});

final recentLogsProvider = Provider.family<List<LogEntry>, int>((ref, count) {
  return ref.watch(loggingServiceProvider).getRecentLogs(count);
});

final errorLogsProvider = Provider<List<LogEntry>>((ref) {
  return ref.watch(loggingServiceProvider).getLogsByLevel(LogLevel.error);
});

final transactionLogsProvider = Provider<List<LogEntry>>((ref) {
  return ref.watch(loggingServiceProvider).getLogsByTag('Transaction');
});
