// AutoOutboxSyncWatcher — watches the outbox table and automatically
// triggers pushLocalChanges whenever new entries appear.
//
// Centralized solution: any write to outbox (from any DAO/repository/screen)
// automatically triggers a debounced push. No per-screen sync calls needed.

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'local_db.dart';

class AutoOutboxSyncWatcher {
  AutoOutboxSyncWatcher._();
  static final AutoOutboxSyncWatcher instance = AutoOutboxSyncWatcher._();

  StreamSubscription<int>? _subscription;
  Timer? _debounceTimer;
  bool _pushing = false;
  bool _started = false;

  /// The push function — set during app init.
  /// Returns number of records pushed.
  static Future<int> Function()? _pushFn;

  /// Sets the push function (call in main.dart after sync manager init).
  static set pushFunction(Future<int> Function() fn) {
    _pushFn = fn;
  }

  /// Starts watching the outbox.
  void start(AppDatabase db) {
    if (_started) return;
    _started = true;

    _subscription = db
        .customSelect(
          'SELECT COUNT(*) AS cnt FROM outbox WHERE processing_status = ?',
          variables: [Variable.withString('pending')],
          readsFrom: {db.outbox},
        )
        .watchSingle()
        .map((row) => row.read<int>('cnt'))
        .listen((count) {
          if (count > 0) {
            _schedulePush();
          }
        });

    debugPrint('👁️ AutoOutboxSyncWatcher started');
  }

  void _schedulePush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), _doPush);
  }

  Future<void> _doPush() async {
    if (_pushing) return;
    _pushing = true;
    try {
      final fn = _pushFn;
      if (fn == null) return;
      final result = await fn();
      if (result > 0) {
        debugPrint('📤 AutoSync: pushed $result changes');
      }
    } catch (e) {
      debugPrint('⚠️ AutoSync push error: $e');
    } finally {
      _pushing = false;
    }
  }

  void stop() {
    _subscription?.cancel();
    _debounceTimer?.cancel();
    _started = false;
  }

  bool get isRunning => _started;
}
