// lib/utils/app_logger.dart
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// نظام تسجيل موحد للتطبيق — بديل احترافي لـ print() و debugPrint().
///
/// المزايا:
/// - مستويات تسجيل واضحة (debug, info, warning, error)
/// - تصفية حسب mode (debug mode يطبع كل شيء، release mode يطبع فقط errors)
/// - دعم tag لتصنيف الرسائل (SYNC, BACKUP, DRIVE, ...)
/// - دعم stack traces للأخطاء
/// - دعم Crashlytics للتقارير في الإنتاج
///
/// الاستخدام:
/// ```dart
/// AppLogger.debug('بدء المزامنة', tag: 'SYNC');
/// AppLogger.info('تم رفع 50 سجل', tag: 'SYNC');
/// AppLogger.warning('تعارض في الحجز $id', tag: 'SYNC');
/// AppLogger.error('فشل الرفع', error: e, stackTrace: st, tag: 'SYNC');
/// ```
class AppLogger {
  AppLogger._();

  /// مستويات التسجيل
  static const LevelFilter filter = kReleaseMode
      ? LevelFilter
            .production // release: فقط warning + error
      : LevelFilter.debug; // debug: كل شيء

  /// رسالة debug — تفاصيل تشخيصية، تُطبع فقط في debug mode
  static void debug(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (filter.showDebug) {
      _log('DEBUG', message, tag: tag, error: error, stackTrace: stackTrace);
    }
  }

  /// رسالة info — معلومات عامة عن التشغيل
  static void info(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (filter.showInfo) {
      _log('INFO', message, tag: tag, error: error, stackTrace: stackTrace);
    }
  }

  /// رسالة warning — تحذيرات (ليست أخطاء حرجة)
  static void warning(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (filter.showWarning) {
      _log('WARN', message, tag: tag, error: error, stackTrace: stackTrace);
    }
  }

  /// رسالة error — أخطاء حرجة
  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (filter.showError) {
      _log('ERROR', message, tag: tag, error: error, stackTrace: stackTrace);
      // TODO: في الإنتاج، أرسل إلى Crashlytics
      // if (kReleaseMode) {
      //   FirebaseCrashlytics.instance.recordError(error ?? message, stackTrace);
      // }
    }
  }

  static void _log(String level, String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    final timestamp = DateTime.now().toIso8601String();
    final tagStr = tag != null ? '[$tag]' : '';
    final prefix = '$timestamp $level $tagStr';

    final fullMessage = error != null ? '$prefix $message — $error' : '$prefix $message';

    // استخدام debugPrint لتجنب تطويل console في release
    debugPrint(fullMessage);

    // تسجيل في developer.log للـ DevTools
    developer.log(message, name: tag ?? 'App', error: error, stackTrace: stackTrace, level: _levelToPriority(level));

    if (stackTrace != null && level == 'ERROR') {
      debugPrint(stackTrace.toString());
    }
  }

  static int _levelToPriority(String level) {
    switch (level) {
      case 'DEBUG':
        return 100;
      case 'INFO':
        return 200;
      case 'WARN':
        return 500;
      case 'ERROR':
        return 900;
      default:
        return 0;
    }
  }
}

/// فلتر المستويات حسب mode
class LevelFilter {
  const LevelFilter({
    required this.showDebug,
    required this.showInfo,
    required this.showWarning,
    required this.showError,
  });

  /// debug mode: كل المستويات
  static const LevelFilter debug = LevelFilter(showDebug: true, showInfo: true, showWarning: true, showError: true);

  /// release mode: فقط warning + error
  static const LevelFilter production = LevelFilter(
    showDebug: false,
    showInfo: false,
    showWarning: true,
    showError: true,
  );

  final bool showDebug;
  final bool showInfo;
  final bool showWarning;
  final bool showError;
}
