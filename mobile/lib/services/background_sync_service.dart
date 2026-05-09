// lib/services/background_sync_service.dart
// خدمة المزامنة في الخلفية
// background_sync_service.dart - مزامنة في الخلفية مع WorkManager

import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';

import 'analytics_service.dart';
import 'battery_optimizer.dart';
import 'smart_sync_manager.dart';

/// معرف مهمة المزامنة في الخلفية
const String backgroundSyncTask = 'marina-hotel-background-sync';
const String periodicSyncTask = 'marina-hotel-periodic-sync';
const String batteryAwareSyncTask = 'marina-hotel-battery-aware-sync';

/// فئة المزامنة في الخلفية
class BackgroundSyncService {
  factory BackgroundSyncService() => _instance;
  BackgroundSyncService._internal();
  static final BackgroundSyncService _instance = BackgroundSyncService._internal();

  bool _isInitialized = false;
  final BatteryOptimizer _batteryOptimizer = BatteryOptimizer();
  final AnalyticsService _analytics = AnalyticsService();

  // إعدادات المزامنة
  Duration _syncInterval = const Duration(minutes: 15);
  bool _requireCharging = false;
  bool _requireNetworkTypeUnmetered = false;
  bool _requiresBatteryNotLow = true;
  final bool _requiresStorageNotLow = true;

  /// تهيئة خدمة المزامنة في الخلفية
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Workmanager().initialize(
        _callbackDispatcher,
      );

      await _batteryOptimizer.initialize();

      _isInitialized = true;

      developer.log(
        '✅ BackgroundSyncService initialized',
        name: 'BackgroundSyncService',
      );
    } catch (e) {
      developer.log(
        '⚠️ BackgroundSyncService init error: $e',
        name: 'BackgroundSyncService',
      );
    }
  }

  /// تسجيل مهمة مزامنة دورية
  Future<void> registerPeriodicSync({
    Duration? interval,
    bool requireCharging = false,
    bool requireUnmeteredNetwork = false,
    bool requiresBatteryNotLow = true,
  }) async {
    if (!_isInitialized) {
      throw StateError('BackgroundSyncService not initialized');
    }

    _syncInterval = interval ?? _syncInterval;
    _requireCharging = requireCharging;
    _requireNetworkTypeUnmetered = requireUnmeteredNetwork;
    _requiresBatteryNotLow = requiresBatteryNotLow;

    try {
      // إلغاء التسجيل السابق إن وجد
      await Workmanager().cancelByUniqueName(periodicSyncTask);

      // تسجيل مهمة جديدة
      await Workmanager().registerPeriodicTask(
        periodicSyncTask,
        periodicSyncTask,
        frequency: _syncInterval,
        constraints: Constraints(
          networkType: requireUnmeteredNetwork
              ? NetworkType.unmetered
              : NetworkType.connected,
          requiresCharging: requireCharging,
          requiresBatteryNotLow: requiresBatteryNotLow,
          requiresStorageNotLow: _requiresStorageNotLow,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );

      developer.log(
        '✅ Registered periodic sync: ${_syncInterval.inMinutes}min interval',
        name: 'BackgroundSyncService',
      );

      await _analytics.logSyncEvent(
        SyncAnalyticsEvent.syncStarted,
        parameters: {
          'trigger': 'register_periodic',
          'interval_minutes': _syncInterval.inMinutes,
        },
      );
    } catch (e) {
      developer.log(
        '⚠️ Failed to register periodic sync: $e',
        name: 'BackgroundSyncService',
      );
    }
  }

  /// تسجيل مهمة مزامنة لمرة واحدة
  Future<void> scheduleOneTimeSync({
    Duration delay = Duration.zero,
    bool requireCharging = false,
    bool requireNetwork = true,
  }) async {
    if (!_isInitialized) return;

    try {
      await Workmanager().registerOneOffTask(
        backgroundSyncTask,
        backgroundSyncTask,
        initialDelay: delay,
        constraints: Constraints(
          networkType: requireNetwork
              ? NetworkType.connected
              : NetworkType.connected,
          requiresCharging: requireCharging,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      developer.log(
        '✅ Scheduled one-time sync in ${delay.inMinutes} minutes',
        name: 'BackgroundSyncService',
      );
    } catch (e) {
      developer.log(
        '⚠️ Failed to schedule one-time sync: $e',
        name: 'BackgroundSyncService',
      );
    }
  }

  /// تسجيل مهمة مزامنة مع مراعاة البطارية
  Future<void> registerBatteryAwareSync() async {
    if (!_isInitialized) return;

    try {
      await Workmanager().cancelByUniqueName(batteryAwareSyncTask);

      // استخدام إعدادات البطارية الحالية
      final settings = _batteryOptimizer.syncSettings;

      await Workmanager().registerPeriodicTask(
        batteryAwareSyncTask,
        batteryAwareSyncTask,
        frequency: settings.syncInterval,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresCharging: !settings.syncOnBattery,
          requiresBatteryNotLow: settings.minBatteryPercentage > 20,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );

      developer.log(
        '✅ Registered battery-aware sync',
        name: 'BackgroundSyncService',
      );
    } catch (e) {
      developer.log(
        '⚠️ Failed to register battery-aware sync: $e',
        name: 'BackgroundSyncService',
      );
    }
  }

  /// إلغاء جميع مهام المزامنة
  Future<void> cancelAllSyncs() async {
    if (!_isInitialized) return;

    try {
      await Workmanager().cancelAll();

      developer.log(
        '✅ Cancelled all background sync tasks',
        name: 'BackgroundSyncService',
      );
    } catch (e) {
      developer.log(
        '⚠️ Failed to cancel syncs: $e',
        name: 'BackgroundSyncService',
      );
    }
  }

  /// إلغاء مهمة محددة
  Future<void> cancelSync(String uniqueName) async {
    if (!_isInitialized) return;

    try {
      await Workmanager().cancelByUniqueName(uniqueName);
    } catch (e) {
      developer.log(
        '⚠️ Failed to cancel sync $uniqueName: $e',
        name: 'BackgroundSyncService',
      );
    }
  }

  /// تنظيف آمن للمثيل Singleton
  void dispose() {
    _isInitialized = false;
  }

  static void disposeInstance() {
    _instance.dispose();
  }

  /// تشغيل المزامنة اليدوية في الخلفية
  static Future<bool> executeBackgroundSync() async {
    developer.log(
      '🔄 Executing background sync',
      name: 'BackgroundSyncService',
    );

    final stopwatch = Stopwatch()..start();
    final analytics = AnalyticsService();

    try {
      // التحقق من الاتصال
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        developer.log(
          '⚠️ No connectivity, skipping background sync',
          name: 'BackgroundSyncService',
        );
        return false;
      }

      // التحقق من البطارية
      final batteryOptimizer = BatteryOptimizer();
      if (!batteryOptimizer.shouldSync) {
        developer.log(
          '🔋 Battery conditions not met, skipping background sync',
          name: 'BackgroundSyncService',
        );
        return false;
      }

      // تنفيذ المزامنة
      final syncManager = SmartSyncManager.instance;
      await syncManager.syncNow();

      stopwatch.stop();

      await analytics.logSyncEvent(
        SyncAnalyticsEvent.syncCompleted,
        parameters: {
          'trigger': 'background',
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );

      developer.log(
        '✅ Background sync completed in ${stopwatch.elapsedMilliseconds}ms',
        name: 'BackgroundSyncService',
      );

      return true;
    } catch (e) {
      stopwatch.stop();

      await analytics.logSyncFailure(
        error: e.toString(),
        operation: 'background_sync',
        attempt: 1,
      );

      developer.log(
        '❌ Background sync failed: $e',
        name: 'BackgroundSyncService',
      );

      return false;
    }
  }

  /// الحصول على معلومات المهام المسجلة
  Future<Map<String, dynamic>> getDebugInfo() async {
    return {
      'is_initialized': _isInitialized,
      'sync_interval_minutes': _syncInterval.inMinutes,
      'require_charging': _requireCharging,
      'require_unmetered_network': _requireNetworkTypeUnmetered,
      'requires_battery_not_low': _requiresBatteryNotLow,
      'battery_level': _batteryOptimizer.batteryLevel,
      'is_charging': _batteryOptimizer.isCharging,
      'should_sync': _batteryOptimizer.shouldSync,
      'optimization_level': _batteryOptimizer.optimizationLevel.name,
    };
  }
}

/// Callback dispatcher للـ WorkManager
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    developer.log(
      '📋 Background task executed: $task',
      name: 'BackgroundSyncService',
    );

    switch (task) {
      case periodicSyncTask:
      case backgroundSyncTask:
      case batteryAwareSyncTask:
        return BackgroundSyncService.executeBackgroundSync();
      default:
        developer.log(
          '⚠️ Unknown task: $task',
          name: 'BackgroundSyncService',
        );
        return Future.value(false);
    }
  });
}

/// إعدادات متقدمة للمزامنة في الخلفية
class BackgroundSyncSettings {

  const BackgroundSyncSettings({
    this.interval = const Duration(minutes: 15),
    this.requireCharging = false,
    this.requireUnmeteredNetwork = false,
    this.requiresBatteryNotLow = true,
    this.requiresStorageNotLow = true,
    this.enableRetry = true,
    this.maxRetries = 3,
  });
  final Duration interval;
  final bool requireCharging;
  final bool requireUnmeteredNetwork;
  final bool requiresBatteryNotLow;
  final bool requiresStorageNotLow;
  final bool enableRetry;
  final int maxRetries;

  static const BackgroundSyncSettings conservative = BackgroundSyncSettings(
    interval: Duration(minutes: 30),
    requireUnmeteredNetwork: true,
  );

  static const BackgroundSyncSettings aggressive = BackgroundSyncSettings(
    interval: Duration(minutes: 5),
    requiresBatteryNotLow: false,
  );

  static const BackgroundSyncSettings overnight = BackgroundSyncSettings(
    interval: Duration(hours: 1),
    requireCharging: true,
  );
}
