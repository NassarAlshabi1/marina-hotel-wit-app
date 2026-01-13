import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_logs.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_delta_sync.dart';
import 'google_drive_logger.dart';
import 'google_drive_conflict_resolver.dart'; // Added import
import 'local_db.dart';
import 'data_usage_manager.dart';
import 'sync_core/unified_lock_manager.dart';
import 'sync_constants.dart';
import 'sync_performance_optimizer.dart';
import 'logging/log_models.dart';
import 'sync_core/retry_strategy.dart';

enum SyncTrigger {
  manual,
  appForeground,
  localChange,
  periodic,
  scheduled,
}

enum SyncMode {
  deltaOnly,
  fullBackup,
  smart,
}

enum SyncPhase {
  idle,
  authenticating,
  pushing,
  pulling,
  conflict,
  completed,
  failed,
}

enum _SyncStartResult {
  ok,
  notInitialized,
  notSignedIn,
  alreadySyncing,
}

sealed class _PerformSyncResult {}

class _PerformSyncOk extends _PerformSyncResult {}

class _PerformSyncNotInitialized extends _PerformSyncResult {}

class _PerformSyncNotSignedIn extends _PerformSyncResult {}

class _PerformSyncAlreadyInProgress extends _PerformSyncResult {
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
  final Lock _pendingChangesLock = Lock();
  
  static const Duration _syncTimeout = Duration(minutes: 5);
  final RetryStrategy _retryStrategy = RetryStrategy(config: RetryConfig.balanced);
  final _syncResultController = StreamController<SyncResult>.broadcast();
  
  bool _pushEnabled = true;
  bool _pullEnabled = true;
  int _debounceSeconds = _defaultDebounceSeconds;
  int _pullIntervalMinutes = _defaultPullIntervalMinutes;
  int _fullBackupIntervalHours = _defaultFullBackupHours;
  
  static const String _prefsPushEnabledKey = 'gd_unified_push_enabled';
  static const String _prefsPullEnabledKey = 'gd_unified_pull_enabled';
  static const String _prefsDebounceSecondsKey = 'gd_unified_debounce_seconds';
  static const String _prefsPullIntervalKey = 'gd_unified_pull_interval_minutes';
  static const String _prefsFullBackupIntervalKey = 'gd_unified_full_backup_hours';
  static const String _prefsSyncModeKey = 'gd_unified_sync_mode';
  static const String _prefsLastPushKey = 'gd_unified_last_push';
  static const String _prefsLastPullKey = 'gd_unified_last_pull';
  static const String _prefsLastFullBackupKey = 'gd_unified_last_full_backup';
  
  static const int _defaultDebounceSeconds = 1;  // انتظار قصير جداً بعد الحفظ (ثانية واحدة فقط لتجميع العمليات المتعددة)
  static const int _maxDebounceSeconds = 3;      // الحد الأقصى للانتظار (غير مستخدم حالياً)
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
    _lastFullBackupTime = _parseTimestamp(prefs.getString(_prefsLastFullBackupKey));
    
    // تسجيل callback لإعادة تشغيل المراقبة بعد إعادة فتح قاعدة البيانات
    DatabaseManager.registerReopenCallback(() {
      _log('🔔 Database reopened - restarting monitoring...');
      _database = DatabaseManager.instance;
      if (backupService.isSignedIn && _pushEnabled) {
        _restartOutboxMonitoring();
      }
    });
    
    if (backupService.isSignedIn) {
      await _startMonitoring();
    }
    
    _isInitialized = true;
    _log('✅ Unified Sync Coordinator initialized successfully');
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (!prefs.containsKey(_prefsPushEnabledKey)) {
      await prefs.setBool(_prefsPushEnabledKey, true);
    }
    if (!prefs.containsKey(_prefsPullEnabledKey)) {
      await prefs.setBool(_prefsPullEnabledKey, true);
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
    
    _pushEnabled = prefs.getBool(_prefsPushEnabledKey) ?? true;
    _pullEnabled = prefs.getBool(_prefsPullEnabledKey) ?? true;
    _debounceSeconds = prefs.getInt(_prefsDebounceSecondsKey) ?? _defaultDebounceSeconds;
    _pullIntervalMinutes = prefs.getInt(_prefsPullIntervalKey) ?? _defaultPullIntervalMinutes;
    _fullBackupIntervalHours = prefs.getInt(_prefsFullBackupIntervalKey) ?? _defaultFullBackupHours;
  }

  Future<void> onSignInChanged(bool isSignedIn) async {
    _log('🔐 Sign-in status changed: $isSignedIn');
    
    if (isSignedIn) {
      await _startMonitoring();
      // عند تسجيل الدخول، نسحب التغييرات فقط بدون إنشاء نسخة احتياطية جديدة
      await performSync(trigger: SyncTrigger.manual, mode: SyncMode.deltaOnly);
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
    
    // تحديث database instance للتأكد من استخدام أحدث اتصال
    _database = DatabaseManager.instance;
    
    // مراقبة تغييرات outbox للمزامنة التلقائية
    _outboxSubscription?.cancel();
    if (_pushEnabled && _database != null) {
      _outboxSubscription = (_database!.select(_database!.outbox)).watch().listen(
        (_) {
          _log('📦 Detected change in outbox', level: LogLevel.debug);
          notifyLocalChange();
        },
        onError: (error) {
          _log('❌ Outbox watch error: $error', level: LogLevel.error);
          // إعادة فتح الـ stream بعد 5 ثوانٍ من حدوث خطأ
          Future.delayed(const Duration(seconds: 5), () {
            if (_pushEnabled && _database != null) {
              _restartOutboxMonitoring();
            }
          });
        },
        onDone: () {
          _log('⚠️ Outbox watch stream closed', level: LogLevel.warning);
          // إعادة فتح الـ stream بعد 3 ثوانٍ من إغلاقه
          Future.delayed(const Duration(seconds: 3), () {
            if (_pushEnabled && _database != null && _backupService?.isSignedIn == true) {
              _restartOutboxMonitoring();
            }
          });
        },
        cancelOnError: false,
      );
      _log('✅ Started outbox monitoring for auto-sync');
    }
    
    if (_pullEnabled) {
      _pullCheckTimer?.cancel();
      _pullCheckTimer = Timer.periodic(
        Duration(minutes: _pullIntervalMinutes),
        (_) => _handlePeriodicPull(),
      );
      _log('⏰ Started periodic pull monitoring (every $_pullIntervalMinutes minutes)');
    }
    
    _scheduleFullBackup();
  }

  void _restartOutboxMonitoring() {
    if (!_isInitialized || !(_backupService?.isSignedIn ?? false) || !_pushEnabled) {
      _log('⚠️ Cannot restart outbox monitoring: conditions not met');
      return;
    }
    
    _log('🔄 Restarting outbox monitoring...');
    _outboxSubscription?.cancel();
    
    // تحديث database instance قبل استخدامها - إصلاح "Can't re-open a database"
    // هذا ضروري لأن _database قد تكون تشير إلى instance مغلقة
    try {
      _database = DatabaseManager.instance;
    } catch (e) {
      _log('❌ Cannot get database instance: $e', level: LogLevel.error);
      return;
    }
    
    if (_database == null) {
      _log('⚠️ Database instance is null - cannot restart monitoring');
      return;
    }
    
    try {
      _outboxSubscription = (_database!.select(_database!.outbox)).watch().listen(
        (_) {
          _log('📦 Detected change in outbox', level: LogLevel.debug);
          notifyLocalChange();
        },
        onError: (error) {
          _log('❌ Outbox watch error: $error', level: LogLevel.error);
          Future.delayed(const Duration(seconds: 5), () {
            if (_pushEnabled && _database != null) {
              _restartOutboxMonitoring();
            }
          });
        },
        onDone: () {
          _log('⚠️ Outbox watch stream closed', level: LogLevel.warning);
          Future.delayed(const Duration(seconds: 3), () {
            if (_pushEnabled && _database != null && _backupService?.isSignedIn == true) {
              _restartOutboxMonitoring();
            }
          });
        },
        cancelOnError: false,
      );
      _log('✅ Outbox monitoring restarted successfully');
    } catch (e) {
      _log('❌ Failed to restart outbox monitoring: $e', level: LogLevel.error);
    }
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
      await performSync(trigger: SyncTrigger.scheduled, mode: SyncMode.fullBackup);
      
      _periodicSyncTimer = Timer.periodic(
        Duration(hours: _fullBackupIntervalHours),
        (_) => performSync(trigger: SyncTrigger.scheduled, mode: SyncMode.fullBackup),
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
  Future<void> notifyLocalChange({String? table, String? operation, int count = 1}) async {
    if (!_isInitialized) return;
    
    await _pendingChangesLock.synchronized(() async {
      final now = DateTime.now();
      
      if (!_hasPendingChanges) {
        _firstChangeTime = now;
        _log('💾 Save action detected: ${table ?? "unknown"} ($operation)', level: LogLevel.debug);
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
    _log('🚀 Triggering sync in ${effectiveDebounce}s (${_pendingChangesCount} changes pending)', 
        level: LogLevel.debug);
    
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
      await performSync(trigger: SyncTrigger.appForeground, mode: SyncMode.smart);
    });
  }

  Future<void> _handlePeriodicPull() async {
    if (!_isSyncing && (_backupService?.isSignedIn ?? false)) {
      if (_pullEnabled) {
        _log('🔄 Periodic pull check triggered');
        await performSync(trigger: SyncTrigger.periodic, mode: SyncMode.deltaOnly);
      }
    }
  }

  Future<SyncResult> performSync({
    required SyncTrigger trigger,
    SyncMode mode = SyncMode.smart,
  }) async {
    // Defensive check: Never sync during database restore
    if (DatabaseManager.isRestoring) {
      _log('⏸️ Sync blocked: database is being restored', level: LogLevel.warning);
      return SyncResult.failure(
        message: 'Sync skipped: database restore in progress',
        phase: SyncPhase.idle,
      );
    }
    
    final lockResult = await UnifiedLockManager.instance.acquire(
      category: LockCategory.mainSync,
      holder: 'GoogleDriveUnifiedSyncCoordinator.performSync',
      priority: LockPriority.high,
    );
    
    if (!lockResult.acquired) {
      _log('❌ فشل الحصول على القفل: ${lockResult.failureReason}');
      return SyncResult.failure(
        message: 'Failed to acquire lock: ${lockResult.failureReason}',
        phase: SyncPhase.idle,
      );
    }
    
    try {
      return await _performSyncLocked(trigger, mode);
    } finally {
      UnifiedLockManager.instance.release(
        category: LockCategory.mainSync,
        holder: 'GoogleDriveUnifiedSyncCoordinator.performSync',
      );
    }
  }

  Future<SyncResult> _performSyncLocked(SyncTrigger trigger, SyncMode mode) async {
    _PerformSyncResult canStartResult;
  
    if (!_isInitialized) {
      canStartResult = _PerformSyncNotInitialized();
    } else if (!(_backupService?.isSignedIn ?? false)) {
      canStartResult = _PerformSyncNotSignedIn();
    } else if (_isSyncing) {
      if (_syncStartTime != null) {
        final elapsed = DateTime.now().difference(_syncStartTime!);
        if (elapsed > _syncTimeout) {
          _log('⚠️ Sync timeout detected (${elapsed.inSeconds}s) - resetting state');
          _isSyncing = false;
          _syncStartTime = null;
          _currentPhase = SyncPhase.idle;
          canStartResult = _PerformSyncOk();
        } else {
          canStartResult = _PerformSyncAlreadyInProgress(elapsed.inSeconds);
        }
      } else {
        _log('⚠️ Inconsistent state: _isSyncing=true but _syncStartTime=null - resetting');
        _isSyncing = false;
        canStartResult = _PerformSyncOk();
      }
    } else {
      canStartResult = _PerformSyncOk();
    }
    
    if (canStartResult is _PerformSyncOk && !_isSyncing) {
      _isSyncing = true;
      _syncStartTime = DateTime.now();
      _currentPhase = SyncPhase.authenticating;
    }
    
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
        _log('⏸️ Sync already in progress (${elapsed}s elapsed) - skipping $trigger');
        if (trigger == SyncTrigger.periodic || trigger == SyncTrigger.scheduled) {
          return SyncResult.success(
            message: 'Sync already in progress - not an error for periodic sync',
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
      final enforceOptimizer = trigger == SyncTrigger.periodic || trigger == SyncTrigger.scheduled;
      if (shouldSkip) {
        if (enforceOptimizer) {
          _log('⏸️ Optimizer suggests skipping sync');
          return SyncResult.failure(
            message: 'Skipped by performance optimizer',
            phase: SyncPhase.idle,
          );
        } else {
          _log('⚠️ Optimizer suggested skipping but trigger $trigger requires immediate sync');
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
        await prefs.setString(_prefsLastFullBackupKey, _lastFullBackupTime!.toIso8601String());
      } else if (effectiveMode == SyncMode.deltaOnly) {
        pulled = await _performDeltaPull();
      } else {
        if (_hasPendingChanges || trigger == SyncTrigger.localChange) {
          pushed = await _performDeltaPush();
        }
        
        if (trigger == SyncTrigger.appForeground || 
            trigger == SyncTrigger.periodic || 
            trigger == SyncTrigger.manual) {
          
          if (effectiveMode == SyncMode.smart) {
             // Smart Sync: Try Delta first, then check Full Backup if needed
             pulled = await _performDeltaPull();
             
             // Check for full backup if delta yielded nothing or periodically
             // Or if this is a manual sync or app foreground where we want to be sure
             if ((pulled ?? 0) == 0) {
                await _performScanAndRestoreFullBackup();
             }
          } else {
             pulled = await _performDeltaPull();
          }
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
      if (errorMessage.contains('NetworkException') || errorMessage.contains('SocketException')) {
        userFriendlyMessage = 'خطأ في الاتصال بالإنترنت';
      } else if (errorMessage.contains('Unauthorized') || errorMessage.contains('401')) {
        userFriendlyMessage = 'انتهت صلاحية تسجيل الدخول - يرجى تسجيل الدخول مرة أخرى';
      } else if (errorMessage.contains('QuotaExceeded') || errorMessage.contains('Storage')) {
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
      _isSyncing = false;
      _syncStartTime = null;
      _currentPhase = SyncPhase.idle;
    }
  }

  Future<SyncResult> performSyncWithRetry({
    required SyncTrigger trigger,
    SyncMode mode = SyncMode.smart,
  }) async {
    return _retryStrategy.execute<SyncResult>(
      operation: () => performSync(trigger: trigger, mode: mode),
      shouldRetry: (error) {
        final errorStr = error.toString().toLowerCase();
        if (errorStr.contains('unauthorized') || errorStr.contains('401')) {
          return false;
        }
        if (errorStr.contains('quotaexceeded') || errorStr.contains('storage')) {
          return false;
        }
        return true;
      },
      onRetry: (attempt, error) {
        _log('🔄 إعادة محاولة المزامنة ($attempt): $error');
      },
    );
  }

  SyncMode _determineEffectiveMode(SyncMode requestedMode, SyncTrigger trigger) {
    if (requestedMode != SyncMode.smart) {
      return requestedMode;
    }
    
    if (trigger == SyncTrigger.scheduled) {
      return SyncMode.fullBackup;
    }
    
    if (_lastFullBackupTime == null) {
      return SyncMode.fullBackup;
    }
    
    final hoursSinceFullBackup = DateTime.now().difference(_lastFullBackupTime!).inHours;
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
        await prefs.setString(_prefsLastPushKey, _lastPushTime!.toIso8601String());
        
        if (result.changesCount > 0) {
          await DataUsageManager.instance.recordDataUsage(
            (result.changesCount * SyncConstants.estimatedBytesPerDeltaChange) / 1024 / 1024,
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
        await prefs.setString(_prefsLastPullKey, _lastPullTime!.toIso8601String());
        
        if (result.changesCount > 0) {
          await DataUsageManager.instance.recordDataUsage(
            (result.changesCount * SyncConstants.estimatedBytesPerDeltaChange) / 1024 / 1024,
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
      final baseMetadata = metadata is Map ? Map<String, dynamic>.from(metadata) : <String, dynamic>{};
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

  /// فحص واستعادة النسخ الاحتياطية الكاملة (مع حل النزاع)
  /// 
  /// ⚠️ ARCHITECTURAL NOTE: Full database restore CANNOT be performed during active sync
  /// because it requires closing the database, stopping all sync operations, and restarting.
  /// 
  /// This method now DETECTS newer backups and SCHEDULES them for deferred restore,
  /// allowing the user to be prompted to restore at an appropriate time.
  Future<void> _performScanAndRestoreFullBackup() async {
    _log('🔍 Checking for full backups from other devices...');
    try {
      // 1. List backups
      final backupFiles = await _backupService!.listBackupFiles(limit: 5);
      if (backupFiles.isEmpty) return;

      // 2. Filter for newer backups from OTHER devices
      // Sorting is crucial: newest first
      backupFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      final latestBackup = backupFiles.first;

      final myDeviceId = _deltaSync?.deviceId;
      final backupDeviceId = latestBackup.appProperties['device_id'];
      
      // Ignore my own backups
      if (backupDeviceId == myDeviceId) {
        _log('✓ Latest backup is from this device. No restore needed.');
        return;
      }

      // Check timestamp locally
      final prefs = await SharedPreferences.getInstance();
      final lastRestoredTsStr = prefs.getString('gd_last_restored_full_ts');
      final lastRestoredTs = _parseTimestamp(lastRestoredTsStr);

      if (lastRestoredTs != null && latestBackup.createdTime.isBefore(lastRestoredTs)) {
         _log('✓ Latest remote backup is older than last restored one.');
         return;
      }
      
      _log('🆕 New full backup found from $backupDeviceId.');
      _log('⚠️ Full restore requires stopping all operations and cannot be done during sync.');
      _log('💡 Flagging backup for deferred restore...');
      
      // Store pending restore info for user prompt
      // The UI should detect this flag and prompt the user to restore
      await prefs.setString('pending_restore_backup_id', latestBackup.fileId);
      if (backupDeviceId != null) {
        await prefs.setString('pending_restore_device_id', backupDeviceId);
      }
      await prefs.setString('pending_restore_timestamp', latestBackup.createdTime.toIso8601String());
      await prefs.setBool('pending_restore_available', true);
      
      _log('✅ Backup flagged for deferred restore.');
      _log('ℹ️ User will be prompted to restore at next app launch or manually.');
      
      // REMOVED UNSAFE CODE:
      // The following code was UNSAFE and could cause data corruption:
      // - await _backupService!.restoreFromBackup(mergedData);
      // 
      // Full restore MUST use this flow:
      // 1. User initiates restore from UI
      // 2. UI calls DatabaseManager.closeForRestore()
      // 3. Sync operations stop
      // 4. Database closes
      // 5. Restore operations execute
      // 6. DatabaseManager.reopenAfterRestore()
      // 7. Sync operations restart
      //
      // See backup_provider.dart for the correct implementation pattern.

    } catch (e) {
      _log('❌ Error checking for full backups: $e', level: LogLevel.error);
    }
  }

  Future<void> setPushEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsPushEnabledKey, enabled);
    _pushEnabled = enabled;
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

  void dispose() {
    _stopMonitoring();
    _syncResultController.close();
    _log('🛑 Unified Sync Coordinator disposed');
  }
}
