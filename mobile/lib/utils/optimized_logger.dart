import 'package:flutter/foundation.dart';

/// Optimized debug logging - only prints in debug mode
void logDebug(String message, {String? tag}) {
  if (kDebugMode) {
    final prefix = tag != null ? '[$tag] ' : '';
    debugPrint('$prefix$message');
  }
}

/// Optimized debug logging with parameters - only prints in debug mode
void logDebugParams(String message, Map<String, dynamic> params, {String? tag}) {
  if (kDebugMode) {
    final prefix = tag != null ? '[$tag] ' : '';
    final paramsStr = params.entries.map((e) => '${e.key}=${e.value}').join(', ');
    debugPrint('$prefix$message: $paramsStr');
  }
}

/// Optimized error logging
void logError(String message, Object error, {String? tag, StackTrace? stackTrace}) {
  if (kDebugMode) {
    final prefix = tag != null ? '[$tag] ' : '';
    debugPrint('$prefix$message: $error');
    if (stackTrace != null) {
      debugPrint('Stack: $stackTrace');
    }
  }
  // In production, you might want to send to crash reporting service
}
