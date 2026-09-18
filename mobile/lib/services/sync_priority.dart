import '../utils/debug_log.dart';

/// ✅ Prioritized sync — prevents lower-priority syncs from
///抢占 higher-priority ones.
///
/// Without priority, a background WorkManager sync could block a
/// realtime WebSocket event from being processed. This system ensures
/// that realtime events always win, manual refreshes beat auto-sync,
/// and auto-sync beats background tasks.
enum SyncPriority {
  realtime(100, 'realtime_event'),
  manual(80, 'manual_refresh'),
  foreground(60, 'app_foreground'),
  staleness(40, 'pull_staleness_guard'),
  autoSync(20, 'auto_sync_timer'),
  background(10, 'workmanager');

  final int value;
  final String label;
  const SyncPriority(this.value, this.label);
}

/// Tracks the currently running sync priority.
/// Lower priority cannot preempt higher priority.
class SyncPriorityGuard {
  SyncPriorityGuard._();
  static final SyncPriorityGuard instance = SyncPriorityGuard._();

  SyncPriority? _currentPriority;
  DateTime? _startedAt;
  String? _currentLabel;

  SyncPriority? get current => _currentPriority;
  Duration? get elapsed =>
      _startedAt != null ? DateTime.now().difference(_startedAt!) : null;
  String? get currentLabel => _currentLabel;

  /// Can the requested priority run right now?
  bool canRun(SyncPriority requested) {
    if (_currentPriority == null) return true;
    return requested.value >= _currentPriority!.value;
  }

  void acquire(SyncPriority priority, {String? label}) {
    _currentPriority = priority;
    _startedAt = DateTime.now();
    _currentLabel = label ?? priority.label;
  }

  void release() {
    dlog(
      () =>
          '🔓 SyncPriority released: ${_currentPriority?.label} '
          '(ran for ${elapsed?.inSeconds}s)',
    );
    _currentPriority = null;
    _startedAt = null;
    _currentLabel = null;
  }

  /// Safety: force release if running longer than [maxDuration].
  void enforceTimeout(Duration maxDuration) {
    if (_currentPriority == null || _startedAt == null) return;
    if (DateTime.now().difference(_startedAt!) > maxDuration) {
      dlog(
        () =>
            '⚠️ SyncPriority timeout: force releasing '
            '"${_currentPriority?.label}" after ${maxDuration.inMinutes}m',
      );
      release();
    }
  }
}
