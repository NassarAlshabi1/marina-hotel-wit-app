import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

enum CircuitState { closed, open, halfOpen }

class CircuitBreakerConfig {

  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.timeout = const Duration(seconds: 30),
    this.resetTimeout = const Duration(minutes: 1),
    this.successThreshold = 2,
  });
  final int failureThreshold;
  final Duration timeout;
  final Duration resetTimeout;
  final int successThreshold;
}

class CircuitBreaker {

  CircuitBreaker({required this.name, CircuitBreakerConfig? config})
    : config = config ?? const CircuitBreakerConfig();
  final String name;
  final CircuitBreakerConfig config;

  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime? _lastFailureTime;
  Timer? _resetTimer;

  final _stateController = StreamController<CircuitState>.broadcast();
  Stream<CircuitState> get stateStream => _stateController.stream;

  CircuitState get state => _state;
  int get failureCount => _failureCount;
  int get successCount => _successCount;

  Future<T> execute<T>(Future<T> Function() operation) async {
    if (_state == CircuitState.open) {
      if (_shouldAttemptReset()) {
        _transitionTo(CircuitState.halfOpen);
      } else {
        throw CircuitBreakerOpenException(
          'Circuit breaker [$name] مفتوح - الخدمة غير متاحة مؤقتًا',
        );
      }
    }

    try {
      final result = await operation().timeout(config.timeout);
      _onSuccess();
      return result;
    } on TimeoutException catch (e) {
      _onFailure();
      throw CircuitBreakerTimeoutException(
        'Circuit breaker [$name] تجاوز المهلة الزمنية',
        originalException: e,
      );
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }

  Future<T?> executeSafe<T>(
    Future<T> Function() operation, {
    T? defaultValue,
  }) async {
    try {
      return await execute(operation);
    } on CircuitBreakerOpenException catch (e) {
      AppLogger.warning('⚠️ [CircuitBreaker] $e', tag: 'APP');
      return defaultValue;
    } catch (e) {
      AppLogger.warning('❌ [CircuitBreaker] خطأ: $e', tag: 'APP');
      return defaultValue;
    }
  }

  void _onSuccess() {
    _failureCount = 0;

    if (_state == CircuitState.halfOpen) {
      _successCount++;
      AppLogger.info(
  '✅ [CircuitBreaker] [$name] نجاح في halfOpen: $_successCount/${config.successThreshold}',,
  tag: 'APP',
);

      if (_successCount >= config.successThreshold) {
        _transitionTo(CircuitState.closed);
        _successCount = 0;
      }
    }
  }

  void _onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    _successCount = 0;

    AppLogger.warning(
  '⚠️ [CircuitBreaker] [$name] فشل: $_failureCount/${config.failureThreshold}',,
  tag: 'APP',
);

    if (_state == CircuitState.halfOpen) {
      _transitionTo(CircuitState.open);
    } else if (_failureCount >= config.failureThreshold) {
      _transitionTo(CircuitState.open);
    }
  }

  bool _shouldAttemptReset() {
    if (_lastFailureTime == null) {
      return false;
    }

    final timeSinceLastFailure = DateTime.now().difference(_lastFailureTime!);
    return timeSinceLastFailure >= config.resetTimeout;
  }

  void _transitionTo(CircuitState newState) {
    if (_state == newState) {
      return;
    }

    final oldState = _state;
    _state = newState;

    AppLogger.info('🔄 [CircuitBreaker] [$name] $oldState → $newState', tag: 'APP');

    _stateController.add(newState);

    if (newState == CircuitState.open) {
      _scheduleReset();
    } else if (newState == CircuitState.closed) {
      _cancelReset();
      _failureCount = 0;
      _successCount = 0;
    }
  }

  void _scheduleReset() {
    _cancelReset();
    _resetTimer = Timer(config.resetTimeout, () {
      if (_state == CircuitState.open) {
        AppLogger.info('⏰ [CircuitBreaker] [$name] محاولة إعادة الفتح تلقائيًا', tag: 'APP');
        _transitionTo(CircuitState.halfOpen);
      }
    });
  }

  void _cancelReset() {
    _resetTimer?.cancel();
    _resetTimer = null;
  }

  void reset() {
    AppLogger.info('🔄 [CircuitBreaker] [$name] إعادة تعيين يدوية', tag: 'APP');
    _failureCount = 0;
    _successCount = 0;
    _lastFailureTime = null;
    _transitionTo(CircuitState.closed);
  }

  Map<String, dynamic> getStatus() {
    return {
      'name': name,
      'state': _state.name,
      'failureCount': _failureCount,
      'successCount': _successCount,
      'lastFailureTime': _lastFailureTime?.toIso8601String(),
    };
  }

  void dispose() {
    _cancelReset();
    _stateController.close();
  }
}

class CircuitBreakerOpenException implements Exception {

  CircuitBreakerOpenException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CircuitBreakerTimeoutException implements Exception {

  CircuitBreakerTimeoutException(
    this.message, {
    required this.originalException,
  });
  final String message;
  final TimeoutException originalException;

  @override
  String toString() => message;
}
