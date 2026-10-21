// UnifiedSyncScheduler — single entry point for all periodic sync timers.
//
// Replaces multiple parallel Timer.periodic instances across
// AppwriteSyncManager, SmartSyncManager, GoogleDriveUnifiedSyncCoordinator.

import 'dart:async';

import '../utils/circular_buffer_logger.dart';
import '../utils/weak_device_optimizer.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class SyncTask {
  const SyncTask({
    required this.id,
    required this.name,
    required this.interval,
    required this.callback,
    this.runImmediately = false,
  });

  final String id;
  final String name;
  final Duration interval;
  final Future<void> Function() callback;
  final bool runImmediately;
}

class UnifiedSyncScheduler {
  UnifiedSyncScheduler._();
  static final UnifiedSyncScheduler instance = UnifiedSyncScheduler._();

  final Map<String, Timer> _timers = {};
  final Map<String, bool> _running = {};
  bool _started = false;
  final List<SyncTask> _tasks = [];

  void register(SyncTask task) {
    if (_started) {
      dlog('⚠️ Cannot register after start');
      return;
    }
    _tasks.add(task);
  }

  void start() {
    if (_started) return;
    _started = true;

    final optimizer = WeakDeviceOptimizer.instance;
    final multiplier = optimizer.isWeakDevice ? 2.0 : 1.0;

    for (final task in _tasks) {
      final adjusted = Duration(
        milliseconds: (task.interval.inMilliseconds * multiplier).round(),
      );

      _running[task.id] = false;

      if (task.runImmediately) {
        _executeTask(task);
      }

      _timers[task.id] = Timer.periodic(adjusted, (_) {
        _executeTask(task);
      });

      dlog(() => '✅ Started: ${task.name} (${adjusted.inSeconds}s)');
    }

    CircularBufferLogger.instance.info(
      'UnifiedSyncScheduler started: ${_tasks.length} tasks',
      tag: 'SCHEDULER',
    );
  }

  void stop() {
    if (!_started) return;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _running.clear();
    _started = false;
  }

  void stopTask(String id) {
    _timers[id]?.cancel();
    _timers.remove(id);
    _running.remove(id);
  }

  bool get isRunning => _started;
  int get activeTaskCount => _timers.length;

  Future<void> _executeTask(SyncTask task) async {
    if (_running[task.id] == true) {
      dlog(() => '⏭️ Skip ${task.name} — running');
      return;
    }

    _running[task.id] = true;
    try {
      await task.callback();
    } catch (e, st) {
      dlog(() => '❌ ${task.name} failed: $e');
      CircularBufferLogger.instance.error(
        'Task ${task.name} failed: $e',
        tag: 'SCHEDULER',
        error: e,
        stack: st,
      );
    } finally {
      _running[task.id] = false;
    }
  }

  void dispose() {
    stop();
    _tasks.clear();
  }
}
