/// Background Sync Service
/// خدمة المزامنة في الخلفية باستخدام WorkManager
/// تضمن مزامنة البيانات حتى عندما يكون التطبيق مغلقاً
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';

import '../models/sync_models.dart';
import '../orchestrator/sync_orchestrator.dart';

/// اسم مهمة المزامنة في الخلفية
const String _syncTaskName = 'marina_hotel_background_sync';
const String _cleanupTaskName = 'marina_hotel_cleanup_sync';

/// خدمة المزامنة في الخلفية
class BackgroundSyncService {
  factory BackgroundSyncService() => _instance;
  BackgroundSyncService._internal();
  static final BackgroundSyncService _instance =
      BackgroundSyncService._internal();

  SyncOrchestrator? _orchestrator;
  SyncConfiguration _config = const SyncConfiguration();

  bool _isInitialized = false;
  Timer? _batteryCheckTimer;

  /// تهيئة الخدمة
  Future<void> initialize({
    required SyncOrchestrator orchestrator,
    required SyncConfiguration config,
  }) async {
    if (_isInitialized) return;

    _orchestrator = orchestrator;
    _config = config;

    // تسجيل معالج المهام في WorkManager
    Workmanager().initialize(
      _callbackDispatcher,
      isInDebugMode: false,
    );

    _isInitialized = true;
    developer.log('BackgroundSyncService initialized', name: 'BackgroundSync');
  }

  /// جدولة مزامنة دورية
  Future<void> schedulePeriodicSync() async {
    if (!_config.backgroundSyncEnabled) {
      developer.log('Background sync disabled', name: 'BackgroundSync');
      return;
    }

    // إلغاء الجدولة القديمة إن وجدت
    await cancelScheduledSync();

    // جدولة المهمة الجديدة
    await Workmanager().registerPeriodicTask(
      _syncTaskName,
      _syncTaskName,
      frequency: _config.autoSyncInterval,
      constraints: Constraints(
        networkType:
            _config.requireWifi ? NetworkType.connected : NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresCharging: _config.requireCharging,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 10),
    );

    developer.log(
      'Scheduled periodic sync: ${_config.autoSyncInterval}',
      name: 'BackgroundSync',
    );
  }

  /// جدولة مهمة تنظيف
  Future<void> scheduleCleanup() async {
    await Workmanager().registerPeriodicTask(
      _cleanupTaskName,
      _cleanupTaskName,
      frequency: const Duration(days: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresCharging: false,
        requiresDeviceIdle: true,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// إلغاء الجدولة
  Future<void> cancelScheduledSync() async {
    await Workmanager().cancelByUniqueName(_syncTaskName);
    developer.log('Cancelled scheduled sync', name: 'BackgroundSync');
  }

  /// تشغيل مزامنة فورية في الخلفية
  Future<void> runImmediateSync() async {
    if (_orchestrator == null) {
      throw StateError('BackgroundSyncService not initialized');
    }

    final canSync = await _canRunBackgroundSync();
    if (!canSync) {
      developer.log('Cannot run background sync - constraints not met',
          name: 'BackgroundSync');
      return;
    }

    try {
      developer.log('Running immediate background sync',
          name: 'BackgroundSync');
      await _orchestrator!.performFullSync();
    } catch (e, stackTrace) {
      developer.log(
        'Background sync failed',
        name: 'BackgroundSync',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// التحقق مما إذا كان يمكن تشغيل المزامنة
  Future<bool> _canRunBackgroundSync() async {
    // التحقق من الاتصال
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.every((r) => r == ConnectivityResult.none)) {
      return false;
    }

    // التحقق من WiFi إذا كان مطلوباً
    if (_config.requireWifi &&
        !connectivity.contains(ConnectivityResult.wifi)) {
      return false;
    }

    // التحقق من البطارية إذا كان الشحن مطلوباً
    if (_config.requireCharging) {
      final battery = Battery();
      final state = await battery.batteryState;
      if (state != BatteryState.charging && state != BatteryState.full) {
        return false;
      }
    }

    return true;
  }

  /// التخلص من الموارد
  void dispose() {
    _batteryCheckTimer?.cancel();
  }
}

/// معالج المهام في الخلفية (يتم استدعاؤه من WorkManager)
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    developer.log('Background task: $task', name: 'BackgroundSync');

    try {
      switch (task) {
        case _syncTaskName:
          await _performBackgroundSync();
          return Future.value(true);

        case _cleanupTaskName:
          await _performCleanup();
          return Future.value(true);

        default:
          developer.log('Unknown task: $task', name: 'BackgroundSync');
          return Future.value(false);
      }
    } catch (e, stackTrace) {
      developer.log(
        'Background task failed',
        name: 'BackgroundSync',
        error: e,
        stackTrace: stackTrace,
      );
      return Future.value(false);
    }
  });
}

/// تنفيذ مزامنة في الخلفية
Future<void> _performBackgroundSync() async {
  developer.log('Performing background sync', name: 'BackgroundSync');

  // هنا يتم استخدام Service Locator أو GetIt للحصول على Orchestrator
  // لأنه لا يمكننا الوصول للـ context في الخلفية
  // هذا يتطلب إعداد Service Locainer مناسب

  // مثال مع Service Locator:
  // final orchestrator = GetIt.instance<SyncOrchestrator>();
  // await orchestrator.performFullSync();

  // كحل مؤقت، نكتفي بتسجيل المحاولة
  // يجب تنفيذ هذا الجزء حسب هيكل التطبيق
}

/// تنفيذ تنظيف في الخلفية
Future<void> _performCleanup() async {
  developer.log('Performing background cleanup', name: 'BackgroundSync');

  // تنظيف السجلات القديمة المُزامنة
  // مثال:
  // final outbox = GetIt.instance<OutboxProcessor>();
  // await outbox.cleanup(olderThan: const Duration(days: 7));
}

/// إعدادات المزامنة في الخلفية
class BackgroundSyncSettings {
  const BackgroundSyncSettings({
    this.enabled = true,
    this.interval = const Duration(minutes: 15),
    this.requireWifi = false,
    this.requireCharging = false,
    this.runOnBatteryLow = false,
  });
  final bool enabled;
  final Duration interval;
  final bool requireWifi;
  final bool requireCharging;
  final bool runOnBatteryLow;

  BackgroundSyncSettings copyWith({
    bool? enabled,
    Duration? interval,
    bool? requireWifi,
    bool? requireCharging,
    bool? runOnBatteryLow,
  }) {
    return BackgroundSyncSettings(
      enabled: enabled ?? this.enabled,
      interval: interval ?? this.interval,
      requireWifi: requireWifi ?? this.requireWifi,
      requireCharging: requireCharging ?? this.requireCharging,
      runOnBatteryLow: runOnBatteryLow ?? this.runOnBatteryLow,
    );
  }
}
