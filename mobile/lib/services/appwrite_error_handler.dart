// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'appwrite_logger.dart';

class AppwriteError {
  AppwriteError({
    required this.code,
    required this.message,
    this.details,
    DateTime? timestamp,
    this.isRecoverable = true,
  }) : timestamp = timestamp ?? DateTime.now();
  final String code;
  final String message;
  final String? details;
  final DateTime timestamp;
  final bool isRecoverable;

  @override
  String toString() =>
      '[$code] $message${details != null ? '\nDetails: $details' : ''}';
}

class AppwriteErrorHandler {
  factory AppwriteErrorHandler() => _instance;
  AppwriteErrorHandler._internal();
  static final AppwriteErrorHandler _instance =
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

    // ✅ إصلاح (2026-06-28): كتم أخطاء 404 المتوقعة في تدفق upsert
    // 404 من updateDocument متوقع تماماً للسجلات الجديدة. upsert يلتقطه
    // داخلياً وينتقل إلى createDocument. لكن إذا تسرب الخطأ للـ catch
    // الخارجي (نادر)، لا نسجّله كـ ERROR لأنه يُسبب ضوضاء كبيرة.
    // نسجّله كـ DEBUG بدلاً من ذلك.
    final isExpected404 = _isExpectedNotFound(error, context);
    if (isExpected404) {
      _logger.debug(
        '${appwriteError.message} (Context: $context) — expected 404, suppressed',
        tag: 'ERROR_HANDLER',
      );
    } else {
      _logger.error(
        '${appwriteError.message} (Context: $context)',
        error: error,
        stackTrace: stackTrace,
        tag: 'ERROR_HANDLER',
      );
    }

    return appwriteError;
  }

  /// ✅ تحقق إذا كان الخطأ 404 متوقعاً في سياق upsert (push)
  /// في سياق push، 404 يعني أن السجل لم يُرفع للسحابة بعد — متوقع.
  bool _isExpectedNotFound(dynamic error, String context) {
    // سياقات push حيث upsert يُنتج 404 متوقع
    if (!context.startsWith('push:')) {
      return false;
    }

    // تحقق من نوع الخطأ
    if (error is AppwriteException) {
      final code = error.code;
      final type = (error.type ?? '').toLowerCase();
      if (code == 404 ||
          type.contains('document_not_found') ||
          type.contains('not_found')) {
        return true;
      }
    }

    final msg = error.toString().toLowerCase();
    if (msg.contains('404') ||
        msg.contains('document_not_found') ||
        msg.contains('not found')) {
      return true;
    }

    return false;
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
      );
    }

    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return AppwriteError(
        code: 'TIMEOUT_ERROR',
        message: 'انتهت مهلة الاتصال',
        details: 'استغرق الطلب وقتاً طويلاً',
      );
    }

    return AppwriteError(
      code: 'UNKNOWN_ERROR',
      message: 'حدث خطأ غير متوقع',
      details: msg,
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
      );
    }

    if (code == 429 || type.contains('rate_limit')) {
      return AppwriteError(
        code: 'RATE_LIMIT',
        message: 'تم تجاوز حد الطلبات',
        details: 'يرجى الانتظار قليلاً قبل المحاولة مرة أخرى',
      );
    }

    if (code != null && code >= 500) {
      return AppwriteError(
        code: 'SERVER_ERROR',
        message: 'خطأ في الخادم',
        details: e.message,
      );
    }

    return AppwriteError(
      code: 'APPWRITE_ERROR_${code ?? 'UNKNOWN'}',
      message: e.message ?? 'خطأ غير متوقع من Appwrite',
      details: 'type: $type',
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
      ),
    );
  }

  /// عرض Dialog للخطأ
  void showErrorDialog(BuildContext context, AppwriteError error) {
    showDialog<void>(
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
