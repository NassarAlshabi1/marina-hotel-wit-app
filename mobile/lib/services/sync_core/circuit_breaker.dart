import 'dart:async';
import '../../utils/debug_log.dart';

enum CircuitState { closed, open, halfOpen }

class CircuitBreakerConfig {
  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.timeout = const Duration(seconds: 30),
    this.resetTimeout = const Duration(minutes: 1),
    this.successThreshold = 2,
    this.halfOpenMaxAttempts = 3,
  });
  final int failureThreshold;
  final Duration timeout;
  final Duration resetTimeout;
  final int successThreshold;

  /// ✅ P1: أقصى عدد محاولات (تنفيذات) مسموح داخل حالة half-open قبل
  /// إجبار الدائرة على العودة إلى open. يمنع بقاء الدائرة في half-open
  /// للأبد إذا كان successThreshold غير قابل للبلوغ (سوء تكوين)
  /// أو تكرار دورات فتح/نصف-فتح المتذبذبة.
  ///
  /// مع الإعدادات الافتراضية (successThreshold=2) لا يُفعَّل هذا الحد
  /// أبداً في المسار الطبيعي: نجاحان يغلقان الدائرة، وأي فشل يعيدها
  /// إلى open مباشرة.
  final int halfOpenMaxAttempts;
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

  // ✅ P1-9 fix: latch لمنع thundering herd في half-open
  bool _halfOpenProbeInFlight = false;

  // ✅ P1: عدّاد التنفيذات داخل episode الحالي لـ half-open
  int _halfOpenExecutions = 0;

  // ✅ P1: سجل أوقات الانتقال بين الحالات (أحدث 20 انتقالاً)
  static const int _maxTransitionsLog = 20;
  final List<Map<String, dynamic>> _transitionsLog = <Map<String, dynamic>>[];
  DateTime? _lastTransitionAt;

  final _stateController = StreamController<CircuitState>.broadcast();
  Stream<CircuitState> get stateStream => _stateController.stream;

  CircuitState get state => _state;
  int get failureCount => _failureCount;
  int get successCount => _successCount;

  /// ✅ P1: عدد التنفيذات داخل episode half-open الحالي.
  int get halfOpenExecutions => _halfOpenExecutions;

  /// ✅ P1: وقت آخر انتقال بين الحالات (null إذا لم يحدث انتقال بعد).
  DateTime? get lastTransitionAt => _lastTransitionAt;

  /// ✅ P1: آخر انتقالات الحالة (من → إلى + الوقت) — للعرض في شاشات
  /// التشخيص. الأحدث أخيراً، بحد أقصى 20 سجلاً.
  List<Map<String, dynamic>> get recentTransitions =>
      List<Map<String, dynamic>>.unmodifiable(_transitionsLog);

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
      // ✅ P1: حد محاولات half-open — تجاوزه يعيد الدائرة إلى open
      // فوراً بدلاً من البقاء في half-open إلى ما لا نهاية.
      _halfOpenExecutions++;
      if (_halfOpenExecutions > config.halfOpenMaxAttempts) {
        dlog(
          () =>
              '⛔ [CircuitBreaker] [$name] تجاوز حد محاولات half-open '
              '(${config.halfOpenMaxAttempts}) — العودة إلى open',
        );
        _transitionTo(CircuitState.open);
        throw CircuitBreakerOpenException(
          'Circuit breaker [$name] تجاوز حد محاولات half-open '
          '(${config.halfOpenMaxAttempts})',
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

    dlog(() => '🔄 [CircuitBreaker] [$name] $oldState → $newState');

    // ✅ P1: تسجيل وقت الانتقال بين الحالات
    _lastTransitionAt = DateTime.now();
    _transitionsLog.add({
      'from': oldState.name,
      'to': newState.name,
      'at': _lastTransitionAt!.toIso8601String(),
    });
    if (_transitionsLog.length > _maxTransitionsLog) {
      _transitionsLog.removeAt(0);
    }

    _stateController.add(newState);

    if (newState == CircuitState.open) {
      _halfOpenExecutions = 0;
      _scheduleReset();
    } else if (newState == CircuitState.closed) {
      _halfOpenExecutions = 0;
      _cancelReset();
      _failureCount = 0;
      _successCount = 0;
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
    _lastFailureTime = null;
    _halfOpenExecutions = 0;
    _transitionTo(CircuitState.closed);
  }

  Map<String, dynamic> getStatus() {
    return {
      'name': name,
      'state': _state.name,
      'failureCount': _failureCount,
      'successCount': _successCount,
      'lastFailureTime': _lastFailureTime?.toIso8601String(),
      // ✅ P1: حقول المراقبة الجديدة
      'halfOpenExecutions': _halfOpenExecutions,
      'halfOpenMaxAttempts': config.halfOpenMaxAttempts,
      'lastTransitionAt': _lastTransitionAt?.toIso8601String(),
      'recentTransitions': List<Map<String, dynamic>>.from(_transitionsLog),
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
