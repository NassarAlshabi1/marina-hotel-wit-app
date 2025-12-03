import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sync_models.dart';
import '../tasks/auto_sync_task.dart';
import 'google_drive_sync_service.dart';
import 'local_db.dart';
import 'smart_sync_manager.dart';
import 'sync_manager.dart';

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
  final SyncStatus? status;
}

/// حارس المزامنة: يتابع WorkManager و AutoSyncTask لضمان استهلاك جميع الأحداث
/// مع تسجيل الحالة الصحية، وإعادة المحاولة، وضبط أولوية الجهاز.
class SyncGuardian {
  SyncGuardian._();

  static final SyncGuardian instance = SyncGuardian._();

  final StreamController<SyncHealthSnapshot> _healthController = StreamController.broadcast();

  SyncManager? _manager;
  GoogleDriveSyncService? _driveService;
  StreamSubscription<SyncStatus>? _statusSubscription;
  Timer? _pendingMonitor;

  bool _initialized = false;
  bool _initializing = false;
  bool _priorityOverridden = false;
  bool _drainingPending = false;
  bool _pendingEvents = false;

  int _failedAttempts = 0;
  DateTime? _lastSyncAt;
  String? _lastError;
  SyncStatus? _latestStatus;

  Stream<SyncHealthSnapshot> watchHealth() => _healthController.stream;

  Future<void> initialize({
    required AppDatabase database,
    GoogleDriveSyncService? driveService,
  }) async {
    if (_initialized || _initializing) {
      return;
    }
    _initializing = true;
    try {
      _driveService = driveService ?? GoogleDriveSyncService();
      await _driveService!.init();

      _manager = SyncManager(db: database, driveService: _driveService!);
      await _manager!.initSyncService();
      await _restoreDevicePriority();

      _statusSubscription = _manager!.onSyncStatus().listen((status) {
        _latestStatus = status;
        _emitHealth();
      });

      await AutoSyncTask.initialize(debug: kDebugMode);
      await AutoSyncTask.schedulePeriodicSync(const Duration(minutes: 15));

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
    _emitHealth();

    try {
      // رفع التغييرات فوراً إلى Google Drive مع انتظار النتيجة
      debugPrint('📤 رفع التغييرات فوراً بعد: $table/$operation');
      await SmartSyncManager.instance.pushLocalChanges();
      debugPrint('✅ تم رفع التغييرات بنجاح');
    } catch (e) {
      debugPrint('⚠️ فشل رفع التغييرات: $e');
      // جدولة محاولة لاحقة
      try {
        await AutoSyncTask.scheduleImmediateSync();
      } catch (_) {}
    }

    _emitHealth();
  }

  Future<void> onAppForeground() async {
    if (!_initialized) {
      return;
    }
    
    _log('📱 التطبيق في المقدمة - سحب التغييرات...');
    
    // سحب التغييرات من Google Drive فوراً
    try {
      final hasNewChanges = await SmartSyncManager.instance.pullRemoteChanges();
      if (hasNewChanges) {
        _log('✅ تم سحب تغييرات جديدة من Google Drive');
      } else {
        _log('ℹ️ لا توجد تغييرات جديدة');
      }
    } catch (e) {
      _log('⚠️ فشل سحب التغييرات عند فتح التطبيق: $e');
    }
    
    // استهلاك أي أحداث معلقة
    await _consumePending(force: false);
  }

  void _log(String message) {
    debugPrint('[SyncGuardian] $message');
  }

  Future<void> forceSync() async {
    await _consumePending(force: true);
  }

  Future<void> setDevicePriority(int priority) async {
    if (_manager == null) {
      return;
    }
    _manager!.setDevicePriority(priority);
    _priorityOverridden = priority > 100;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_guardian_device_priority', priority);
    _emitHealth();
  }

  Future<void> _restoreDevicePriority() async {
    final prefs = await SharedPreferences.getInstance();
    final priority = prefs.getInt('sync_guardian_device_priority');
    if (priority != null) {
      _manager?.setDevicePriority(priority);
      _priorityOverridden = priority > 100;
    }
  }

  void _startPendingMonitor() {
    _pendingMonitor?.cancel();
    _pendingMonitor = Timer.periodic(const Duration(minutes: 5), (_) async {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool('auto_sync_pending') ?? false;
      _pendingEvents = pending;
      if (pending) {
        await _consumePending(force: false);
      } else {
        _emitHealth();
      }
    });
  }

  Future<void> _consumePending({required bool force}) async {
    if (!_initialized || _manager == null || _drainingPending) {
      return;
    }
    _drainingPending = true;
    try {
      await AutoSyncTask.consumePendingAndSync(_manager!, force: force);
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
        status: _latestStatus,
      ),
    );
  }

  Future<void> dispose() async {
    await _statusSubscription?.cancel();
    _pendingMonitor?.cancel();
    _healthController.close();
    _initialized = false;
  }
}
