import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import 'sync_constants.dart';

/// ✅ Circuit Breaker for sync operations.
///
/// After [failureThreshold] consecutive failures, stops attempting
/// sync for an exponentially increasing cooldown period.
/// Resets on any successful sync.
///
/// Prevents battery/data drain when the server is down — instead of
/// 12-24 failed attempts per hour, the breaker backs off:
/// 5m → 10m → 20m → 40m → 60m (max).
class SyncCircuitBreaker {
  SyncCircuitBreaker._();
  static final SyncCircuitBreaker instance = SyncCircuitBreaker._();

  int _consecutiveFailures = 0;
  DateTime? _lastFailureAt;
  bool _isOpen = false;

  bool get isOpen => _isOpen;
  int get consecutiveFailures => _consecutiveFailures;

  /// Exponential backoff: 5 → 10 → 20 → 40 → 60 (max)
  Duration get currentCooldown {
    if (_consecutiveFailures <= 0) return Duration.zero;
    final minutes = (5 * pow(2, min(_consecutiveFailures - 1, 3)))
        .toInt()
        .clamp(
          SyncConstants.circuitBreakerMinCooldownMinutes,
          SyncConstants.circuitBreakerMaxCooldownMinutes,
        );
    return Duration(minutes: minutes);
  }

  /// How long until the next attempt is allowed.
  Duration get timeUntilNextAttempt {
    if (!_isOpen || _lastFailureAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_lastFailureAt!);
    final remaining = currentCooldown - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void recordFailure() {
    _consecutiveFailures++;
    _lastFailureAt = DateTime.now();

    if (_consecutiveFailures >= SyncConstants.circuitBreakerFailureThreshold) {
      _isOpen = true;
      dwarn(
        () =>
            '🔴 Circuit breaker OPEN: $_consecutiveFailures failures, '
            'cooldown ${currentCooldown.inMinutes}m',
      );
    }
  }

  void reset() {
    if (_isOpen) {
      dlog(
        () =>
            '🟢 Circuit breaker CLOSED after successful sync '
            '(${_consecutiveFailures} failures resolved)',
      );
    }
    _consecutiveFailures = 0;
    _lastFailureAt = null;
    _isOpen = false;
  }

  /// Should we attempt a sync right now?
  bool shouldAttempt() {
    if (!_isOpen) return true;
    if (_lastFailureAt == null) return true;
    return DateTime.now().difference(_lastFailureAt!) >= currentCooldown;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('_cb_failures', _consecutiveFailures);
    await prefs.setInt(
      '_cb_last_failure',
      _lastFailureAt?.millisecondsSinceEpoch ?? 0,
    );
    await prefs.setBool('_cb_open', _isOpen);
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _consecutiveFailures = prefs.getInt('_cb_failures') ?? 0;
    final lastMs = prefs.getInt('_cb_last_failure') ?? 0;
    _lastFailureAt = lastMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(lastMs)
        : null;
    _isOpen = prefs.getBool('_cb_open') ?? false;

    // If the cooldown has elapsed since the last failure, close the breaker.
    if (_isOpen && !shouldAttempt()) {
      dlog(
        () => '🔄 Circuit breaker: cooldown elapsed during restore, closing',
      );
      reset();
    }
  }
}
