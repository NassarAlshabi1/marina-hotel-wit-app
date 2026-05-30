import 'dart:async';

/// Rate Limiter for Appwrite API calls to prevent exceeding rate limits.
///
/// Appwrite Cloud has limits on requests per minute.
/// This class implements a token bucket algorithm for rate limiting.
class SyncRateLimiter {
  /// Maximum requests per minute (Appwrite Cloud default)
  static const int maxRequestsPerMinute = 60;

  /// Window duration for rate limiting
  static const Duration windowDuration = Duration(minutes: 1);

  /// Maximum burst size (requests allowed at once)
  static const int burstSize = 10;

  /// Singleton instance
  static final SyncRateLimiter _instance = SyncRateLimiter._internal();
  factory SyncRateLimiter() => _instance;
  SyncRateLimiter._internal();

  /// Request counters per endpoint type
  final Map<String, List<DateTime>> _requestLog = {};

  /// Lock for thread safety
  final _lock = SyncLock();

  /// Statistics
  int totalRequests = 0;
  int totalRejected = 0;
  DateTime? lastResetTime;

  /// Check if a request can be made (returns true if allowed)
  bool canMakeRequest({String? endpoint}) {
    return _lock.synchronized(() {
      final key = endpoint ?? 'default';
      final now = DateTime.now();
      final windowStart = now.subtract(windowDuration);

      // Initialize or clean old entries
      _requestLog[key] ??= [];
      _requestLog[key]!.removeWhere((dt) => dt.isBefore(windowStart));

      // Check if limit exceeded
      if (_requestLog[key]!.length >= maxRequestsPerMinute) {
        totalRejected++;
        return false;
      }

      return true;
    });
  }

  /// Record a request
  void recordRequest({String? endpoint}) {
    _lock.synchronized(() {
      final key = endpoint ?? 'default';
      final now = DateTime.now();

      _requestLog[key] ??= [];
      _requestLog[key]!.add(now);
      totalRequests++;

      // Clean old entries
      final windowStart = now.subtract(windowDuration);
      _requestLog[key]!.removeWhere((dt) => dt.isBefore(windowStart));
    });
  }

  /// Wait until a request can be made
  Future<bool> waitForSlot({String? endpoint, Duration? timeout}) async {
    final startTime = DateTime.now();
    final maxWait = timeout ?? const Duration(seconds: 30);

    while (true) {
      if (canMakeRequest(endpoint: endpoint)) {
        return true;
      }

      if (DateTime.now().difference(startTime) > maxWait) {
        return false;
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Execute a rate-limited operation
  Future<T> execute<T>({
    required Future<T> Function() operation,
    String? endpoint,
    Duration? timeout,
  }) async {
    // Wait for slot
    final hasSlot = await waitForSlot(endpoint: endpoint, timeout: timeout);
    if (!hasSlot) {
      throw RateLimitException('Rate limit timeout exceeded');
    }

    // Record and execute
    recordRequest(endpoint: endpoint);
    return operation();
  }

  /// Get current usage for an endpoint
  int getCurrentUsage({String? endpoint}) {
    return _lock.synchronized(() {
      final key = endpoint ?? 'default';
      final now = DateTime.now();
      final windowStart = now.subtract(windowDuration);

      _requestLog[key] ??= [];
      _requestLog[key]!.removeWhere((dt) => dt.isBefore(windowStart));

      return _requestLog[key]!.length;
    });
  }

  /// Get remaining requests
  int getRemainingRequests({String? endpoint}) {
    return maxRequestsPerMinute - getCurrentUsage(endpoint: endpoint);
  }

  /// Reset all counters
  void reset() {
    _lock.synchronized(() {
      _requestLog.clear();
      totalRequests = 0;
      totalRejected = 0;
      lastResetTime = DateTime.now();
    });
  }

  /// Get statistics
  Map<String, dynamic> getStats() {
    return _lock.synchronized(() {
      return {
        'totalRequests': totalRequests,
        'totalRejected': totalRejected,
        'lastResetTime': lastResetTime?.toIso8601String(),
        'usageByEndpoint': {
          for (final key in _requestLog.keys) key: getCurrentUsage(endpoint: key)
        },
      };
    });
  }

  /// Periodic cleanup timer
  Timer? _cleanupTimer;

  /// Start periodic cleanup
  void startCleanup({Duration interval = const Duration(minutes: 5)}) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(interval, (_) {
      _lock.synchronized(() {
        final now = DateTime.now();
        final windowStart = now.subtract(windowDuration);

        for (final key in _requestLog.keys) {
          _requestLog[key]!.removeWhere((dt) => dt.isBefore(windowStart));
        }
      });
    });
  }

  /// Stop cleanup timer
  void stopCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  /// Dispose
  void dispose() {
    stopCleanup();
    reset();
  }
}

/// Exception thrown when rate limit is exceeded
class RateLimitException implements Exception {
  final String message;
  RateLimitException(this.message);

  @override
  String toString() => 'RateLimitException: $message';
}

/// Simple sync lock for thread safety
class SyncLock {
  bool _isLocked = false;

  T synchronized<T>(T Function() fn) {
    while (_isLocked) {
      // Busy wait - in production, use a proper lock
    }
    _isLocked = true;
    try {
      return fn();
    } finally {
      _isLocked = false;
    }
  }
}