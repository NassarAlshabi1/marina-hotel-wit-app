/// ============================================================
/// Marina Hotel - Safe Catch Helper
/// ============================================================
/// استبدال تدريجي لـ 134 catch (_) الصامتة
/// يستخدم AppLogger أو DiagnosticsLogger حسب المتوفر
/// ============================================================

import 'app_logger.dart';

/// دالة مساعدة لاستبدال catch (_) الصامتة
/// تسجل الخطأ ولا تبتلعه
void reportError(
  Object error, {
  String message = '⚠️ خطأ غير متوقع',
  String tag = 'SAFE',
  StackTrace? stackTrace,
}) {
  AppLogger.warning(
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

/// للإبلاغ عن خطأ غير متوقع مع معلومات السياق
void reportUnexpected(
  Object error, {
  required String context,
  String tag = 'SAFE',
  StackTrace? stackTrace,
}) {
  AppLogger.error(
    '⚠️ [catch] $context',
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}
