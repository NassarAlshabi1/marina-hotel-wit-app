import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'appwrite_logger.dart';

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
  String toString() =>
      '[$code] $message${details != null ? '\nDetails: $details' : ''}';
}

class AppwriteErrorHandler {
  static final AppwriteErrorHandler _instance =
      AppwriteErrorHandler._internal();
  factory AppwriteErrorHandler() => _instance;
  AppwriteErrorHandler._internal();

  final _logger = AppwriteLogger();
  final List<AppwriteError> _errorHistory = [];
  static const int _maxHistorySize = 100;

  AppwriteError handleError(
    dynamic error, {
    String context = 'Unknown',
    StackTrace? stackTrace,
  }) {
    final appwriteError = _parseError(error, context);
    _errorHistory.add(appwriteError);
    if (_errorHistory.length > _maxHistorySize) {
      _errorHistory.removeRange(0, _errorHistory.length - _maxHistorySize);
    }

    _logger.error(
      '${appwriteError.message} (Context: $context)',
      error: error,
      stackTrace: stackTrace,
      tag: 'ERROR_HANDLER',
    );

    return appwriteError;
  }

  AppwriteError _parseError(dynamic error, String context) {
    if (error is AppwriteError) {
      return error;
    }

    if (error is AppwriteException) {
      return _parseAppwriteException(error);
    }

    final msg = error.toString();

    if (msg.contains('SocketException') ||
        msg.contains('HandshakeException') ||
        msg.contains('Connection refused') ||
        msg.contains('Network is unreachable')) {
      return AppwriteError(
        code: 'NETWORK_ERROR',
        message: 'فشل الاتصال بالشبكة',
        details: 'تحقق من اتصالك بالإنترنت وحاول مرة أخرى',
        isRecoverable: true,
      );
    }

    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return AppwriteError(
        code: 'TIMEOUT_ERROR',
        message: 'انتهت مهلة الاتصال',
        details: 'استغرق الطلب وقتاً طويلاً',
        isRecoverable: true,
      );
    }

    return AppwriteError(
      code: 'UNKNOWN_ERROR',
      message: 'حدث خطأ غير متوقع',
      details: msg,
      isRecoverable: true,
    );
  }

  AppwriteError _parseAppwriteException(AppwriteException e) {
    final code = e.code;
    final type = e.type ?? '';

    if (code == 401 || type.contains('unauthorized')) {
      return AppwriteError(
        code: 'AUTH_ERROR',
        message: 'خطأ في المصادقة',
        details: e.message,
        isRecoverable: true,
      );
    }

    if (code == 403 || type.contains('forbidden')) {
      return AppwriteError(
        code: 'PERMISSION_ERROR',
        message: 'لا تملك صلاحية للقيام بهذا الإجراء',
        details: e.message,
        isRecoverable: false,
      );
    }

    if (code == 404 || type.contains('not_found')) {
      return AppwriteError(
        code: 'NOT_FOUND',
        message: 'العنصر المطلوب غير موجود',
        details: e.message,
        isRecoverable: false,
      );
    }

    if (code == 409 || type.contains('conflict')) {
      return AppwriteError(
        code: 'CONFLICT_ERROR',
        message: 'تضارب في البيانات',
        details: 'تم تعديل البيانات من قبل جهاز آخر',
        isRecoverable: true,
      );
    }

    if (code == 429 || type.contains('rate_limit')) {
      return AppwriteError(
        code: 'RATE_LIMIT',
        message: 'تم تجاوز حد الطلبات',
        details: 'يرجى الانتظار قليلاً قبل المحاولة مرة أخرى',
        isRecoverable: true,
      );
    }

    if (code != null && code >= 500) {
      return AppwriteError(
        code: 'SERVER_ERROR',
        message: 'خطأ في الخادم',
        details: e.message,
        isRecoverable: true,
      );
    }

    return AppwriteError(
      code: 'APPWRITE_ERROR_${code ?? 'UNKNOWN'}',
      message: e.message ?? 'خطأ غير متوقع من Appwrite',
      details: 'type: $type',
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
              Text(error.details!, style: const TextStyle(fontSize: 12)),
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
  AppwriteError? get lastError =>
      _errorHistory.isNotEmpty ? _errorHistory.last : null;

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
