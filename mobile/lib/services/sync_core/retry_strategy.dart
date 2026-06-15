import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

enum RetryBackoffType { linear, exponential, fibonacci }

class RetryConfig {

  const RetryConfig({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.backoffType = RetryBackoffType.exponential,
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.1,
  });
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final RetryBackoffType backoffType;
  final double backoffMultiplier;
  final double jitterFactor;

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

  static const balanced = RetryConfig(
    backoffType: RetryBackoffType.fibonacci,
  );
}

class RetryStrategy {

  RetryStrategy({RetryConfig? config}) : config = config ?? const RetryConfig();
  final RetryConfig config;
  final Random _random = Random();

  Duration calculateDelay(int attemptNumber) {
    if (attemptNumber <= 0) {
      return Duration.zero;
    }

    Duration baseDelay;

    switch (config.backoffType) {
      case RetryBackoffType.linear:
        baseDelay = config.initialDelay * attemptNumber;

      case RetryBackoffType.exponential:
        final exponential = pow(config.backoffMultiplier, attemptNumber - 1);
        baseDelay = config.initialDelay * exponential.toInt();

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
    return Duration(milliseconds: randomJitter.toInt());
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

      try {
        AppLogger.info('🔄 [Retry] محاولة $attempt من ${config.maxAttempts}', tag: 'APP');
        return await operation();
      } catch (error) {
        lastError = error;
        AppLogger.warning('⚠️ [Retry] فشلت المحاولة $attempt: $error', tag: 'APP');

        if (!shouldRetry(error)) {
          AppLogger.warning('❌ [Retry] الخطأ غير قابل لإعادة المحاولة', tag: 'APP');
          rethrow;
        }

        if (attempt >= config.maxAttempts) {
          AppLogger.error('❌ [Retry] تم تجاوز الحد الأقصى للمحاولات', tag: 'APP');
          rethrow;
        }

        final delay = calculateDelay(attempt);
        AppLogger.info(
  '⏳ [Retry] انتظار ${delay.inSeconds} ثانية قبل المحاولة التالية',,
  tag: 'APP',
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
      AppLogger.warning('🔄 [Retry] استخدام القيمة الاحتياطية بعد فشل جميع المحاولات', tag: 'APP');
      return fallback();
    }
  }
}
