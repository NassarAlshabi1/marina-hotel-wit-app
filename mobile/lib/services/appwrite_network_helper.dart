import 'dart:async';

import 'package:appwrite/appwrite.dart' show AppwriteException;

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

        await Future<void>.delayed(waitTime);
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
  ///
  /// ✅ إصلاح حرج (2026-06-26): الفحص القديم كان يعتمد على errorStr.contains('timeout')
  /// مما يُطابق stack trace الذي يحوي "withTimeout" و "TimeoutException" دائماً!
  /// النتيجة: 404 من Appwrite كان يُعتبر retriable فيُعاد 3 مرات بلا فائدة.
  ///
  /// الآن نفحص AppwriteException.code مباشرة (int) بدلاً من البحث في النص.
  /// فقط 5xx و 429 قابلة لإعادة المحاولة. 4xx (بما فيها 404) غير قابلة.
  bool _isRetriableError(dynamic error) {
    // ✅ فحص AppwriteException مباشرة عبر code (int)
    // هذا يتجنب مطابقة stack trace العشوائية.
    if (error is AppwriteException) {
      final code = error.code;
      // 429 = Too Many Requests (قابل لإعادة المحاولة)
      if (code == 429) return true;
      // 5xx = أخطاء الخادم (قابلة لإعادة المحاولة)
      if (code != null && code >= 500 && code < 600) return true;
      // باقي أخطاء Appwrite (4xx بما فيها 400/401/403/404/409) غير قابلة
      return false;
    }

    // ✅ TimeoutException الحقيقية (من Dart، وليست stack trace)
    if (error is TimeoutException) {
      return true;
    }

    // ✅ أخطاء الشبكة (نصية فقط بعد استبعاد AppwriteException)
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('socketexception') ||
        errorStr.contains('handshakeexception') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('connection reset') ||
        errorStr.contains('network is unreachable') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('connection timed out')) {
      return true;
    }

    // باقي الأخطاء غير قابلة لإعادة المحاولة
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
