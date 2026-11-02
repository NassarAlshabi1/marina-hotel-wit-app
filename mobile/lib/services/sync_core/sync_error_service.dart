import 'package:flutter/material.dart';
import '../appwrite_error_handler.dart';
import '../appwrite_logger.dart';
import '../crashlytics_service.dart';

/// خدمة موحدة للتعامل مع الأخطاء في نظام المزامنة
/// تجمع AppwriteLogger + CrashlyticsService + AppwriteErrorHandler تحت واجهة واحدة
class SyncErrorService {
  SyncErrorService({
    required this.tag,
    AppwriteLogger? logger,
    AppwriteErrorHandler? errorHandler,
    CrashlyticsService? crashlytics,
  }) : _logger = logger ?? AppwriteLogger(),
       _errorHandler = errorHandler ?? AppwriteErrorHandler(),
       _crashlytics = crashlytics ?? CrashlyticsService.instance;
  final AppwriteLogger _logger;
  final AppwriteErrorHandler _errorHandler;
  final CrashlyticsService _crashlytics;
  final String tag;

  /// تسجيل معلومات
  void info(String message, {Map<String, dynamic>? context}) {
    _logger.info(message, tag: tag);
  }

  /// تسجيل تحذير
  void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    _logger.warning(message, error: error, stackTrace: stackTrace, tag: tag);
  }

  /// تسجيل خطأ مع إرسال إلى Crashlytics تلقائياً
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool fatal = false,
    Map<String, dynamic>? context,
  }) {
    _logger.error(message, error: error, stackTrace: stackTrace, tag: tag);

    if (fatal) {
      _crashlytics.recordFatalSyncError(
        operation: tag,
        error: error ?? message,
        stackTrace: stackTrace,
        context: context ?? const {},
      );
    } else {
      _crashlytics.recordSyncError(
        operation: tag,
        error: error?.toString() ?? message,
        stackTrace: stackTrace,
        context: context ?? const {},
      );
    }
  }

  /// معالجة خطأ Appwrite وإرجاع الرسالة المنسقة
  AppwriteErrorResult handleAppwriteError(
    Object error, {
    String? context,
    StackTrace? stackTrace,
  }) {
    final appwriteError = _errorHandler.handleError(
      error,
      context: context ?? tag,
      stackTrace: stackTrace,
    );
    _logger.warning(
      appwriteError.message,
      error: error,
      stackTrace: stackTrace,
      tag: tag,
    );
    return AppwriteErrorResult(
      message: appwriteError.message,
      isRetryable: appwriteError.isRecoverable,
    );
  }

  /// إظهار SnackBar للمستخدم مع رسالة الخطأ
  void showError(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }
}

/// نتيجة معالجة خطأ Appwrite
class AppwriteErrorResult {
  const AppwriteErrorResult({required this.message, this.isRetryable = false});
  final String message;
  final bool isRetryable;
}
