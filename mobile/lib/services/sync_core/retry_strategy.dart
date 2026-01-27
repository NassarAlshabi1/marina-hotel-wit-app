import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

enum RetryBackoffType {
  linear,
  exponential,
  fibonacci,
}

class RetryConfig {
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final RetryBackoffType backoffType;
  final double backoffMultiplier;
  final double jitterFactor;

  const RetryConfig({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.backoffType = RetryBackoffType.exponential,
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.1,
  });

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
    backoffType: RetryBackoffType.exponential,
    backoffMultiplier: 2.5,
  );

  static const balanced = RetryConfig(
    maxAttempts: 5,
    initialDelay: Duration(seconds: 2),
    maxDelay: Duration(minutes: 5),
    backoffType: RetryBackoffType.fibonacci,
  );
}

class RetryStrategy {
  final RetryConfig config;
  final Random _random = Random();

  RetryStrategy({RetryConfig? config}) : config = config ?? const RetryConfig();

  Duration calculateDelay(int attemptNumber) {
    if (attemptNumber <= 0) return Duration.zero;

    Duration baseDelay;

    switch (config.backoffType) {
      case RetryBackoffType.linear:
        baseDelay = config.initialDelay * attemptNumber;
        break;

      case RetryBackoffType.exponential:
        final exponential = pow(config.backoffMultiplier, attemptNumber - 1);
        baseDelay = config.initialDelay * exponential.toInt();
        break;

      case RetryBackoffType.fibonacci:
        final fib = _fibonacci(attemptNumber);
        baseDelay = config.initialDelay * fib;
        break;
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
    return Duration(milliseconds: randomJitter.toInt());
  }

  int _fibonacci(int n) {
    if (n <= 1) return n;
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

      try {
        debugPrint('🔄 [Retry] محاولة $attempt من ${config.maxAttempts}');
        return await operation();
      } catch (error) {
        lastError = error;
        debugPrint('⚠️ [Retry] فشلت المحاولة $attempt: $error');

        if (!shouldRetry(error)) {
          debugPrint('❌ [Retry] الخطأ غير قابل لإعادة المحاولة');
          rethrow;
        }

        if (attempt >= config.maxAttempts) {
          debugPrint('❌ [Retry] تم تجاوز الحد الأقصى للمحاولات');
          rethrow;
        }

        final delay = calculateDelay(attempt);
        debugPrint(
            '⏳ [Retry] انتظار ${delay.inSeconds} ثانية قبل المحاولة التالية');

        if (onRetry != null) {
          onRetry(attempt, error);
        }

        await Future.delayed(delay);
      }
    }

    throw lastError ?? Exception('فشلت جميع المحاولات');
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
    } catch (error) {
      debugPrint('🔄 [Retry] استخدام القيمة الاحتياطية بعد فشل جميع المحاولات');
      return fallback();
    }
  }
}
