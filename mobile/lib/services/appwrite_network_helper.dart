import 'dart:async';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';

/// مساعد للعمليات الشبكية مع Retry Logic و Timeout
class AppwriteNetworkHelper {
  factory AppwriteNetworkHelper() => _instance;
  AppwriteNetworkHelper._internal();
  static final AppwriteNetworkHelper _instance =
      AppwriteNetworkHelper._internal();

  final _logger = AppwriteLogger();

  /// تنفيذ عملية مع Retry Logic (Exponential Backoff)
  ///
  /// [operation] - الدالة المراد تنفيذها
  /// [maxRetries] - عدد المحاولات القصوى (افتراضي: 3)
  /// [initialDelay] - التأخير الأولي (افتراضي: 2 ثانية)
  /// [backoffMultiplier] - معامل التضاعف (افتراضي: 2.0)
  /// [operationName] - اسم العملية للتسجيل
  Future<T> withRetry<T>({
    required Future<T> Function() operation,
    int? maxRetries,
    Duration? initialDelay,
    double? backoffMultiplier,
    String? operationName,
  }) async {
    final retries = maxRetries ?? AppwriteConfig.maxRetries;
    final delay = initialDelay ?? AppwriteConfig.initialRetryDelay;
    final multiplier =
        backoffMultiplier ?? AppwriteConfig.retryBackoffMultiplier;
    final opName = operationName ?? 'Operation';

    int attempt = 0;
    Duration currentDelay = delay;

    while (true) {
      attempt++;

      try {
        _logger.debug('$opName - Attempt $attempt/$retries', tag: 'RETRY');
        return await operation();
      } catch (e) {
        // التحقق من نوع الخطأ - هل قابل لإعادة المحاولة؟
        if (!_isRetriableError(e)) {
          _logger.warning('$opName - Non-retriable error: $e', tag: 'RETRY');
          rethrow;
        }

        // إذا وصلنا للحد الأقصى من المحاولات
        if (attempt >= retries) {
          _logger.error(
            '$opName - Max retries ($retries) reached',
            error: e,
            tag: 'RETRY',
          );
          rethrow;
        }

        // حساب وقت الانتظار (Exponential Backoff)
        final waitTime = currentDelay;
        _logger.warning(
          '$opName - Attempt $attempt failed, retrying in ${waitTime.inSeconds}s... Error: $e',
          tag: 'RETRY',
        );

        await Future.delayed(waitTime);
        currentDelay = Duration(
          milliseconds: (currentDelay.inMilliseconds * multiplier).round(),
        );
      }
    }
  }

  /// تنفيذ عملية مع Timeout
  ///
  /// [operation] - الدالة المراد تنفيذها
  /// [timeout] - المدة القصوى للانتظار
  /// [operationName] - اسم العملية للتسجيل
  Future<T> withTimeout<T>({
    required Future<T> Function() operation,
    Duration? timeout,
    String? operationName,
  }) async {
    final maxDuration = timeout ?? AppwriteConfig.defaultTimeout;
    final opName = operationName ?? 'Operation';

    try {
      _logger.debug(
        '$opName - Starting with ${maxDuration.inSeconds}s timeout',
        tag: 'TIMEOUT',
      );

      return await operation().timeout(
        maxDuration,
        onTimeout: () {
          _logger.error(
            '$opName - Timeout after ${maxDuration.inSeconds}s',
            tag: 'TIMEOUT',
          );
          throw TimeoutException(
            '$opName تجاوز الوقت المحدد (${maxDuration.inSeconds} ثانية)',
          );
        },
      );
    } catch (e) {
      if (e is TimeoutException) {
        rethrow;
      }
      _logger.error('$opName - Failed: $e', error: e, tag: 'TIMEOUT');
      rethrow;
    }
  }

  /// تنفيذ عملية مع كل من Retry و Timeout
  ///
  /// [operation] - الدالة المراد تنفيذها
  /// [maxRetries] - عدد المحاولات القصوى
  /// [timeout] - المدة القصوى للانتظار لكل محاولة
  /// [operationName] - اسم العملية للتسجيل
  Future<T> withRetryAndTimeout<T>({
    required Future<T> Function() operation,
    int? maxRetries,
    Duration? timeout,
    String? operationName,
  }) async {
    return withRetry(
      operation: () => withTimeout(
        operation: operation,
        timeout: timeout,
        operationName: operationName,
      ),
      maxRetries: maxRetries,
      operationName: operationName,
    );
  }

  /// التحقق من أن الخطأ قابل لإعادة المحاولة
  bool _isRetriableError(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // أخطاء الشبكة القابلة لإعادة المحاولة
    if (errorStr.contains('network') ||
        errorStr.contains('connection') ||
        errorStr.contains('socket') ||
        errorStr.contains('timeout') ||
        errorStr.contains('failed host lookup')) {
      return true;
    }

    // أخطاء HTTP القابلة لإعادة المحاولة
    if (errorStr.contains('500') || // Internal Server Error
        errorStr.contains('502') || // Bad Gateway
        errorStr.contains('503') || // Service Unavailable
        errorStr.contains('504') || // Gateway Timeout
        errorStr.contains('429')) {
      // Too Many Requests
      return true;
    }

    // أخطاء Appwrite المؤقتة
    if (errorStr.contains('rate limit') ||
        errorStr.contains('server_error') ||
        errorStr.contains('service_unavailable')) {
      return true;
    }

    // أخطاء Appwrite 404 (document_not_found) غير قابلة لإعادة المحاولة
    if (errorStr.contains('404') || errorStr.contains('document_not_found')) {
      return false;
    }

    // باقي الأخطاء غير قابلة لإعادة المحاولة (مثل 401, 403)
    return false;
  }

  /// حساب وقت الانتظار بناءً على Exponential Backoff مع Jitter
  ///
  /// [attempt] - رقم المحاولة
  /// [baseDelay] - التأخير الأساسي
  /// [multiplier] - معامل التضاعف
  /// [addJitter] - إضافة تذبذب عشوائي (يساعد في تقليل التصادمات)
  Duration calculateBackoff({
    required int attempt,
    Duration? baseDelay,
    double? multiplier,
    bool addJitter = true,
  }) {
    final base = baseDelay ?? AppwriteConfig.initialRetryDelay;
    final mult = multiplier ?? AppwriteConfig.retryBackoffMultiplier;

    // Exponential backoff: delay = baseDelay * (multiplier ^ attempt)
    final exponentialDelay = base.inMilliseconds * (mult * attempt);

    // إضافة jitter (تذبذب عشوائي بين 0-20%)
    if (addJitter) {
      final jitter =
          exponentialDelay *
          0.2 *
          (0.5 + (DateTime.now().millisecond % 100) / 100);
      return Duration(milliseconds: (exponentialDelay + jitter).round());
    }

    return Duration(milliseconds: exponentialDelay.round());
  }
}
