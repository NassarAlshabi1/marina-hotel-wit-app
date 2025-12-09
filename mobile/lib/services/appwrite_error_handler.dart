import 'package:flutter/material.dart';
import 'appwrite_logger.dart';

/// نموذج الخطأ
class AppwriteError {
  final String code;
  final String message;
  final String? details;
  final DateTime timestamp;
  final bool isRecoverable;

  AppwriteError({
    required this.code,
    required this.message,
    this.details,
    DateTime? timestamp,
    this.isRecoverable = true,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '[$code] $message${details != null ? "\nDetails: $details" : ""}';
}

/// معالج الأخطاء المركزي
class AppwriteErrorHandler {
  static final AppwriteErrorHandler _instance = AppwriteErrorHandler._internal();
  factory AppwriteErrorHandler() => _instance;
  AppwriteErrorHandler._internal();

  final _logger = AppwriteLogger();
  final List<AppwriteError> _errorHistory = [];

  /// معالجة الخطأ
  AppwriteError handleError(
    dynamic error, {
    String context = 'Unknown',
    StackTrace? stackTrace,
  }) {
    final appwriteError = _parseError(error, context);
    _errorHistory.add(appwriteError);
    
    // تسجيل الخطأ
    _logger.error(
      '${appwriteError.message} (Context: $context)',
      error: error,
      stackTrace: stackTrace,
      tag: 'ERROR_HANDLER',
    );

    return appwriteError;
  }

  /// تحويل الخطأ إلى AppwriteError
  AppwriteError _parseError(dynamic error, String context) {
    if (error is AppwriteError) {
      return error;
    }

    // Network errors
    if (error.toString().contains('SocketException') ||
        error.toString().contains('HandshakeException') ||
        error.toString().contains('Connection') ||
        error.toString().contains('network')) {
      return AppwriteError(
        code: 'NETWORK_ERROR',
        message: 'فشل الاتصال بالشبكة',
        details: 'تحقق من اتصالك بالإنترنت وحاول مرة أخرى',
        isRecoverable: true,
      );
    }

    // Authentication errors
    if (error.toString().contains('401') ||
        error.toString().contains('Unauthorized') ||
        error.toString().contains('authentication')) {
      return AppwriteError(
        code: 'AUTH_ERROR',
        message: 'خطأ في المصادقة',
        details: 'يرجى تسجيل الدخول مرة أخرى',
        isRecoverable: true,
      );
    }

    // Permission errors
    if (error.toString().contains('403') ||
        error.toString().contains('Forbidden') ||
        error.toString().contains('permission')) {
      return AppwriteError(
        code: 'PERMISSION_ERROR',
        message: 'لا تملك صلاحية للقيام بهذا الإجراء',
        details: error.toString(),
        isRecoverable: false,
      );
    }

    // Not found errors
    if (error.toString().contains('404') ||
        error.toString().contains('Not Found') ||
        error.toString().contains('not_found')) {
      return AppwriteError(
        code: 'NOT_FOUND',
        message: 'العنصر المطلوب غير موجود',
        details: error.toString(),
        isRecoverable: false,
      );
    }

    // Server errors
    if (error.toString().contains('500') ||
        error.toString().contains('502') ||
        error.toString().contains('503') ||
        error.toString().contains('Server Error')) {
      return AppwriteError(
        code: 'SERVER_ERROR',
        message: 'خطأ في الخادم',
        details: 'يرجى المحاولة لاحقاً',
        isRecoverable: true,
      );
    }

    // Timeout errors
    if (error.toString().contains('timeout') ||
        error.toString().contains('Timeout')) {
      return AppwriteError(
        code: 'TIMEOUT_ERROR',
        message: 'انتهت مهلة الاتصال',
        details: 'استغرق الطلب وقتاً طويلاً',
        isRecoverable: true,
      );
    }

    // Rate limit errors
    if (error.toString().contains('429') ||
        error.toString().contains('Too Many Requests') ||
        error.toString().contains('rate_limit')) {
      return AppwriteError(
        code: 'RATE_LIMIT',
        message: 'تم تجاوز حد الطلبات',
        details: 'يرجى الانتظار قليلاً قبل المحاولة مرة أخرى',
        isRecoverable: true,
      );
    }

    // Conflict errors (for sync)
    if (error.toString().contains('409') ||
        error.toString().contains('Conflict') ||
        error.toString().contains('conflict')) {
      return AppwriteError(
        code: 'CONFLICT_ERROR',
        message: 'تضارب في البيانات',
        details: 'تم تعديل البيانات من قبل جهاز آخر',
        isRecoverable: true,
      );
    }

    // Generic error
    return AppwriteError(
      code: 'UNKNOWN_ERROR',
      message: 'حدث خطأ غير متوقع',
      details: error.toString(),
      isRecoverable: true,
    );
  }

  /// عرض الخطأ للمستخدم
  void showError(BuildContext context, AppwriteError error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.message,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (error.details != null) ...[
              const SizedBox(height: 4),
              Text(
                error.details!,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        backgroundColor: error.isRecoverable ? Colors.orange : Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'إغلاق',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  /// عرض Dialog للخطأ
  void showErrorDialog(BuildContext context, AppwriteError error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              error.isRecoverable ? Icons.warning : Icons.error,
              color: error.isRecoverable ? Colors.orange : Colors.red,
            ),
            const SizedBox(width: 8),
            const Text('خطأ'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.message,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (error.details != null) ...[
              const SizedBox(height: 12),
              Text(
                error.details!,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'الكود: ${error.code}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  /// الحصول على سجل الأخطاء
  List<AppwriteError> get errorHistory => List.unmodifiable(_errorHistory);

  /// الحصول على عدد الأخطاء
  int get errorCount => _errorHistory.length;

  /// الحصول على آخر خطأ
  AppwriteError? get lastError => _errorHistory.isNotEmpty ? _errorHistory.last : null;

  /// مسح سجل الأخطاء
  void clearHistory() {
    _errorHistory.clear();
  }

  /// الحصول على إحصائيات الأخطاء
  Map<String, int> getStatistics() {
    final stats = <String, int>{};
    for (final error in _errorHistory) {
      stats[error.code] = (stats[error.code] ?? 0) + 1;
    }
    return stats;
  }
}
