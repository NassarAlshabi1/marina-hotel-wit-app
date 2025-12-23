import 'dart:async';

/// Simple mutex for synchronizing async operations in sync managers.
/// Usage: mutex.runExclusive(() => yourAsyncOperation());
class SyncMutex {
  Completer<void>? _completer;
  bool _locked = false;

  Future<void> acquire() async {
    while (_locked) {
      await _completer!.future;
    }
    _locked = true;
    _completer = Completer<void>();
  }

  void release() {
    if (_locked) {
      _locked = false;
      _completer!.complete();
    }
  }

  /// Runs the action exclusively, acquiring lock before and releasing after.
  Future<T> runExclusive<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }
}
