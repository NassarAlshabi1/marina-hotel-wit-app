import 'dart:async';
import 'dart:math';

/// واجهة استراتيجية إعادة المحاولة
abstract class RetryStrategy {
  /// تنفيذ عملية مع إعادة محاولة
  Future<T> execute<T>(Future<T> Function() operation);
}

/// استراتيجية Exponential Backoff
class ExponentialBackoffStrategy implements RetryStrategy {
  ExponentialBackoffStrategy({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(minutes: 5),
    this.backoffMultiplier = 2.0,
  });
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final double backoffMultiplier;

  @override
  Future<T> execute<T>(Future<T> Function() operation) async {
    int attempt = 0;
    Duration currentDelay = initialDelay;

    while (attempt < maxAttempts) {
      try {
        return await operation();
      } catch (e) {
        attempt++;

        if (attempt >= maxAttempts) {
          throw Exception('فشلت العملية بعد $maxAttempts محاولات: $e');
        }

        // إضافة jitter عشوائي لتجنب thundering herd
        final jitter = Random().nextInt(1000);
        final delayWithJitter = currentDelay + Duration(milliseconds: jitter);

        await Future.delayed(delayWithJitter);

        // زيادة المدة للمحاولة التالية
        currentDelay = Duration(
          milliseconds: min(
            (currentDelay.inMilliseconds * backoffMultiplier).toInt(),
            maxDelay.inMilliseconds,
          ),
        );
      }
    }

    throw Exception('وصلنا إلى نهاية الـ loop بدون نتيجة');
  }
}

/// استراتيجية Circuit Breaker
class CircuitBreakerStrategy implements RetryStrategy {
  CircuitBreakerStrategy({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(minutes: 1),
  });
  final int failureThreshold;
  final Duration resetTimeout;

  int _failureCount = 0;
  DateTime? _lastFailureTime;
  bool _isOpen = false;

  @override
  Future<T> execute<T>(Future<T> Function() operation) async {
    // التحقق من حالة Circuit Breaker
    if (_isOpen) {
      final timeSinceLastFailure = DateTime.now().difference(_lastFailureTime!);

      if (timeSinceLastFailure < resetTimeout) {
        throw Exception('Circuit Breaker مفتوح - المحاولة لاحقاً');
      }

      // إعادة المحاولة - نصف مغلق
      _isOpen = false;
    }

    try {
      final result = await operation();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }

  void _onSuccess() {
    _failureCount = 0;
    _isOpen = false;
  }

  void _onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();

    if (_failureCount >= failureThreshold) {
      _isOpen = true;
    }
  }

  bool get isOpen => _isOpen;
  bool get isClosed => !_isOpen;
}

/// استراتيجية Combined (Exponential Backoff + Circuit Breaker)
class CombinedRetryStrategy implements RetryStrategy {
  CombinedRetryStrategy({
    ExponentialBackoffStrategy? backoff,
    CircuitBreakerStrategy? circuitBreaker,
  }) : _backoff = backoff ?? ExponentialBackoffStrategy(),
       _circuitBreaker = circuitBreaker ?? CircuitBreakerStrategy();
  final ExponentialBackoffStrategy _backoff;
  final CircuitBreakerStrategy _circuitBreaker;

  @override
  Future<T> execute<T>(Future<T> Function() operation) async {
    return _circuitBreaker.execute(() async {
      return _backoff.execute(operation);
    });
  }

  bool get isCircuitOpen => _circuitBreaker.isOpen;
}
