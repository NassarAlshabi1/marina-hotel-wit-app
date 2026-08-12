// AutoOutboxSyncWatcher — watches the outbox table and automatically
// triggers pushLocalChanges whenever new entries appear.
//
// Centralized solution: any write to outbox (from any DAO/repository/screen)
// automatically triggers a debounced push. No per-screen sync calls needed.
//
// ✅ Offline-aware: if no internet, skips push and retries when connectivity
//    is restored. Outbox entries remain in 'pending' status until successful
//    push, so no data is lost.
// ✅ Weak-device friendly: uses a single stream subscription (no polling),
//    debounced push (3s), and prevents overlapping pushes.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';

import 'local_db.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';
import 'sync_guard.dart';

class AutoOutboxSyncWatcher {
  AutoOutboxSyncWatcher._();
  static final AutoOutboxSyncWatcher instance = AutoOutboxSyncWatcher._();

  StreamSubscription<int>? _subscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _debounceTimer;
  bool _pushing = false;
  bool _started = false;
  bool _isOnline = false;

  /// The push function — set during app init.
  /// Returns number of records pushed.
  static Future<int> Function()? _pushFn;

  /// Sets the push function (call in main.dart after sync manager init).
  static set pushFunction(Future<int> Function() fn) {
    _pushFn = fn;
  }

  /// Starts watching the outbox + connectivity.
  ///
  /// ✅ Code Review Fix (2026-08-06): تحويل لـ async + await connectivity check.
  /// سابقاً، كان `checkConnectivity().then(...)` غير مُنتظر، فلو fire الـ outbox
  /// listener قبل اكتمال الفحص (مثلاً على جهاز بطيء)، الـ first push كان
  /// يُؤجّل لأن `_isOnline = false` افتراضياً. الآن نُنتظر الفحص قبل تسجيل
  /// الـ listeners لضمان أن `_isOnline` صحيح عند أول outbox event.
  ///
  /// التوافق: main.dart يستدعي start() بشكل unawaited (لا ينتظر التهيئة)،
  /// لكن هذا مقبول لأن الـ outbox entries تبقى في حالة 'pending' حتى
  /// يكتمل الفحص (~50ms عادةً). لو فشل الفحص، نُعامل الحالة كـ offline
  /// (آمن: لا push بدون تأكيد الاتصال).
  Future<void> start(AppDatabase db) async {
    if (_started) return;
    _started = true;

    // ✅ Code Review Fix: نُنتظر الفحص قبل تسجيل الـ listeners.
    // هذا يضمن أن `_isOnline` صحيح عند أول outbox event.
    try {
      final results = await Connectivity().checkConnectivity();
      _isOnline = results.any((r) => r != ConnectivityResult.none);
    } catch (e) {
      // فشل الفحص (نادر) — نُعامل كـ offline (آمن)
      _isOnline = false;
      dlog(
        () =>
            '⚠️ AutoSync: initial connectivity check failed: $e '
            '(treating as offline)',
      );
    }

    // 1. Watch connectivity — track online/offline state
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);

      if (_isOnline && !wasOnline) {
        // Just came back online → flush pending outbox
        dlog('🌐 AutoSync: back online → flushing outbox');
        _schedulePush();
      } else if (!_isOnline && wasOnline) {
        dlog('📴 AutoSync: went offline → push paused');
      }
    });

    // 2. Watch outbox table for new pending entries
    // ✅ الآن `_isOnline` صحيح، فلو كان هناك pending entries عند البدء
    // و online، الـ first push سيحدث بشكل صحيح بعد الـ 3s debounce.
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

    dlog(
      '👁️ AutoOutboxSyncWatcher started (offline-aware, '
      'initial online=$_isOnline)',
    );
  }

  void _schedulePush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), _doPush);
  }

  Future<void> _doPush() async {
    // ✅ Offline check: don't attempt push if no internet
    if (!_isOnline) {
      dlog('📴 AutoSync: offline — push deferred (outbox retains entries)');
      return;
    }

    if (_pushing) {
      dlog('⏭️ AutoSync: push already in progress');
      return;
    }

    // ✅ Wave 5: ownership-safe tryAcquire (with token).
    final token = SyncGuard.tryAcquire(label: 'auto_outbox_push');
    if (token == null) {
      dlog(
        '⏸️ AutoSync skipped — another sync active (${SyncGuard.activeLabel})',
      );
      return;
    }

    _pushing = true;
    try {
      final fn = _pushFn;
      if (fn == null) return;
      final result = await fn();
      if (result > 0) {
        dlog(() => '📤 AutoSync: pushed $result changes');
      }
    } catch (e) {
      dlog(
        () => '⚠️ AutoSync push error: $e (will retry on next outbox change)',
      );
    } finally {
      _pushing = false;
      SyncGuard.release(token);
    }
  }

  /// Manually triggers a push (e.g., from a sync button).
  Future<void> pushNow() async {
    _debounceTimer?.cancel();
    // ✅ Wave 5: ownership-safe tryAcquire (with token).
    final token = SyncGuard.tryAcquire(label: 'auto_outbox_push');
    if (token == null) {
      dlog(
        '⏸️ Push skipped — another sync active (${SyncGuard.activeLabel})',
      );
      return;
    }

    try {
      await _doPush();
    } finally {
      SyncGuard.release(token);
    }
  }

  /// Whether the device is currently online.
  bool get isOnline => _isOnline;

  /// Whether a push is currently in progress.
  bool get isPushing => _pushing;

  void stop() {
    _subscription?.cancel();
    _connectivitySub?.cancel();
    _debounceTimer?.cancel();
    _started = false;
  }

  bool get isRunning => _started;
}
