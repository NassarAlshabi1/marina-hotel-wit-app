import 'dart:async';

/// Simple mutex for synchronizing async operations in sync managers.
/// Usage: mutex.runExclusive(() => yourAsyncOperation());
class SyncMutex {
  Completer<void>? _completer;
  bool _locked = false;

  Future<void> acquire() async {
    if (_locked) {
      await _completer!.future;
    }
  }

  /// Runs the action exclusively, acquiring lock before and releasing after.
  Future&lt;T&gt; runExclusive&lt;T&gt;(Future&lt;T&gt; Function() action) async {
    await acquire();
    final completerLocal = Completer&lt;void&gt;();
    _completer = completerLocal;
    _locked = true;
    try {
      return await action();
    } finally {
      _locked = false;
      completerLocal.complete();
    }
  }
}