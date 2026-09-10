import 'dart:async';
import 'dart:math';
import '../../utils/debug_log.dart';

enum RetryBackoffType { linear, exponential, fibonacci }

/// ✅ P1: إحصائيات إعادة المحاولة لمثيل [RetryStrategy] — تُجمَع
/// تلقائياً عند كل تنفيذ، وتُعرض/تُصدَّر عبر [RetryStats.toMap].
class RetryStats {
  /// عدد مرات استدعاء execute (كل محاولة فردية تُحتسب).
  int attempts = 0;

  /// عدد المرات التي جدولت فيها إعادة محاولة (انتظار ثم محاولة جديدة).
  int retries = 0;

  /// عدد العمليات التي نجحت بعد محاولة فاشلة واحدة على الأقل.
  int successAfterRetry = 0;

  /// عدد المرات التي استُنفدت فيها كل المحاولات وفشلت العملية.
  int exhausted = 0;

  /// عدد الأخطاء غير القابلة لإعادة المحاولة (بسبب القائمة أو shouldRetry).
  int nonRetryable = 0;

  /// نص آخر خطأ رُصد.
  String? lastError;

  Map<String, dynamic> toMap() => {
    'attempts': attempts,
    'retries': retries,
    'successAfterRetry': successAfterRetry,
    'exhausted': exhausted,
    'nonRetryable': nonRetryable,
    'lastError': lastError,
  };

  /// تصفير الإحصائيات (للاختبارات أو بعد تصديرها).
  void reset() {
    attempts = 0;
    retries = 0;
    successAfterRetry = 0;
    exhausted = 0;
    nonRetryable = 0;
    lastError = null;
  }

  @override
  String toString() =>
      'RetryStats(attempts=$attempts, retries=$retries, '
      'successAfterRetry=$successAfterRetry, exhausted=$exhausted, '
      'nonRetryable=$nonRetryable)';
}

class RetryConfig {
  const RetryConfig({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.backoffType = RetryBackoffType.exponential,
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.1,
    this.retryableErrors = const <Type>[],
  });
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final RetryBackoffType backoffType;
  final double backoffMultiplier;
  final double jitterFactor;

  /// ✅ P1: قائمة أنواع الأخطاء القابلة لإعادة المحاولة (بوّابة صارمة).
  ///
  /// - القائمة فارغة (الافتراضي): السلوك القديم — [RetryStrategy.execute]
  ///   يعتمد فقط على دالة shouldRetry الممرّرة.
  /// - القائمة غير فارغة: الخطأ يجب أن يكون نوعه أحد الأنواع المذكورة
  ///   (مطابقة runtimeType) وإلا يُعاد رميه فوراً دون أي محاولة أخرى،
  ///   حتى لو أعادت shouldRetry true.
  ///
  /// مثال:
  /// ```dart
  /// RetryConfig(retryableErrors: [TimeoutException, SocketException])
  /// ```
  final List<Type> retryableErrors;

  static const conservative = RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 5),
    maxDelay: Duration(minutes: 2),
    backoffType: RetryBackoffType.linear,
  );

  static const aggressive = RetryConfig(
    maxAttempts: 10,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(minutes: 10),
    backoffMultiplier: 2.5,
  );

  static const balanced = RetryConfig(backoffType: RetryBackoffType.fibonacci);
}

class RetryStrategy {
  RetryStrategy({RetryConfig? config}) : config = config ?? const RetryConfig();
  final RetryConfig config;
  final Random _random = Random();

  /// ✅ P1: إحصائيات هذا المثيل — تُجمَع تلقائياً عند كل execute.
  final RetryStats stats = RetryStats();

  /// ✅ P1: هل الخطأ مقبول حسب قائمة retryableErrors؟
  /// قائمة فارغة تعني "البوّابة معطّلة" (السلوك القديم).
  bool _passesRetryableErrorsFilter(dynamic error) {
    if (config.retryableErrors.isEmpty) {
      return true;
    }
    return config.retryableErrors.contains(error.runtimeType);
  }

  Duration calculateDelay(int attemptNumber) {
    if (attemptNumber <= 0) {
      return Duration.zero;
    }

    Duration baseDelay;

    switch (config.backoffType) {
      case RetryBackoffType.linear:
        baseDelay = config.initialDelay * attemptNumber;

      case RetryBackoffType.exponential:
        // ✅ P1-12 fix: استخدام round() بدل toInt() لمنع بتر القيم
        final exponential = pow(config.backoffMultiplier, attemptNumber - 1);
        final delayMs = (config.initialDelay.inMilliseconds * exponential)
            .round();
        baseDelay = Duration(milliseconds: delayMs);

      case RetryBackoffType.fibonacci:
        final fib = _fibonacci(attemptNumber);
        baseDelay = config.initialDelay * fib;
    }

    if (baseDelay > config.maxDelay) {
      baseDelay = config.maxDelay;
    }

    final jitter = _calculateJitter(baseDelay);
    final finalDelay = baseDelay + jitter;

    return finalDelay;
  }

  Duration _calculateJitter(Duration baseDelay) {
    final jitterMs = baseDelay.inMilliseconds * config.jitterFactor;
    final randomJitter = (_random.nextDouble() * 2 - 1) * jitterMs;
    // ✅ P1-12 fix: استخدام round() بدل toInt()
    return Duration(milliseconds: randomJitter.round());
  }

  int _fibonacci(int n) {
    if (n <= 1) {
      return n;
    }
    int a = 0, b = 1;
    for (int i = 2; i <= n; i++) {
      final int temp = a + b;
      a = b;
      b = temp;
    }
    return b;
  }

  Future<T> execute<T>({
    required Future<T> Function() operation,
    required bool Function(dynamic error) shouldRetry,
    void Function(int attempt, dynamic error)? onRetry,
  }) async {
    int attempt = 0;
    dynamic lastError;

    while (attempt < config.maxAttempts) {
      attempt++;
      stats.attempts++;

      try {
        dlog(() => '🔄 [Retry] محاولة $attempt من ${config.maxAttempts}');
        final result = await operation();
        if (attempt > 1) {
          stats.successAfterRetry++;
        }
        return result;
      } catch (error) {
        lastError = error;
        stats.lastError = error.toString();
        dlog(() => '⚠️ [Retry] فشلت المحاولة $attempt: $error');

        // ✅ P1: بوّابة retryableErrors — الخطأ غير المذكور في القائمة
        // (عندما تكون غير فارغة) يُعاد رميه فوراً دون أي محاولة أخرى.
        if (!_passesRetryableErrorsFilter(error)) {
          stats.nonRetryable++;
          dlog(
            () =>
                '🚫 [Retry] نوع الخطأ ${error.runtimeType} غير مذكور في '
                'retryableErrors — إيقاف إعادة المحاولة فوراً',
          );
          rethrow;
        }

        if (!shouldRetry(error)) {
          stats.nonRetryable++;
          dlog('❌ [Retry] الخطأ غير قابل لإعادة المحاولة');
          rethrow;
        }

        if (attempt >= config.maxAttempts) {
          stats.exhausted++;
          dlog('❌ [Retry] تم تجاوز الحد الأقصى للمحاولات');
          rethrow;
        }

        final delay = calculateDelay(attempt);
        dlog(
          () =>
              '⏳ [Retry] انتظار ${delay.inSeconds} ثانية قبل المحاولة التالية',
        );

        if (onRetry != null) {
          onRetry(attempt, error);
        }

        stats.retries++;
        await Future<void>.delayed(delay);
      }
    }

    throw Exception(lastError.toString());
  }

  Future<T?> executeWithFallback<T>({
    required Future<T> Function() operation,
    required bool Function(dynamic error) shouldRetry,
    required T Function() fallback,
    void Function(int attempt, dynamic error)? onRetry,
  }) async {
    try {
      return await execute(
        operation: operation,
        shouldRetry: shouldRetry,
        onRetry: onRetry,
      );
    } catch (e) {
      dlog('🔄 [Retry] استخدام القيمة الاحتياطية بعد فشل جميع المحاولات');
      return fallback();
    }
  }
}
