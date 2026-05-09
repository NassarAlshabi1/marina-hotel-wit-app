import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../services/diagnostics/diagnostics_logger.dart';
import '../services/logging/log_models.dart';

/// مسجل منظم يوفر مستويات تسجيل مختلفة بدلاً من debugPrint
/// الاستخدام: AppLogger.info('تم تسجيل الدخول', tag: 'AUTH');
class AppLogger {
  AppLogger._();

  /// مستوى التسجيل الأدنى في وضع الإصدار (warning = 2)
  static const int _releaseMinLevel = 2;

  // ─── واجهة عامة ──────────────────────────────────────────

  /// تسجيل رسالة تصحيح - فقط في وضع التطوير
  static void debug(
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.debug, message, tag: tag, error: error, stackTrace: stackTrace);

  /// تسجيل رسالة معلوماتية
  static void info(
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.info, message, tag: tag, error: error, stackTrace: stackTrace);

  /// تسجيل تحذير
  static void warning(
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.warning, message, tag: tag, error: error, stackTrace: stackTrace);

  /// تسجيل خطأ
  static void error(
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.error, message, tag: tag, error: error, stackTrace: stackTrace);

  /// تسجيل خطأ حرج
  static void critical(
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.critical, message, tag: tag, error: error, stackTrace: stackTrace);

  // ─── التنفيذ الداخلي ─────────────────────────────────────

  static void _log(
    LogLevel level,
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stackTrace,
  }) {
    // إعادة توجيه إلى DiagnosticsLogger دائماً (مع حماية من الأخطاء)
    try {
      DiagnosticsLogger.instance.log(
        message,
        tag: tag,
        level: level,
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {
      // لا نريد أن يفشل التسجيل بسبب مشكلة في DiagnosticsLogger
    }

    // فلترة حسب المستوى في وضع الإصدار
    if (!kDebugMode && level.value < _releaseMinLevel) {
      return;
    }

    // تنسيق الرسالة
    final levelStr = level.name.toUpperCase().padRight(8);
    final buffer = StringBuffer('[$tag $levelStr] $message');

    if (error != null) {
      buffer.writeln();
      buffer.write('  ↳ Error: $error');
    }
    if (stackTrace != null) {
      buffer.writeln();
      buffer.write('  ↳ StackTrace:\n$stackTrace');
    }

    final output = buffer.toString();

    if (kDebugMode) {
      debugPrint(output);
    } else {
      // في وضع الإصدار نستخدم developer.log
      final developerLevel = _mapToDeveloperLevel(level);
      developer.log(output, level: developerLevel, name: tag);
    }
  }

  /// تحويل LogLevel إلى مستوى developer.log
  static int _mapToDeveloperLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
      case LogLevel.critical:
        return 1200;
    }
  }
}
