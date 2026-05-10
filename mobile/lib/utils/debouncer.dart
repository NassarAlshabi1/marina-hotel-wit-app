import 'dart:async';

/// Debouncer utility for search fields and rapid updates
class Debouncer {
  Debouncer({this.milliseconds = 300});

  final int milliseconds;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void cancel() {
    _timer?.cancel();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Throttler for limiting call frequency
class Throttler {
  Throttler({this.milliseconds = 1000});

  final int milliseconds;
  DateTime? _lastCall;

  void run(void Function() action) {
    final now = DateTime.now();
    if (_lastCall == null ||
        now.difference(_lastCall!).inMilliseconds >= milliseconds) {
      _lastCall = now;
      action();
    }
  }
}

/// Rate limiter for API calls
class RateLimiter {
  RateLimiter({required this.maxCalls, required this.perDuration});

  final int maxCalls;
  final Duration perDuration;
  final List<DateTime> _calls = [];

  bool get canCall {
    final now = DateTime.now();
    _calls.removeWhere(
      (t) => now.difference(t).inMilliseconds > perDuration.inMilliseconds,
    );
    return _calls.length < maxCalls;
  }

  void recordCall() {
    _calls.add(DateTime.now());
  }

  Future<void> waitIfNeeded() async {
    while (!canCall) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    recordCall();
  }
}
