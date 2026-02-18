// ignore_for_file: unused_field

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_logs.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_delta_sync.dart';
import 'google_drive_logger.dart';
import 'local_db.dart';
import 'data_usage_manager.dart';
import 'sync_locks.dart';
import 'sync_constants.dart';
import 'sync_performance_optimizer.dart';
import 'logging/log_models.dart';

enum SyncTrigger { manual, appForeground, localChange, periodic, scheduled }

enum SyncMode { deltaOnly, fullBackup, smart }

enum SyncPhase {
  idle,
  authenticating,
  pushing,
  pulling,
  conflict,
  completed,
  failed,
}

// ignore: unused_element
enum _SyncStartResult { ok, notInitialized, notSignedIn, alreadySyncing }

sealed class _PerformSyncStartResult {}

class _PerformSyncOk extends _PerformSyncStartResult {}

class _PerformSyncNotInitialized extends _PerformSyncStartResult {}

class _PerformSyncNotSignedIn extends _PerformSyncStartResult {}

class _PerformSyncAlreadyInProgress extends _PerformSyncStartResult {
  final int elapsedSeconds;
  _PerformSyncAlreadyInProgress(this.elapsedSeconds);
}

class SyncResult {
  final bool success;
  final String message;
  final int? pushedChanges;
  final int? pulledChanges;
  final SyncPhase phase;
  final DateTime timestamp;
  final String? error;

  const SyncResult({
    required this.success,
    required this.message,
    this.pushedChanges,
    this.pulledChanges,
    required this.phase,
    required this.timestamp,
    this.error,
  });

  factory SyncResult.success({
    required String message,
    int? pushed,
    int? pulled,
  }) {
    return SyncResult(
      success: true,
      message: message,
      pushedChanges: pushed,
      pulledChanges: pulled,
      phase: SyncPhase.completed,
      timestamp: DateTime.now(),
    );
  }

  factory SyncResult.failure({
    required String message,
    String? error,
    required SyncPhase phase,
  }) {
    return SyncResult(
      success: false,
      message: message,
      error: error,
      phase: phase,
      timestamp: DateTime.now(),
    );
  }
}

class GoogleDriveUnifiedSyncCoordinator {
  GoogleDriveUnifiedSyncCoordinator._();
  static final instance = GoogleDriveUnifiedSyncCoordinator._();

  GoogleDriveBackupService? _backupService;
  GoogleDriveDeltaSync? _deltaSync;
  GoogleDriveLogger? _logger;
  AppDatabase? _database;

  Timer? _debounceTimer;
  Timer? _periodicSyncTimer;
  Timer? _pullCheckTimer;
  StreamSubscription? _outboxSubscription;

  bool _isInitialized = false;
  bool _isSyncing = false;
  bool _hasPendingChanges = false;
  int _pendingChangesCount = 0;
  DateTime? _lastPushTime;
  DateTime? _lastPullTime;
  DateTime? _lastFullBackupTime;
  DateTime? _firstChangeTime;
  DateTime? _syncStartTime;

  SyncPhase _currentPhase = SyncPhase.idle;

  static const Duration _syncTimeout = Duration(minutes: 2);
  final _syncResultController = StreamController<SyncResult>.broadcast();

  bool _pushEnabled = true;
  bool _pullEnabled = true;
  int _debounceSeconds = _defaultDebounceSeconds;
  int _pullIntervalMinutes = _defaultPullIntervalMinutes;
  int _fullBackupIntervalHours = _defaultFullBackupHours;

  static const String _prefsPushEnabledKey = 'gd_unified_push_enabled';
  static const String _prefsPullEnabledKey = 'gd_unified_pull_enabled';
  static const String _prefsDebounceSecondsKey = 'gd_unified_debounce_seconds';
  static const String _prefsPullIntervalKey =
      'gd_unified_pull_interval_minutes';
  static const String _prefsFullBackupIntervalKey =
      'gd_unified_full_backup_hours';
  static const String _prefsSyncModeKey = 'gd_unified_sync_mode';
  static const String _prefsLastPushKey = 'gd_unified_last_push';
  static const String _prefsLastPullKey = 'gd_unified_last_pull';
  static const String _prefsLastFullBackupKey = 'gd_unified_last_full_backup';

  static const int _defaultDebounceSeconds =
      1; // انتظار قصير جداً بعد الحفظ (ثانية واحدة فقط لتجميع العمليات المتعددة)
  static const int _maxDebounceSeconds =
      3; // الحد الأقصى للانتظار (غير مستخدم حالياً)
  static const int _defaultPullIntervalMinutes = 2;
  static const int _defaultFullBackupHours = 24;

  Stream<SyncResult> get syncResults => _syncResultController.stream;
  bool get isInitialized => _isInitialized;
  bool get isSyncing => _isSyncing;
  SyncPhase get currentPhase => _currentPhase;
  bool get hasPendingChanges => _hasPendingChanges;
  int get pendingChangesCount => _pendingChangesCount;
  String? get deviceId => _deltaSync?.deviceId;

  void _log(String message, {LogLevel level = LogLevel.info}) {
    DebugLogs.add('UnifiedSyncCoordinator', message);
    debugPrint('[UnifiedSyncCoordinator] $message');
    _logger?.log(message, level: level, tag: 'SYNC_COORD');
  }

  Future<void> initialize({
    required GoogleDriveBackupService backupService,
    required AppDatabase database,
    GoogleDriveLogger? logger,
  }) async {
    if (_isInitialized) {
      _log('⚠️ Coordinator already initialized');
      return;
    }

    _backupService = backupService;
    _database = database;
    _logger = logger;
    _deltaSync = GoogleDriveDeltaSync.instance;

    await _deltaSync!.initialize(backupService, database);
    await _loadSettings();

    final prefs = await SharedPreferences.getInstance();
    _lastPushTime = _parseTimestamp(prefs.getString(_prefsLastPushKey));
    _lastPullTime = _parseTimestamp(prefs.getString(_prefsLastPullKey));
    _lastFullBackupTime = _parseTimestamp(
      prefs.getString(_prefsLastFullBackupKey),
    );

    if (backupService.isSignedIn) {
      await _startMonitoring();
    }

    _isInitialized = true;
    _log('✅ Unified Sync Coordinator initialized successfully');
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey(_prefsPushEnabledKey)) {
      await prefs.setBool(_prefsPushEnabledKey, false);
    }
    if (!prefs.containsKey(_prefsPullEnabledKey)) {
      await prefs.setBool(_prefsPullEnabledKey, false);
    }
    if (!prefs.containsKey(_prefsDebounceSecondsKey)) {
      await prefs.setInt(_prefsDebounceSecondsKey, _defaultDebounceSeconds);
    }
    if (!prefs.containsKey(_prefsPullIntervalKey)) {
      await prefs.setInt(_prefsPullIntervalKey, _defaultPullIntervalMinutes);
    }
    if (!prefs.containsKey(_prefsFullBackupIntervalKey)) {
      await prefs.setInt(_prefsFullBackupIntervalKey, _defaultFullBackupHours);
    }
    if (!prefs.containsKey(_prefsSyncModeKey)) {
      await prefs.setString(_prefsSyncModeKey, SyncMode.smart.name);
    }

    _pushEnabled = prefs.getBool(_prefsPushEnabledKey) ?? false;
    _pullEnabled = prefs.getBool(_prefsPullEnabledKey) ?? false;
    _debounceSeconds =
        prefs.getInt(_prefsDebounceSecondsKey) ?? _defaultDebounceSeconds;
    _pullIntervalMinutes =
        prefs.getInt(_prefsPullIntervalKey) ?? _defaultPullIntervalMinutes;
    _fullBackupIntervalHours =
        prefs.getInt(_prefsFullBackupIntervalKey) ?? _defaultFullBackupHours;

    if (_pullEnabled) {
      _pullEnabled = false;
      await prefs.setBool(_prefsPullEnabledKey, false);
    }
  }

  Future<void> onSignInChanged(bool isSignedIn) async {
    _log('🔐 Sign-in status changed: $isSignedIn');

    if (isSignedIn) {
      final prefs = await SharedPreferences.getInstance();
      final syncEnabled = prefs.getBool('google_drive_sync_enabled') ?? false;
      if (!syncEnabled) {
        _log('⏸️ Google Drive sync disabled - skipping monitoring');
        return;
      }
      await _startMonitoring();
      await performSync(trigger: SyncTrigger.manual, mode: SyncMode.smart);
    } else {
      _stopMonitoring();
      _hasPendingChanges = false;
      _pendingChangesCount = 0;
    }
  }

  Future<void> _startMonitoring() async {
    if (!_isInitialized || !(_backupService?.isSignedIn ?? false)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final syncEnabled = prefs.getBool('google_drive_sync_enabled') ?? false;
    if (!syncEnabled) {
      _log('⏸️ Google Drive sync disabled - monitoring skipped');
      return;
    }

    // مراقبة تغييرات outbox للمزامنة التلقائية
    _outboxSubscription?.cancel();
    if (_pushEnabled && _database != null) {
      _outboxSubscription = (_database!.select(_database!.outbox))
          .watch()
          .listen((_) {
            _log('📦 Detected change in outbox', level: LogLevel.debug);
            notifyLocalChange();
          });
      _log('✅ Started outbox monitoring for auto-sync');
    }

    if (_pullEnabled) {
      _pullCheckTimer?.cancel();
      _pullCheckTimer = Timer.periodic(
        Duration(minutes: _pullIntervalMinutes),
        (_) => _handlePeriodicPull(),
      );
      _log(
        '⏰ Started periodic pull monitoring (every $_pullIntervalMinutes minutes)',
      );
    }

    _scheduleFullBackup();
  }

  void _stopMonitoring() {
    _debounceTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _pullCheckTimer?.cancel();
    _outboxSubscription?.cancel();
    _log('⏹️ Stopped all monitoring');
  }

  Future<void> _scheduleFullBackup() async {
    Duration delay;
    if (_lastFullBackupTime == null) {
      delay = const Duration(hours: 1);
    } else {
      final elapsed = DateTime.now().difference(_lastFullBackupTime!);
      final target = Duration(hours: _fullBackupIntervalHours);
      if (elapsed >= target) {
        delay = const Duration(minutes: 5);
      } else {
        delay = target - elapsed;
      }
    }

    _log('📅 Next full backup in ${delay.inHours}h ${delay.inMinutes % 60}m');

    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer(delay, () async {
      await performSync(
        trigger: SyncTrigger.scheduled,
        mode: SyncMode.fullBackup,
      );

      _periodicSyncTimer = Timer.periodic(
        Duration(hours: _fullBackupIntervalHours),
        (_) => performSync(
          trigger: SyncTrigger.scheduled,
          mode: SyncMode.fullBackup,
        ),
      );
    });
  }

  /// إشعار بتغيير محلي في البيانات
  ///
  /// آلية فورية وذكية:
  /// - مزامنة شبه فورية بعد الضغط على زر الحفظ/الإضافة/التعديل/الحذف
  /// - انتظار ثانية واحدة فقط لتجميع العمليات المتعددة السريعة
  /// - يجمع كل التغييرات ويزامنها دفعة واحدة
  ///
  /// مثال:
  /// - المستخدم يضغط "حفظ حجز" → انتظار ثانية واحدة → مزامنة تلقائية ✅
  /// - يضغط "حفظ" 3 مرات بسرعة → تُجمع كلها وتُزامن مرة واحدة
  /// - يحذف 5 عناصر بسرعة → تُجمع وتُزامن مرة واحدة
  ///
  /// الفائدة:
  /// - شبه فوري: يشعر المستخدم بالمزامنة الفورية
  /// - ذكي: لا يزعج المستخدم بمزامنات متعددة
  /// - فعال: يوفر البطارية والبيانات
  void notifyLocalChange({String? table, String? operation, int count = 1}) {
    if (!_isInitialized) return;

    SyncLocks.mainSyncLock.synchronized(() {
      final now = DateTime.now();

      if (!_hasPendingChanges) {
        _firstChangeTime = now;
        _log(
          '💾 Save action detected: ${table ?? "unknown"} ($operation)',
          level: LogLevel.debug,
        );
      }

      _hasPendingChanges = true;
      _pendingChangesCount += count;
    });

    _debounceTimer?.cancel();

    if (!_pushEnabled) {
      _log('⏸️ Push disabled - changes queued ($_pendingChangesCount)');
      return;
    }

    final effectiveDebounce = _debounceSeconds;
    _log(
      '🚀 Triggering sync in ${effectiveDebounce}s (${_pendingChangesCount} changes pending)',
      level: LogLevel.debug,
    );

    _debounceTimer = Timer(Duration(seconds: effectiveDebounce), () async {
      if (_hasPendingChanges) {
        _log('✅ Starting sync for $_pendingChangesCount changes');
        _triggerSync();
      }
    });
  }

  Future<void> _triggerSync() async {
    try {
      await performSync(trigger: SyncTrigger.localChange, mode: SyncMode.smart);
    } finally {
      _firstChangeTime = null;
    }
  }

  Future<void> onAppForeground() async {
    if (!_isInitialized || !(_backupService?.isSignedIn ?? false)) {
      return;
    }

    _log('📱 App entered foreground');

    if (!_pullEnabled) {
      _log('⏸️ Pull disabled - skipping foreground sync');
      return;
    }

    final now = DateTime.now();
    if (_lastPullTime != null) {
      final minutesSince = now.difference(_lastPullTime!).inMinutes;
      if (minutesSince < 1) {
        _log('✓ Last pull was $minutesSince min ago - skipping');
        return;
      }
    }

    Future.delayed(SyncConstants.appForegroundDelay, () async {
      await performSync(
        trigger: SyncTrigger.appForeground,
        mode: SyncMode.smart,
      );
    });
  }

  Future<void> _handlePeriodicPull() async {
    if (!_isSyncing && (_backupService?.isSignedIn ?? false)) {
      if (_pullEnabled) {
        _log('🔄 Periodic pull check triggered');
        await performSync(
          trigger: SyncTrigger.periodic,
          mode: SyncMode.deltaOnly,
        );
      }
    }
  }

  Future<SyncResult> performSync({
    required SyncTrigger trigger,
    SyncMode mode = SyncMode.smart,
  }) async {
    final canStartResult = await SyncLocks.mainSyncLock.synchronized(() async {
      if (!_isInitialized) return _PerformSyncNotInitialized();
      if (!(_backupService?.isSignedIn ?? false)) {
        return _PerformSyncNotSignedIn();
      }

      if (_isSyncing) {
        if (_syncStartTime != null) {
          final elapsed = DateTime.now().difference(_syncStartTime!);
          if (elapsed > _syncTimeout) {
            _log(
              '⚠️ Sync timeout detected (${elapsed.inSeconds}s) - resetting state',
            );
            _isSyncing = false;
            _syncStartTime = null;
            _currentPhase = SyncPhase.idle;
          } else {
            return _PerformSyncAlreadyInProgress(elapsed.inSeconds);
          }
        } else {
          _log(
            '⚠️ Inconsistent state: _isSyncing=true but _syncStartTime=null - resetting',
          );
          _isSyncing = false;
        }
      }

      _isSyncing = true;
      _syncStartTime = DateTime.now();
      _currentPhase = SyncPhase.authenticating;
      return _PerformSyncOk();
    });

    switch (canStartResult) {
      case _PerformSyncNotInitialized():
        return SyncResult.failure(
          message: 'Coordinator not initialized',
          phase: SyncPhase.idle,
        );
      case _PerformSyncNotSignedIn():
        return SyncResult.failure(
          message: 'Not signed in to Google Drive',
          phase: SyncPhase.authenticating,
        );
      case _PerformSyncAlreadyInProgress(elapsedSeconds: final elapsed):
        _log(
          '⏸️ Sync already in progress (${elapsed}s elapsed) - skipping $trigger',
        );
        if (trigger == SyncTrigger.periodic ||
            trigger == SyncTrigger.scheduled) {
          return SyncResult.success(
            message:
                'Sync already in progress - not an error for periodic sync',
            pushed: 0,
            pulled: 0,
          );
        }
        return SyncResult.failure(
          message: 'Sync already in progress',
          phase: _currentPhase,
        );
      case _PerformSyncOk():
        break;
    }

    _log('🚀 Starting sync [trigger=$trigger, mode=$mode]');

    try {
      final optimizer = SyncPerformanceOptimizer.instance;
      final dataManager = DataUsageManager.instance;

      final shouldSkip = await optimizer.shouldSkipSync();
      final enforceOptimizer =
          trigger == SyncTrigger.periodic || trigger == SyncTrigger.scheduled;
      if (shouldSkip) {
        if (enforceOptimizer) {
          _log('⏸️ Optimizer suggests skipping sync');
          return SyncResult.failure(
            message: 'Skipped by performance optimizer',
            phase: SyncPhase.idle,
          );
        } else {
          _log(
            '⚠️ Optimizer suggested skipping but trigger $trigger requires immediate sync',
          );
        }
      }

      if (await dataManager.isLimitExceeded()) {
        _log('📊 Data limit exceeded - skipping sync');
        return SyncResult.failure(
          message: 'Data limit exceeded',
          phase: SyncPhase.idle,
        );
      }

      final effectiveMode = _determineEffectiveMode(mode, trigger);

      int? pushed;
      int? pulled;

      if (effectiveMode == SyncMode.fullBackup) {
        pushed = await _performFullBackup();
        _lastFullBackupTime = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefsLastFullBackupKey,
          _lastFullBackupTime!.toIso8601String(),
        );
      } else if (effectiveMode == SyncMode.deltaOnly) {
        if (_pullEnabled) {
          pulled = await _performDeltaPull();
        } else {
          _log('⏸️ Pull disabled - skipping delta pull');
          pulled = 0;
        }
      } else {
        if (_hasPendingChanges || trigger == SyncTrigger.localChange) {
          pushed = await _performDeltaPush();
        }

        if (_pullEnabled &&
            (trigger == SyncTrigger.appForeground ||
                trigger == SyncTrigger.periodic ||
                trigger == SyncTrigger.manual)) {
          pulled = await _performDeltaPull();
        } else if (!_pullEnabled &&
            (trigger == SyncTrigger.appForeground ||
                trigger == SyncTrigger.periodic ||
                trigger == SyncTrigger.manual)) {
          _log('⏸️ Pull disabled - skipping delta pull');
          pulled = 0;
        }
      }

      optimizer.recordSyncSuccess();

      final result = SyncResult.success(
        message: 'Sync completed successfully',
        pushed: pushed,
        pulled: pulled,
      );

      _syncResultController.add(result);
      _log('✅ Sync completed [pushed=$pushed, pulled=$pulled]');

      return result;
    } catch (error, stackTrace) {
      final errorMessage = error.toString();
      _log('❌ Sync failed: $errorMessage', level: LogLevel.error);
      _log('Stack trace: $stackTrace', level: LogLevel.debug);

      SyncPerformanceOptimizer.instance.recordSyncFailure();

      String userFriendlyMessage = 'فشلت المزامنة';
      if (errorMessage.contains('NetworkException') ||
          errorMessage.contains('SocketException')) {
        userFriendlyMessage = 'خطأ في الاتصال بالإنترنت';
      } else if (errorMessage.contains('Unauthorized') ||
          errorMessage.contains('401')) {
        userFriendlyMessage =
            'انتهت صلاحية تسجيل الدخول - يرجى تسجيل الدخول مرة أخرى';
      } else if (errorMessage.contains('QuotaExceeded') ||
          errorMessage.contains('Storage')) {
        userFriendlyMessage = 'مساحة التخزين ممتلئة على Google Drive';
      } else if (errorMessage.contains('غير مسجل الدخول')) {
        userFriendlyMessage = 'غير مسجل الدخول في Google Drive';
      } else if (errorMessage.contains('الخدمة غير جاهزة')) {
        userFriendlyMessage = 'خدمة المزامنة غير جاهزة';
      } else {
        userFriendlyMessage = 'فشلت المزامنة: $errorMessage';
      }

      final result = SyncResult.failure(
        message: userFriendlyMessage,
        error: errorMessage,
        phase: _currentPhase,
      );

      _syncResultController.add(result);
      return result;
    } finally {
      await SyncLocks.mainSyncLock.synchronized(() async {
        _isSyncing = false;
        _syncStartTime = null;
        _currentPhase = SyncPhase.idle;
      });
    }
  }

  SyncMode _determineEffectiveMode(
    SyncMode requestedMode,
    SyncTrigger trigger,
  ) {
    if (requestedMode != SyncMode.smart) {
      return requestedMode;
    }

    if (trigger == SyncTrigger.scheduled) {
      return SyncMode.fullBackup;
    }

    if (_lastFullBackupTime == null) {
      return SyncMode.fullBackup;
    }

    final hoursSinceFullBackup = DateTime.now()
        .difference(_lastFullBackupTime!)
        .inHours;
    if (hoursSinceFullBackup >= _fullBackupIntervalHours) {
      return SyncMode.fullBackup;
    }

    return SyncMode.smart;
  }

  Future<int?> _performDeltaPush() async {
    _currentPhase = SyncPhase.pushing;
    _log('📤 Performing delta push...');

    try {
      final result = await _deltaSync!.pushDeltaChanges();

      if (result.success) {
        _hasPendingChanges = false;
        _pendingChangesCount = 0;
        _firstChangeTime = null;
        _lastPushTime = DateTime.now();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefsLastPushKey,
          _lastPushTime!.toIso8601String(),
        );

        if (result.changesCount > 0) {
          await DataUsageManager.instance.recordDataUsage(
            (result.changesCount * SyncConstants.estimatedBytesPerDeltaChange) /
                1024 /
                1024,
          );
        }

        _log('✅ Pushed ${result.changesCount} changes');
        return result.changesCount;
      } else {
        _log('⚠️ Delta push failed: ${result.message}');
        return null;
      }
    } catch (e) {
      _log('❌ Delta push error: $e');
      rethrow;
    }
  }

  Future<int?> _performDeltaPull() async {
    _currentPhase = SyncPhase.pulling;
    _log('📥 Performing delta pull...');

    try {
      final result = await _deltaSync!.pullDeltaChanges();

      if (result.success) {
        _lastPullTime = DateTime.now();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefsLastPullKey,
          _lastPullTime!.toIso8601String(),
        );

        if (result.changesCount > 0) {
          await DataUsageManager.instance.recordDataUsage(
            (result.changesCount * SyncConstants.estimatedBytesPerDeltaChange) /
                1024 /
                1024,
          );
        }

        _log('✅ Pulled ${result.changesCount} changes');
        return result.changesCount;
      } else {
        _log('ℹ️ No changes to pull');
        return 0;
      }
    } catch (e) {
      _log('❌ Delta pull error: $e');
      rethrow;
    }
  }

  Future<int?> _performFullBackup() async {
    _currentPhase = SyncPhase.pushing;
    _log('💾 Performing full backup...');

    try {
      final backupData = await _backupService!.exportDatabaseToJson();

      final metadata = backupData['metadata'];
      final baseMetadata = metadata is Map
          ? Map<String, dynamic>.from(metadata)
          : <String, dynamic>{};
      backupData['metadata'] = {
        ...baseMetadata,
        'backup_type': 'full',
        'sync_type': 'scheduled',
        'device_id': _deltaSync!.deviceId,
      };

      await _backupService!.uploadBackup(backupData, isSync: false);

      _log('✅ Full backup completed');
      return 1;
    } catch (e) {
      _log('❌ Full backup error: $e');
      rethrow;
    }
  }

  Future<void> setPushEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsPushEnabledKey, enabled);
    _pushEnabled = enabled;

    if (!enabled) {
      _outboxSubscription?.cancel();
      _outboxSubscription = null;
    } else {
      final syncEnabled = prefs.getBool('google_drive_sync_enabled') ?? false;
      if (_isInitialized &&
          syncEnabled &&
          (_backupService?.isSignedIn ?? false)) {
        _outboxSubscription?.cancel();
        if (_database != null) {
          _outboxSubscription = (_database!.select(_database!.outbox))
              .watch()
              .listen((_) {
                _log('📦 Detected change in outbox', level: LogLevel.debug);
                notifyLocalChange();
              });
        }
      }
    }

    _log('🔧 Push ${enabled ? 'enabled' : 'disabled'}');
  }

  Future<void> setPullEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsPullEnabledKey, enabled);
    _pullEnabled = enabled;

    if (enabled && _isInitialized && (_backupService?.isSignedIn ?? false)) {
      await _startMonitoring();
    } else if (!enabled) {
      _pullCheckTimer?.cancel();
    }

    _log('🔧 Pull ${enabled ? 'enabled' : 'disabled'}');
  }

  Future<void> setDebounceSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsDebounceSecondsKey, seconds);
    _debounceSeconds = seconds;
    _log('⏱️ Debounce set to $seconds seconds');
  }

  Future<void> setPullInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsPullIntervalKey, minutes);
    _pullIntervalMinutes = minutes;

    if (_isInitialized && (_backupService?.isSignedIn ?? false)) {
      await _startMonitoring();
    }

    _log('⏰ Pull interval set to $minutes minutes');
  }

  Future<void> setFullBackupInterval(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsFullBackupIntervalKey, hours);
    _fullBackupIntervalHours = hours;

    if (_isInitialized && (_backupService?.isSignedIn ?? false)) {
      _scheduleFullBackup();
    }

    _log('📅 Full backup interval set to $hours hours');
  }

  Future<Map<String, dynamic>> getStatus() async {
    return {
      'initialized': _isInitialized,
      'signed_in': _backupService?.isSignedIn ?? false,
      'is_syncing': _isSyncing,
      'current_phase': _currentPhase.name,
      'has_pending_changes': _hasPendingChanges,
      'pending_changes_count': _pendingChangesCount,
      'push_enabled': _pushEnabled,
      'pull_enabled': _pullEnabled,
      'debounce_seconds': _debounceSeconds,
      'pull_interval_minutes': _pullIntervalMinutes,
      'full_backup_interval_hours': _fullBackupIntervalHours,
      'last_push': _lastPushTime?.toIso8601String(),
      'last_pull': _lastPullTime?.toIso8601String(),
      'last_full_backup': _lastFullBackupTime?.toIso8601String(),
      'device_id': _deltaSync?.deviceId,
    };
  }

  DateTime? _parseTimestamp(String? iso) {
    if (iso == null) return null;
    try {
      return DateTime.parse(iso);
    } catch (_) {
      return null;
    }
  }

  Future<bool> pushChanges() async {
    _log('📤 Pushing local changes to Google Drive...');
    try {
      if (!_isInitialized || !(_backupService?.isSignedIn ?? false)) {
        _log('⚠️ Cannot push - not initialized or not signed in');
        return false;
      }

      final pushedCount = await _performDeltaPush();
      if (pushedCount != null && pushedCount >= 0) {
        _log('✅ Pushed $pushedCount changes to Google Drive');
        return true;
      }
      return false;
    } catch (e) {
      _log('❌ Push failed: $e', level: LogLevel.error);
      return false;
    }
  }

  Future<bool> pullChanges() async {
    _log('📥 Pulling remote changes from Google Drive...');
    try {
      if (!_isInitialized || !(_backupService?.isSignedIn ?? false)) {
        _log('⚠️ Cannot pull - not initialized or not signed in');
        return false;
      }
      if (!_pullEnabled) {
        _log('⏸️ Pull disabled - skipping');
        return false;
      }

      final pulledCount = await _performDeltaPull();
      if (pulledCount != null && pulledCount >= 0) {
        _log('✅ Pulled $pulledCount changes from Google Drive');
        return true;
      }
      return false;
    } catch (e) {
      _log('❌ Pull failed: $e', level: LogLevel.error);
      return false;
    }
  }

  void dispose() {
    _stopMonitoring();
    _syncResultController.close();
    _log('🛑 Unified Sync Coordinator disposed');
  }
}
