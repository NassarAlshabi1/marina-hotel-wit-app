import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tasks/auto_sync_task.dart';
import '../utils/app_logger.dart';
import '../utils/debug_log.dart';
import 'local_db.dart';
import 'sync_constants.dart';
import 'unified_sync_orchestrator.dart';

class SyncHealthSnapshot {
  const SyncHealthSnapshot({
    required this.lastSyncAt,
    required this.failedAttempts,
    required this.pendingEvents,
    required this.isInitialized,
    required this.lastError,
    required this.monitoringActive,
    required this.priorityOverridden,
    required this.status,
  });

  final DateTime? lastSyncAt;
  final int failedAttempts;
  final bool pendingEvents;
  final bool isInitialized;
  final String? lastError;
  final bool monitoringActive;
  final bool priorityOverridden;
  final String? status;
}

class SyncGuardian {
  SyncGuardian._();

  static final SyncGuardian instance = SyncGuardian._();

  final StreamController<SyncHealthSnapshot> _healthController = StreamController.broadcast();

  Timer? _pendingMonitor;
  Timer? _debounceTimer;
  int _pendingChangesCount = 0;
  DateTime? _lastPullTime;

  bool _initialized = false;
  bool _initializing = false;
  bool _priorityOverridden = false;
  bool _drainingPending = false;
  bool _pendingEvents = false;

  int _failedAttempts = 0;
  DateTime? _lastSyncAt;
  String? _lastError;

  AppDatabase? _database;
  UnifiedSyncOrchestrator? _orchestrator;

  Stream<SyncHealthSnapshot> watchHealth() => _healthController.stream;

  Future<void> initialize({required AppDatabase database}) async {
    if (_initialized || _initializing) {
      return;
    }
    _initializing = true;
    _database = database;
    _orchestrator = UnifiedSyncOrchestrator.instance;
    try {
      await _orchestrator!.initialize(database: database);
      await AutoSyncTask.initialize(debug: kDebugMode);
      await AutoSyncTask.schedulePeriodicSync(SyncConstants.defaultAutoSyncInterval);
      await _restoreDevicePriority();
      _startPendingMonitor();
      await _refreshPendingFlag();
      _initialized = true;
      _emitHealth();
    } finally {
      _initializing = false;
    }
  }

  Future<void> notifyLocalChange({String? table, String? operation}) async {
    if (!_initialized) {
      return;
    }

    _pendingEvents = true;
    _pendingChangesCount++;
    _emitHealth();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(SyncConstants.guardianLocalChangeDebounce, () async {
      try {
        dlog(() => '📤 رفع $_pendingChangesCount تغيير بعد debounce: $table/$operation');
        final ok = await _orchestrator!.syncNow(reason: 'guardian_debounce');
        if (!ok) {
          await AutoSyncTask.scheduleImmediateSync();
        }
        _pendingChangesCount = 0;
      } catch (e) {
        dwarn(() => 'فشل رفع التغييرات: $e');
        try {
          await AutoSyncTask.scheduleImmediateSync();
        } catch (e, st) {
          AppLogger.warning('فشل فحص حماية المزامنة', tag: 'SYNC_GUARD', error: e, stackTrace: st);
        }
      } finally {
        _emitHealth();
      }
    });
  }

  Future<void> onAppForeground() async {
    if (!_initialized) {
      return;
    }

    _log('📱 التطبيق في المقدمة');

    final now = DateTime.now();
    if (_lastPullTime != null) {
      final minutesSinceLastPull = now.difference(_lastPullTime!).inMinutes;
      if (minutesSinceLastPull < 2) {
        _log('✓ تخطي Pull - آخر سحب كان قبل $minutesSinceLastPull دقيقة');
        return;
      }
    }

    _lastPullTime = now;

    Future<void>.delayed(SyncConstants.appForegroundDelay, () async {
      try {
        await _orchestrator!.onAppForeground();
      } catch (e) {
        _log('⚠️ فشل سحب التغييرات: $e');
      }
    });

    await _consumePending(force: false);
  }

  void _log(String message) {
    dlog(() => '[SyncGuardian] $message');
  }

  Future<void> forceSync() async {
    await _consumePending(force: true);
    await _orchestrator?.syncNow(reason: 'guardian_force');
  }

  Future<void> setDevicePriority(int priority) async {
    _priorityOverridden = priority > 100;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_guardian_device_priority', priority);
    _emitHealth();
  }

  Future<void> _restoreDevicePriority() async {
    final prefs = await SharedPreferences.getInstance();
    final priority = prefs.getInt('sync_guardian_device_priority');
    if (priority != null) {
      _priorityOverridden = priority > 100;
    }
  }

  void _startPendingMonitor() {
    _pendingMonitor?.cancel();
    _pendingMonitor = Timer.periodic(const Duration(minutes: 5), (_) async {
      // ✅ إصلاح جذري: Timer callback async بدون try-catch يُسبب
      // unhandled async error → Crashlytics Fatal عند أي استثناء.
      try {
        final prefs = await SharedPreferences.getInstance();
        final pending = prefs.getBool('auto_sync_pending') ?? false;
        _pendingEvents = pending;
        if (pending) {
          await _consumePending(force: false);
        } else {
          _emitHealth();
        }
      } catch (e) {
        _log('⚠️ SyncGuardian pending monitor خطأ: $e');
        // لا rethrow — نمنع fatal crash
      }
    });
  }

  Future<void> _consumePending({required bool force}) async {
    if (!_initialized || _drainingPending) {
      return;
    }
    _drainingPending = true;
    try {
      await AutoSyncTask.consumePendingAndSync(force: force);
      _failedAttempts = 0;
      _lastSyncAt = DateTime.now().toUtc();
      _lastError = null;
      await _refreshPendingFlag();
    } catch (error) {
      _failedAttempts += 1;
      _lastError = error.toString();
      await _refreshPendingFlag();
    } finally {
      _emitHealth();
      _drainingPending = false;
    }
  }

  Future<void> _refreshPendingFlag() async {
    final prefs = await SharedPreferences.getInstance();
    _pendingEvents = prefs.getBool('auto_sync_pending') ?? false;
  }

  void _emitHealth() {
    _healthController.add(
      SyncHealthSnapshot(
        lastSyncAt: _lastSyncAt,
        failedAttempts: _failedAttempts,
        pendingEvents: _pendingEvents,
        isInitialized: _initialized,
        lastError: _lastError,
        monitoringActive: _pendingMonitor?.isActive ?? false,
        priorityOverridden: _priorityOverridden,
        status: null,
      ),
    );
  }

  Future<void> dispose() async {
    _pendingMonitor?.cancel();
    unawaited(_healthController.close());
    _initialized = false;
  }

  Future<void> stop() async {
    _log('⏸️ Stopping SyncGuardian...');
    _pendingMonitor?.cancel();
    _debounceTimer?.cancel();
    _initialized = false;
    _log('✅ SyncGuardian stopped');
  }

  Future<void> restart() async {
    _log('🔄 Restarting SyncGuardian...');
    await stop();
    if (_database != null) {
      await initialize(database: _database!);
    }
    _log('✅ SyncGuardian restarted');
  }
}
