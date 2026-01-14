import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../services/google_drive_sync_service.dart';
import '../services/local_db.dart';
import '../services/sync_manager.dart';

const _kImmediateWorkName = 'marina_auto_sync_now';
const _kPeriodicWorkName = 'marina_auto_sync_periodic';
const _kPendingFlagKey = 'auto_sync_pending';
const _kDebounceWindow = Duration(seconds: 1);

@pragma('vm:entry-point')
void autoSyncCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPendingFlagKey, true);

    try {
      final db = DatabaseManager.instance;
      final driveService = GoogleDriveSyncService();
      final manager = SyncManager(db: db, driveService: driveService);
      await manager.initSyncService(allowInteractiveSignIn: false);
      await manager.smartSync(force: false);
      await prefs.setBool(_kPendingFlagKey, false);
    } catch (error, stackTrace) {
      developer.log(
        'Auto-sync background task failed',
        name: 'AutoSyncTask',
        error: error is Exception ? error.runtimeType.toString() : error,
        stackTrace: stackTrace,
        level: 1000,
      );
      await prefs.setBool(_kPendingFlagKey, true);
    }

    return true;
  });
}

/// مهمة الخلفية التي تعتمد على WorkManager مع دعم debounce
class AutoSyncTask {
  AutoSyncTask._();

  static int _debounceToken = 0;
  static Future<void>? _pendingDebounce;
  static bool _initialized = false;

  /// تهيئة WorkManager وتسجيل callback
  static Future<void> initialize({bool debug = false}) async {
    if (_initialized) {
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    await Workmanager().initialize(autoSyncCallbackDispatcher, isInDebugMode: debug);
    _initialized = true;
  }

  /// جدولة مزامنة فورية مع Debounce لمنع التكرار المتتابع
  static Future<void> scheduleImmediateSync({Duration delay = _kDebounceWindow}) async {
    if (!_initialized) {
      throw StateError('لم يتم تهيئة AutoSyncTask. استدع initialize أولاً.');
    }
    final token = ++_debounceToken;
    _pendingDebounce = Future<void>.delayed(delay, () async {
      if (token != _debounceToken) {
        return;
      }
      await Workmanager().registerOneOffTask(
        _kImmediateWorkName,
        _kImmediateWorkName,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        initialDelay: delay,
        constraints: Constraints(networkType: NetworkType.connected),
        inputData: const <String, dynamic>{},
      );
    });
  }

  /// تسجيل مهمة دورية تعتمد على WorkManager (الحد الأدنى 15 دقيقة على أندرويد)
  static Future<void> schedulePeriodicSync(Duration frequency) async {
    if (!_initialized) {
      throw StateError('لم يتم تهيئة AutoSyncTask. استدع initialize أولاً.');
    }
    await Workmanager().registerPeriodicTask(
      _kPeriodicWorkName,
      _kPeriodicWorkName,
      frequency: frequency,
      initialDelay: frequency,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
      inputData: const <String, dynamic>{},
    );
  }

  /// إلغاء المهام المسجلة
  static Future<void> cancelAll() async {
    if (!_initialized) {
      return;
    }
    _debounceToken++;
    _pendingDebounce = null;
    await Workmanager().cancelByUniqueName(_kImmediateWorkName);
    await Workmanager().cancelByUniqueName(_kPeriodicWorkName);
  }

  /// استهلاك العلامة المخزنة وتشغيل المزامنة الحقيقية داخل التطبيق الرئيسي
  static Future<void> consumePendingAndSync(SyncManager manager, {bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_kPendingFlagKey) ?? false;
    if (!pending && !force) {
      return;
    }
    await manager.syncAllTables(force: force);
    await prefs.setBool(_kPendingFlagKey, false);
  }
}
