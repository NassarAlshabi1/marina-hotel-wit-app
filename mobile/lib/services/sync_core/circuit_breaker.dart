// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
import 'dart:async';
import 'package:flutter/foundation.dart';

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

  // ✅ P1-9 fix: latch لمنع thundering herd في half-open
  bool _halfOpenProbeInFlight = false;

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

    // ✅ P1-9 fix: في half-open، اسمح بمسبار واحد فقط
    if (_state == CircuitState.halfOpen) {
      if (_halfOpenProbeInFlight) {
        throw CircuitBreakerOpenException(
          'Circuit breaker [$name] half-open — مسبار قيد التنفيذ',
        );
      }
      _halfOpenProbeInFlight = true;
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
    } finally {
      // ✅ P1-9: تحرير الـ latch
      _halfOpenProbeInFlight = false;
    }
  }

  Future<T?> executeSafe<T>(
    Future<T> Function() operation, {
    T? defaultValue,
  }) async {
    try {
      return await execute(operation);
    } on CircuitBreakerOpenException catch (e) {
      debugPrint('⚠️ [CircuitBreaker] $e');
      return defaultValue;
    } catch (e) {
      debugPrint('❌ [CircuitBreaker] خطأ: $e');
      return defaultValue;
    }
  }

  void _onSuccess() {
    _failureCount = 0;

    if (_state == CircuitState.halfOpen) {
      _successCount++;
      debugPrint(
        '✅ [CircuitBreaker] [$name] نجاح في halfOpen: $_successCount/${config.successThreshold}',
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

    debugPrint(
      '⚠️ [CircuitBreaker] [$name] فشل: $_failureCount/${config.failureThreshold}',
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

    debugPrint('🔄 [CircuitBreaker] [$name] $oldState → $newState');

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
        debugPrint('⏰ [CircuitBreaker] [$name] محاولة إعادة الفتح تلقائيًا');
        _transitionTo(CircuitState.halfOpen);
      }
    });
  }

  void _cancelReset() {
    _resetTimer?.cancel();
    _resetTimer = null;
  }

  void reset() {
    debugPrint('🔄 [CircuitBreaker] [$name] إعادة تعيين يدوية');
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
