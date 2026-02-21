import 'dart:async';

/// Simple mutex for synchronizing async operations in sync managers.
/// Usage: mutex.runExclusive(() => yourAsyncOperation());
class SyncMutex {
  Completer<void>? _completer;
  bool _locked = false;

  Future<bool> acquire({Duration? timeout}) async {
    final startTime = DateTime.now();

    while (_locked) {
      if (timeout != null && DateTime.now().difference(startTime) > timeout) {
        return false;
      }

      try {
        if (timeout != null) {
          final remaining = timeout - DateTime.now().difference(startTime);
          if (remaining.isNegative) return false;
          await _completer!.future.timeout(remaining);
        } else {
          await _completer!.future;
        }
      } on TimeoutException {
        return false;
      }
    }

    _locked = true;
    _completer = Completer<void>();
    return true;
  }

  void release() {
    if (_locked) {
      _locked = false;
      _completer!.complete();
    }
  }

  /// Runs the action exclusively, acquiring lock before and releasing after.
  Future<T?> runExclusive<T>(
    Future<T> Function() action, {
    Duration? timeout,
  }) async {
    final acquired = await acquire(timeout: timeout);
    if (!acquired) return null;

    try {
      return await action();
    } finally {
      release();
    }
  }

  /// Alias for runExclusive to match some usage patterns
  Future<T?> protect<T>(
    Future<T> Function() action, {
    Duration? timeout,
  }) => runExclusive(action, timeout: timeout);
}
