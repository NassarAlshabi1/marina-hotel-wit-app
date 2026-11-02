import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../services/unified_sync_orchestrator.dart';

const _kImmediateWorkName = 'marina_auto_sync_now';
const _kPeriodicWorkName = 'marina_auto_sync_periodic';
const _kPendingFlagKey = 'auto_sync_pending';
const _kDebounceWindow = Duration(seconds: 1);

@pragma('vm:entry-point')
void autoSyncCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();

      final prefs = await SharedPreferences.getInstance();
      final googleDriveEnabled = prefs.getBool('google_drive_sync_enabled') ?? false;

      if (!googleDriveEnabled) {
        return true;
      }

      final success = await UnifiedSyncOrchestrator.instance.syncNow(reason: 'google_drive_background_task');

      if (success) {
        await prefs.setBool(_kPendingFlagKey, false);
      } else {
        await prefs.setBool(_kPendingFlagKey, true);
      }

      return success;
    } catch (error, stackTrace) {
      developer.log(
        'Auto-sync background task failed',
        name: 'AutoSyncTask',
        error: error is Exception ? error.runtimeType.toString() : error,
        stackTrace: stackTrace,
        level: 1000,
      );
      return false;
    }
  });
}

/// مهمة الخلفية التي تعتمد على WorkManager مع دعم debounce
class AutoSyncTask {
  AutoSyncTask._();

  static int _debounceToken = 0;
  static bool _initialized = false;

  /// ✅ P0-7 fix: تهيئة موحّدة — لا نُهيّئ Workmanager هنا
  /// Workmanager يُهيّأ مرة واحدة فقط من BackgroundSyncService
  /// هذا يمنع تعدّد المُوزّعات الذي يكسر المهام الخلفية
  static Future<void> initialize({bool debug = false}) async {
    if (_initialized) {
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    // ✅ P0-7: لا نُهيّئ Workmanager هنا — يُهيّأ من مكان واحد موحّد
    _initialized = true;
  }

  /// جدولة مزامنة فورية مع Debounce لمنع التكرار المتتابع
  static Future<void> scheduleImmediateSync({Duration delay = _kDebounceWindow}) async {
    if (!_initialized) {
      throw StateError('لم يتم تهيئة AutoSyncTask. استدع initialize أولاً.');
    }
    final token = ++_debounceToken;
    await Future<void>.delayed(delay, () async {
      if (token != _debounceToken) {
        return;
      }
      await Workmanager().registerOneOffTask(
        _kImmediateWorkName,
        _kImmediateWorkName,
        existingWorkPolicy: ExistingWorkPolicy.replace,
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
    await Workmanager().cancelByUniqueName(_kImmediateWorkName);
    await Workmanager().cancelByUniqueName(_kPeriodicWorkName);
  }

  /// استهلاك العلامة المخزنة وتشغيل المزامنة الحقيقية داخل التطبيق الرئيسي
  static Future<void> consumePendingAndSync({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_kPendingFlagKey) ?? false;
    if (!pending && !force) {
      return;
    }
    await UnifiedSyncOrchestrator.instance.syncNow(reason: 'pending_sync');
    await prefs.setBool(_kPendingFlagKey, false);
  }
}
