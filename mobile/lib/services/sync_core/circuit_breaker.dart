import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../utils/debug_log.dart';

enum CircuitState { closed, open, halfOpen }

/// ✅ P1 (تقرير 2026-09-11): انتقال حالة مختوم زمنياً — يُسجَّل في
/// سجل محدود داخل قاطع الدائرة لأغراض التشخيص والمراقبة.
@immutable
class CircuitTransition {
  const CircuitTransition({
    required this.from,
    required this.to,
    required this.at,
  });

  final CircuitState from;
  final CircuitState to;
  final DateTime at;

  @override
  String toString() => '$from → $to @ ${at.toIso8601String()}';
}

class CircuitBreakerConfig {
  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.timeout = const Duration(seconds: 30),
    this.resetTimeout = const Duration(minutes: 1),
    this.successThreshold = 2,
    this.halfOpenMaxConsecutiveFailures = 1,
    this.maxTransitionHistory = 20,
  });
  final int failureThreshold;
  final Duration timeout;
  final Duration resetTimeout;
  final int successThreshold;

  /// ✅ P1: أقصى عدد للإخفاقات المتتالية المسموح في half-open قبل
  /// العودة إلى open. الافتراضي 1 = السلوك السابق تماماً (أي فشل في
  /// المسبار يعيد الفتح). قيمة أكبر تسمح بعدة محاولات مسبار متتالية
  /// قبل الاستسلام — مفيدة عند شبكات متقلبة تعطي نجاحاً متقطعاً.
  final int halfOpenMaxConsecutiveFailures;

  /// أقصى حجم لسجل انتقالات الحالة (الأقدم يُحذف أولاً).
  final int maxTransitionHistory;
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

  // ✅ P1 (تقرير 2026-09-11): مراقبة half-open وسجل الانتقالات.
  int _halfOpenConsecutiveFailures = 0;
  int _transitionCount = 0;
  DateTime? _lastStateChangeAt;
  final List<CircuitTransition> _transitions = <CircuitTransition>[];

  final _stateController = StreamController<CircuitState>.broadcast();
  Stream<CircuitState> get stateStream => _stateController.stream;

  CircuitState get state => _state;
  int get failureCount => _failureCount;
  int get successCount => _successCount;

  /// ✅ P1: الإخفاقات المتتالية الحالية في half-open.
  int get halfOpenConsecutiveFailures => _halfOpenConsecutiveFailures;

  /// ✅ P1: وقت آخر انتقال حالة (أو null إذا لم يحدث انتقال بعد).
  DateTime? get lastStateChangeAt => _lastStateChangeAt;

  /// ✅ P1: إجمالي عدد انتقالات الحالة منذ الإنشاء/آخر reset.
  int get transitionCount => _transitionCount;

  /// ✅ P1: سجل الانتقالات الأخيرة (الأقدم أولاً، محدود بـ
  /// [CircuitBreakerConfig.maxTransitionHistory]).
  List<CircuitTransition> get transitions =>
      List<CircuitTransition>.unmodifiable(_transitions);

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
      dlog(() => '⚠️ [CircuitBreaker] $e');
      return defaultValue;
    } catch (e) {
      dlog(() => '❌ [CircuitBreaker] خطأ: $e');
      return defaultValue;
    }
  }

  void _onSuccess() {
    _failureCount = 0;

    if (_state == CircuitState.halfOpen) {
      _successCount++;
      // ✅ P1: نجاح المسبار يصفّر عدّاد الإخفاقات المتتالية.
      _halfOpenConsecutiveFailures = 0;
      dlog(
        () =>
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

    dlog(
      () =>
          '⚠️ [CircuitBreaker] [$name] فشل: $_failureCount/${config.failureThreshold}',
    );

    if (_state == CircuitState.halfOpen) {
      // ✅ P1: عتبة الإخفاقات المتتالية في half-open — الافتراضي 1
      // يحافظ على السلوك السابق (فشل واحد = إعادة الفتح).
      _halfOpenConsecutiveFailures++;
      if (_halfOpenConsecutiveFailures >=
          config.halfOpenMaxConsecutiveFailures) {
        _halfOpenConsecutiveFailures = 0;
        _transitionTo(CircuitState.open);
      } else {
        dlog(
          () =>
              '⚠️ [CircuitBreaker] [$name] فشل مسبار half-open '
              '($_halfOpenConsecutiveFailures/${config.halfOpenMaxConsecutiveFailures})',
        );
      }
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

    // ✅ P1: ختم زمني + سجل محدود لكل انتقال حالة.
    _lastStateChangeAt = DateTime.now();
    _transitionCount++;
    _transitions.add(
      CircuitTransition(from: oldState, to: newState, at: _lastStateChangeAt!),
    );
    while (_transitions.length > config.maxTransitionHistory) {
      _transitions.removeAt(0);
    }

    dlog(() => '🔄 [CircuitBreaker] [$name] $oldState → $newState');

    _stateController.add(newState);

    if (newState == CircuitState.open) {
      _scheduleReset();
    } else if (newState == CircuitState.closed) {
      _cancelReset();
      _failureCount = 0;
      _successCount = 0;
      _halfOpenConsecutiveFailures = 0;
    }
  }

  void _scheduleReset() {
    _cancelReset();
    _resetTimer = Timer(config.resetTimeout, () {
      if (_state == CircuitState.open) {
        dlog(() => '⏰ [CircuitBreaker] [$name] محاولة إعادة الفتح تلقائيًا');
        _transitionTo(CircuitState.halfOpen);
      }
    });
  }

  void _cancelReset() {
    _resetTimer?.cancel();
    _resetTimer = null;
  }

  void reset() {
    dlog(() => '🔄 [CircuitBreaker] [$name] إعادة تعيين يدوية');
    _failureCount = 0;
    _successCount = 0;
    _halfOpenConsecutiveFailures = 0;
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
      // ✅ P1: مراقبة الانتقالات وhalf-open.
      'lastStateChangeAt': _lastStateChangeAt?.toIso8601String(),
      'transitionCount': _transitionCount,
      'halfOpenConsecutiveFailures': _halfOpenConsecutiveFailures,
      'recentTransitions': [
        for (final t in _transitions) t.toString(),
      ],
    };
  }

  void dispose() {
    _cancelReset();
    unawaited(_stateController.close());
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
