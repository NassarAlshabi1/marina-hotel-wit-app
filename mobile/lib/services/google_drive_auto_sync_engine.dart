import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_logs.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_conflict_resolver.dart';
import 'google_drive_logger.dart';
import 'google_drive_unified_sync_coordinator.dart';
import 'unified_sync_orchestrator.dart';
import 'sync_locks.dart';
import 'sync_constants.dart';
import 'local_db.dart';
import 'logging/log_models.dart';

class RetryConfig {
  final int maxRetries;
  final int baseDelaySeconds;
  final int maxDelaySeconds;
  final double backoffMultiplier;

  const RetryConfig({
    this.maxRetries = 5,
    this.baseDelaySeconds = 2,
    this.maxDelaySeconds = 300,
    this.backoffMultiplier = 2.0,
  });

  int calculateDelay(int attemptNumber) {
    final delay =
        baseDelaySeconds * pow(backoffMultiplier, attemptNumber).toInt();
    return min(delay, maxDelaySeconds);
  }
}

class AutoSyncEngineState {
  final bool isRunning;
  final bool hasNetworkConnection;
  final bool isSignedIn;
  final int pendingChangesCount;
  final DateTime? lastSuccessfulSync;
  final int failedAttempts;
  final DateTime? nextRetryAt;
  final String? lastError;

  const AutoSyncEngineState({
    required this.isRunning,
    required this.hasNetworkConnection,
    required this.isSignedIn,
    required this.pendingChangesCount,
    this.lastSuccessfulSync,
    this.failedAttempts = 0,
    this.nextRetryAt,
    this.lastError,
  });

  AutoSyncEngineState copyWith({
    bool? isRunning,
    bool? hasNetworkConnection,
    bool? isSignedIn,
    int? pendingChangesCount,
    DateTime? lastSuccessfulSync,
    int? failedAttempts,
    DateTime? nextRetryAt,
    String? lastError,
  }) {
    return AutoSyncEngineState(
      isRunning: isRunning ?? this.isRunning,
      hasNetworkConnection: hasNetworkConnection ?? this.hasNetworkConnection,
      isSignedIn: isSignedIn ?? this.isSignedIn,
      pendingChangesCount: pendingChangesCount ?? this.pendingChangesCount,
      lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      nextRetryAt: nextRetryAt,
      lastError: lastError,
    );
  }
}

enum _StartResult {
  ok,
  notInitialized,
  alreadyRunning,
}

class AutoSyncEngine with WidgetsBindingObserver {
  AutoSyncEngine._();
  static final instance = AutoSyncEngine._();

  GoogleDriveBackupService? _backupService;
  GoogleDriveUnifiedSyncCoordinator? _coordinator;
  UnifiedSyncOrchestrator? _orchestrator;
  GoogleDriveConflictResolver? _conflictResolver;
  GoogleDriveLogger? _logger;
  // ignore: unused_field
  AppDatabase? _database;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<SyncResult>? _syncResultSubscription;
  Timer? _retryTimer;
  Timer? _healthCheckTimer;

  bool _isInitialized = false;
  bool _isRunning = false;
  bool _hasNetworkConnection = false;
  bool _isSignedIn = false;
  int _pendingChangesCount = 0;
  DateTime? _lastSuccessfulSync;
  int _failedAttempts = 0;
  DateTime? _nextRetryAt;
  String? _lastError;

  final _stateController = StreamController<AutoSyncEngineState>.broadcast();

  static const String _prefsEnabledKey = 'auto_sync_engine_enabled';
  static const String _prefsDebounceSecondsKey = 'auto_sync_engine_debounce';
  static const String _prefsPullIntervalKey = 'auto_sync_engine_pull_interval';
  static const String _prefsRetryEnabledKey = 'auto_sync_engine_retry_enabled';

  final RetryConfig _retryConfig = const RetryConfig(
    maxRetries: 5,
    baseDelaySeconds: 2,
    maxDelaySeconds: 300,
    backoffMultiplier: 2.0,
  );

  Stream<AutoSyncEngineState> get stateStream => _stateController.stream;

  AutoSyncEngineState get currentState => AutoSyncEngineState(
        isRunning: _isRunning,
        hasNetworkConnection: _hasNetworkConnection,
        isSignedIn: _isSignedIn,
        pendingChangesCount: _pendingChangesCount,
        lastSuccessfulSync: _lastSuccessfulSync,
        failedAttempts: _failedAttempts,
        nextRetryAt: _nextRetryAt,
        lastError: _lastError,
      );

  void _log(String message, {LogLevel level = LogLevel.info}) {
    DebugLogs.add('AutoSyncEngine', message);
    debugPrint('[AutoSyncEngine] $message');
    _logger?.log(message, level: level, tag: 'AUTO_SYNC');
  }

  void _emitState() {
    _stateController.add(currentState);
  }

  Future<void> initialize({
    required GoogleDriveBackupService backupService,
    required AppDatabase database,
    GoogleDriveLogger? logger,
  }) async {
    if (_isInitialized) {
      _log('⚠️ Engine already initialized');
      return;
    }

    _log('🚀 Initializing Auto Sync Engine...');

    _backupService = backupService;
    _database = database;
    _logger = logger;

    _coordinator = GoogleDriveUnifiedSyncCoordinator.instance;
    await _coordinator!.initialize(
      backupService: backupService,
      database: database,
      logger: logger,
    );

    _orchestrator = UnifiedSyncOrchestrator.instance;
    await _orchestrator!.initialize(database: database);

    _conflictResolver = GoogleDriveConflictResolver.instance;
    _conflictResolver!.initialize(logger);

    await _loadSettings();

    _isSignedIn = backupService.isSignedIn;

    WidgetsBinding.instance.addObserver(this);

    _isInitialized = true;
    _log('✅ Auto Sync Engine initialized');
    _emitState();
  }

  Future<void> start() async {
    final canStart = await SyncLocks.autoEngineLock.synchronized(() async {
      if (!_isInitialized) return _StartResult.notInitialized;
      if (_isRunning) return _StartResult.alreadyRunning;

      _isRunning = true;
      return _StartResult.ok;
    });

    if (canStart == _StartResult.notInitialized) {
      _log('❌ Cannot start - engine not initialized');
      return;
    }

    if (canStart == _StartResult.alreadyRunning) {
      _log('⚠️ Engine already running');
      return;
    }

    _log('🎬 Starting Auto Sync Engine...');
    _emitState();

    _setupConnectivityListener();
    _setupSyncResultListener();
    _setupDataStreamListener();
    _startHealthCheck();

    if (_isSignedIn && _hasNetworkConnection) {
      await _performInitialSync();
    }

    _log('✅ Auto Sync Engine started successfully');
    _log('   📡 Network monitoring: ACTIVE');
    _log('   🔄 Lifecycle monitoring: ACTIVE');
    _log('   💾 Data stream listening: ACTIVE');
    _log('   ❤️ Health checks: ACTIVE');
  }

  void stop() {
    SyncLocks.autoEngineLock.synchronized(() {
      if (!_isRunning) return;

      _log('🛑 Stopping Auto Sync Engine...');

      _isRunning = false;

      _connectivitySubscription?.cancel();
      _connectivitySubscription = null;

      _syncResultSubscription?.cancel();
      _syncResultSubscription = null;

      _retryTimer?.cancel();
      _retryTimer = null;

      _healthCheckTimer?.cancel();
      _healthCheckTimer = null;

      WidgetsBinding.instance.removeObserver(this);

      _emitState();
      _log('✅ Auto Sync Engine stopped');
    });
  }

  Future<void> restart() async {
    _log('🔄 Restarting Auto Sync Engine...');
    stop();
    await Future.delayed(const Duration(milliseconds: 500));
    await start();
    _log('✅ Auto Sync Engine restarted');
  }

  void _setupConnectivityListener() {
    _log('📡 Setting up connectivity listener...');

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        final wasConnected = _hasNetworkConnection;
        _hasNetworkConnection =
            results.any((r) => r != ConnectivityResult.none);

        _log('📡 Network status changed: $_hasNetworkConnection');
        _emitState();

        if (!wasConnected && _hasNetworkConnection) {
          _log('🌐 Network restored - triggering sync...');
          await _onNetworkRestored();
        } else if (wasConnected && !_hasNetworkConnection) {
          _log('📴 Network lost - canceling pending operations');
          _retryTimer?.cancel();
        }
      },
      onError: (error) {
        _log('❌ Connectivity listener error: $error', level: LogLevel.error);
      },
    );

    Connectivity().checkConnectivity().then((results) {
      _hasNetworkConnection = results.any((r) => r != ConnectivityResult.none);
      _log('📡 Initial network status: $_hasNetworkConnection');
      _emitState();
    });
  }

  void _setupSyncResultListener() {
    _log('📊 Setting up sync result listener...');

    _syncResultSubscription = _coordinator!.syncResults.listen(
      (result) {
        if (result.success) {
          _lastSuccessfulSync = result.timestamp;
          _failedAttempts = 0;
          _nextRetryAt = null;
          _lastError = null;

          if (result.pushedChanges != null && result.pushedChanges! > 0) {
            _pendingChangesCount =
                max(0, _pendingChangesCount - result.pushedChanges!);
          }

          _log(
              '✅ Sync succeeded: pushed=${result.pushedChanges}, pulled=${result.pulledChanges}');
        } else {
          _failedAttempts++;
          _lastError = result.error ?? result.message;

          final errorDetails = result.error != null
              ? '${result.message} - ${result.error}'
              : result.message;

          _log('❌ Sync failed (attempt $_failedAttempts): $errorDetails',
              level: LogLevel.error);

          final prefs = SharedPreferences.getInstance();
          prefs.then((p) async {
            final retryEnabled = p.getBool(_prefsRetryEnabledKey) ?? true;
            if (retryEnabled && _failedAttempts < _retryConfig.maxRetries) {
              await _scheduleRetry();
            } else if (_failedAttempts >= _retryConfig.maxRetries) {
              _log('🚫 Max retries reached - stopping automatic retries',
                  level: LogLevel.warning);
            }
          });
        }

        _emitState();
      },
      onError: (error) {
        _log('❌ Sync result listener error: $error', level: LogLevel.error);
      },
    );
  }

  void _setupDataStreamListener() {
    _log('💾 Setting up data stream listener...');

    _coordinator!.syncResults.listen((result) {
      if (result.success &&
          result.pushedChanges != null &&
          result.pushedChanges! > 0) {
        _log('📤 Data changes detected and pushed: ${result.pushedChanges}');
      }
    });
  }

  void _startHealthCheck() {
    _log('❤️ Starting health check monitor...');

    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _performHealthCheck(),
    );
  }

  Future<void> _performHealthCheck() async {
    final shouldRun =
        await SyncLocks.autoEngineLock.synchronized(() => _isRunning);
    if (!shouldRun) return;

    _log('❤️ Performing health check...');

    final hadConnection = _hasNetworkConnection;
    final results = await Connectivity().checkConnectivity();
    _hasNetworkConnection = results.any((r) => r != ConnectivityResult.none);

    final wasSignedIn = _isSignedIn;
    _isSignedIn = _backupService?.isSignedIn ?? false;

    if (_hasNetworkConnection && _isSignedIn) {
      if (_pendingChangesCount > 0) {
        _log('❤️ Health check: found pending changes - triggering sync');
        await _orchestrator!.syncNow(
          push: true,
          pull: true,
          reason: 'health_check',
        );
      }

      if (!hadConnection || !wasSignedIn) {
        _log('❤️ Health check: connection/auth restored - triggering pull');
        await _orchestrator!.syncNow(
          push: false,
          pull: true,
          reason: 'health_check_pull',
        );
      }
    }

    _emitState();
  }

  Future<void> _onNetworkRestored() async {
    _log('🌐 Network restored handler triggered');

    _retryTimer?.cancel();
    _failedAttempts = 0;

    if (!_isSignedIn) {
      _log('🔐 Attempting silent sign-in...');
      try {
        final account = await _backupService!.attemptSilentSignIn();
        if (account != null) {
          _isSignedIn = true;
          await _orchestrator!.onDriveSignInChanged(true);
          _log('✅ Silent sign-in successful');
        } else {
          _log('⚠️ Silent sign-in failed - user intervention needed');
          return;
        }
      } catch (e) {
        _log('❌ Silent sign-in error: $e');
        return;
      }
    }

    if (_pendingChangesCount > 0) {
      _log(
          '📤 Syncing ${_pendingChangesCount} pending changes after network restore');
      await _orchestrator!.syncNow(
        push: true,
        pull: false,
        reason: 'network_restore_push',
      );
    } else {
      _log('📥 Checking for remote changes after network restore');
      await _orchestrator!.syncNow(
        push: false,
        pull: true,
        reason: 'network_restore_pull',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('🔄 App lifecycle changed: ${state.name}');

    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    } else if (state == AppLifecycleState.paused) {
      _onAppPaused();
    } else if (state == AppLifecycleState.inactive) {
      _onAppInactive();
    }
  }

  Future<void> _onAppResumed() async {
    if (!_isRunning) return;

    _log('📱 App resumed - triggering foreground sync');

    if (!_hasNetworkConnection) {
      _log('📴 No network - checking connectivity first');
      final results = await Connectivity().checkConnectivity();
      _hasNetworkConnection = results.any((r) => r != ConnectivityResult.none);
      _emitState();
    }

    if (!_hasNetworkConnection) {
      _log('📴 Still no network - skipping sync');
      return;
    }

    if (!_isSignedIn) {
      _log('🔐 Not signed in - attempting silent sign-in');
      try {
        final account = await _backupService!.attemptSilentSignIn();
        if (account != null) {
          _isSignedIn = true;
          await _orchestrator!.onDriveSignInChanged(true);
        } else {
          _log('⚠️ Silent sign-in failed');
          return;
        }
      } catch (e) {
        _log('❌ Silent sign-in error: $e');
        return;
      }
    }

    Future.delayed(SyncConstants.appForegroundDelay, () async {
      try {
        await _orchestrator!.onAppForeground();
      } catch (e) {
        _log('❌ Error on app foreground sync: $e', level: LogLevel.error);
      }
    });
  }

  void _onAppPaused() {
    _log('⏸️ App paused');

    if (_pendingChangesCount > 0 && _hasNetworkConnection && _isSignedIn) {
      _log('💾 App paused with pending changes - quick sync before background');

      _orchestrator!
          .syncNow(
        push: true,
        pull: false,
        reason: 'app_paused',
      )
          .then((result) {
        if (result) {
          _log('✅ Quick sync before background completed');
        }
      }).catchError((error) {
        _log('⚠️ Quick sync before background failed: $error');
      });
    }
  }

  void _onAppInactive() {
    _log('💤 App inactive');
  }

  void notifyDataChange({
    required String table,
    required String operation,
    int count = 1,
    Map<String, dynamic>? recordData,
  }) {
    if (!_isRunning) return;

    SyncLocks.autoEngineLock.synchronized(() {
      _pendingChangesCount += count;
    });

    _emitState();

    _log(
        '💾 Data change detected: $table/$operation (count=$count, total pending=$_pendingChangesCount)');

    _orchestrator!.notifyLocalChange(
      table: table,
      operation: operation,
    );
  }

  Future<void> _scheduleRetry() async {
    if (_failedAttempts >= _retryConfig.maxRetries) {
      _log('🚫 Max retries reached - stopping retries',
          level: LogLevel.warning);
      return;
    }

    final delaySeconds = _retryConfig.calculateDelay(_failedAttempts);
    _nextRetryAt = DateTime.now().add(Duration(seconds: delaySeconds));

    _log('⏰ Scheduling retry #$_failedAttempts in $delaySeconds seconds');
    _emitState();

    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delaySeconds), () async {
      _log('🔄 Executing scheduled retry #$_failedAttempts');

      if (!_hasNetworkConnection) {
        _log('📴 No network for retry - waiting for network restore');
        return;
      }

      if (!_isSignedIn) {
        _log('🔐 Not signed in for retry - attempting sign-in');
        try {
          final account = await _backupService!.attemptSilentSignIn();
          if (account == null) {
            _log('⚠️ Retry sign-in failed - scheduling next retry');
            await _scheduleRetry();
            return;
          }
          _isSignedIn = true;
          await _orchestrator!.onDriveSignInChanged(true);
        } catch (e) {
          _log('❌ Retry sign-in error: $e');
          await _scheduleRetry();
          return;
        }
      }

      await _orchestrator!.syncNow(
        push: true,
        pull: true,
        reason: 'auto_retry',
      );
    });
  }

  Future<void> _performInitialSync() async {
    _log('🎬 Performing initial sync...');

    await Future.delayed(const Duration(seconds: 2));

    await _orchestrator!.syncNow(
      push: true,
      pull: true,
      reason: 'initial_sync',
    );
  }

  Future<void> onSignInChanged(bool isSignedIn) async {
    _log('🔐 Sign-in status changed: $isSignedIn');

    _isSignedIn = isSignedIn;
    _emitState();

    if (isSignedIn) {
      _failedAttempts = 0;
      _nextRetryAt = null;

      await _coordinator!.onSignInChanged(true);

      if (_hasNetworkConnection && _isRunning) {
        await _performInitialSync();
      }
    } else {
      await _orchestrator!.onDriveSignInChanged(false);
      _retryTimer?.cancel();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey(_prefsEnabledKey)) {
      await prefs.setBool(_prefsEnabledKey, true);
    }
    if (!prefs.containsKey(_prefsDebounceSecondsKey)) {
      await prefs.setInt(_prefsDebounceSecondsKey, 5);
    }
    if (!prefs.containsKey(_prefsPullIntervalKey)) {
      await prefs.setInt(_prefsPullIntervalKey, 2);
    }
    if (!prefs.containsKey(_prefsRetryEnabledKey)) {
      await prefs.setBool(_prefsRetryEnabledKey, true);
    }

    final debounce = prefs.getInt(_prefsDebounceSecondsKey) ?? 5;
    await _orchestrator!.setDebounceSeconds(debounce);

    final pullInterval = prefs.getInt(_prefsPullIntervalKey) ?? 2;
    await _orchestrator!.setPullInterval(pullInterval);

    final strategy = await _conflictResolver!.getStrategy();
    _log(
        '⚙️ Settings loaded: debounce=${debounce}s, pull=${pullInterval}min, conflicts=$strategy');
  }

  Future<void> setDebounceSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsDebounceSecondsKey, seconds);
    await _orchestrator!.setDebounceSeconds(seconds);
    _log('⏱️ Debounce updated: ${seconds}s');
  }

  Future<void> setPullInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsPullIntervalKey, minutes);
    await _orchestrator!.setPullInterval(minutes);
    _log('⏰ Pull interval updated: ${minutes}min');
  }

  Future<void> setConflictStrategy(ConflictResolutionStrategy strategy) async {
    await _conflictResolver!.setStrategy(strategy);
    _log('🤝 Conflict strategy updated: ${strategy.name}');
  }

  Future<void> setRetryEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsRetryEnabledKey, enabled);

    if (!enabled) {
      _retryTimer?.cancel();
      _nextRetryAt = null;
      _emitState();
    }

    _log('🔄 Auto-retry ${enabled ? 'enabled' : 'disabled'}');
  }

  Future<SyncResult> forceSyncNow() async {
    _log('🚀 Force sync triggered by user');

    if (!_hasNetworkConnection) {
      final message = 'لا يوجد اتصال بالإنترنت';
      _log('📴 $message');
      return SyncResult.failure(
        message: message,
        error: 'NetworkUnavailable',
        phase: SyncPhase.idle,
      );
    }

    if (!_isSignedIn) {
      final message = 'غير مسجل الدخول في Google Drive';
      _log('🔐 $message');
      return SyncResult.failure(
        message: message,
        error: 'NotSignedIn',
        phase: SyncPhase.authenticating,
      );
    }

    final ok = await _orchestrator!.syncNow(
      push: true,
      pull: true,
      reason: 'manual_force',
    );

    if (ok) {
      return SyncResult.success(
        message: 'Sync completed successfully',
      );
    }

    return SyncResult.failure(
      message: 'فشلت المزامنة',
      error: 'UnifiedSyncFailed',
      phase: SyncPhase.failed,
    );
  }

  Future<Map<String, dynamic>> getEngineStatus() async {
    final coordinatorStatus = await _coordinator?.getStatus() ?? {};
    final conflictStats =
        await _conflictResolver?.getConflictStatistics() ?? {};

    return {
      'engine': {
        'initialized': _isInitialized,
        'running': _isRunning,
        'network_connected': _hasNetworkConnection,
        'signed_in': _isSignedIn,
        'pending_changes': _pendingChangesCount,
        'last_successful_sync': _lastSuccessfulSync?.toIso8601String(),
        'failed_attempts': _failedAttempts,
        'next_retry': _nextRetryAt?.toIso8601String(),
        'last_error': _lastError,
      },
      'coordinator': coordinatorStatus,
      'conflicts': conflictStats,
    };
  }

  Future<void> resetFailedAttempts() async {
    _failedAttempts = 0;
    _nextRetryAt = null;
    _lastError = null;
    _retryTimer?.cancel();
    _emitState();
    _log('🔄 Failed attempts reset');
  }

  void dispose() {
    stop();
    _stateController.close();
    _log('🛑 Auto Sync Engine disposed');
  }
}
