import 'dart:async';
import 'dart:math';
import '../../utils/debug_log.dart';

enum RetryBackoffType { linear, exponential, fibonacci }

class RetryConfig {
  const RetryConfig({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.backoffType = RetryBackoffType.exponential,
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.1,
    this.retryableErrors = const <Type>[],
    this.retryableErrorTest,
  });
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final RetryBackoffType backoffType;
  final double backoffMultiplier;
  final double jitterFactor;

  /// ✅ P1 (تقرير 2026-09-11): قائمة أنواع الأخطاء القابلة لإعادة
  /// المحاولة. فارغة = كل الأخطاء قابلة (السلوك السابق تماماً — القرار
  /// يبقى لـ shouldRetry الخاص بالمتصل). غير فارغة = الخطأ يُعاد رفعه
  /// فوراً دون استهلاك محاولات إذا لم يطابق أي نوع.
  ///
  /// المطابقة بنوع runtimeType الدقيق — للتسلسلات الهرمية أو شروط أعمق
  /// استخدم [retryableErrorTest].
  final List<Type> retryableErrors;

  /// ✅ P1: مسند اختياري أعمق للتحكم في قابلية إعادة المحاولة — له
  /// الأولوية على [retryableErrors] عند تعيينه.
  final bool Function(dynamic error)? retryableErrorTest;

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

  // ✅ P1 (تقرير 2026-09-11): إحصائيات إعادة المحاولة لهذه النسخة.
  int _totalExecutions = 0;
  int _totalAttempts = 0;
  int _totalRetries = 0;
  int _totalExhausted = 0;
  int _totalBlockedByPolicy = 0;
  DateTime? _lastErrorAt;
  String? _lastErrorMessage;

  /// إجمالي عمليات execute المكتملة (نجاحاً أو فشلاً).
  int get totalExecutions => _totalExecutions;

  /// إجمالي المحاولات الفردية (المحاولة الأولى + إعادات المحاولة).
  int get totalAttempts => _totalAttempts;

  /// إجمالي مرات إعادة المحاولة المجدولة (بعد فشل قابل للإعادة).
  int get totalRetries => _totalRetries;

  /// إجمالي مرات استنفاد كل المحاولات دون نجاح.
  int get totalExhausted => _totalExhausted;

  /// إجمالي الأخطاء المرفوضة من سياسة الإعادة (رُفعت فوراً دون إعادة).
  int get totalBlockedByPolicy => _totalBlockedByPolicy;

  /// وقت آخر خطأ ورسالته.
  DateTime? get lastErrorAt => _lastErrorAt;
  String? get lastErrorMessage => _lastErrorMessage;

  /// لقطة إحصائية شاملة — للتشخيص والاختبارات.
  Map<String, dynamic> get stats => {
    'totalExecutions': _totalExecutions,
    'totalAttempts': _totalAttempts,
    'totalRetries': _totalRetries,
    'totalExhausted': _totalExhausted,
    'totalBlockedByPolicy': _totalBlockedByPolicy,
    'lastErrorAt': _lastErrorAt?.toIso8601String(),
    'lastErrorMessage': _lastErrorMessage,
    'maxAttempts': config.maxAttempts,
  };

  /// تصفير الإحصائيات (لا يمس التكوين).
  void resetStats() {
    _totalExecutions = 0;
    _totalAttempts = 0;
    _totalRetries = 0;
    _totalExhausted = 0;
    _totalBlockedByPolicy = 0;
    _lastErrorAt = null;
    _lastErrorMessage = null;
  }

  /// ✅ P1: هل هذا الخطأ قابل لإعادة المحاولة وفق سياسة التكوين؟
  ///
  /// - إذا عُيّن [RetryConfig.retryableErrorTest] فهو الحاكم حصرياً.
  /// - وإلا إذا كانت [RetryConfig.retryableErrors] فارغة: كل الأخطاء
  ///   قابلة (السلوك السابق).
  /// - وإلا: مطابقة runtimeType الدقيق ضد القائمة.
  bool isRetryableError(dynamic error) {
    final test = config.retryableErrorTest;
    if (test != null) {
      return test(error);
    }
    final types = config.retryableErrors;
    if (types.isEmpty) {
      return true;
    }
    return types.any((t) => error.runtimeType == t);
  }

  /// الجمع بين سياسة المتصل وسياسة التكوين — الاثنان معاً يجب أن يسمحا.
  bool shouldRetryError(
    dynamic error,
    bool Function(dynamic error) callerPolicy,
  ) {
    if (!callerPolicy(error)) {
      return false;
    }
    return isRetryableError(error);
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
    _totalExecutions++;

    while (attempt < config.maxAttempts) {
      attempt++;
      _totalAttempts++;

      try {
        dlog(() => '🔄 [Retry] محاولة $attempt من ${config.maxAttempts}');
        return await operation();
      } catch (error) {
        lastError = error;
        _lastErrorAt = DateTime.now();
        _lastErrorMessage = error.toString();
        dlog(() => '⚠️ [Retry] فشلت المحاولة $attempt: $error');

        if (!shouldRetry(error)) {
          dlog('❌ [Retry] الخطأ غير قابل لإعادة المحاولة');
          rethrow;
        }

        // ✅ P1: سياسة التكوين — الخطأ غير المدرج يُرفع فوراً دون
        // استهلاك باقي المحاولات أو انتظارات backoff.
        if (!isRetryableError(error)) {
          _totalBlockedByPolicy++;
          dlog(
            () =>
                '❌ [Retry] سياسة retryableErrors تمنع إعادة المحاولة '
                'للخطأ ${error.runtimeType}',
          );
          rethrow;
        }

        if (attempt >= config.maxAttempts) {
          _totalExhausted++;
          dlog('❌ [Retry] تم تجاوز الحد الأقصى للمحاولات');
          rethrow;
        }

        _totalRetries++;
        final delay = calculateDelay(attempt);
        dlog(
          () =>
              '⏳ [Retry] انتظار ${delay.inSeconds} ثانية قبل المحاولة التالية',
        );

        if (onRetry != null) {
          onRetry(attempt, error);
        }

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
