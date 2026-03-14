import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../services/unified_sync_orchestrator.dart';

const _kImmediateWorkName = 'appwrite_auto_sync_now';
const _kPeriodicWorkName = 'appwrite_auto_sync_periodic';
const _kPendingFlagKey = 'appwrite_auto_sync_pending';
const _kDebounceWindow = Duration(seconds: 8);

@pragma('vm:entry-point')
void appwriteAutoSyncCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();

      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('appwrite_sync_enabled') ?? false;

      if (!enabled) {
        return true;
      }

      final success = await UnifiedSyncOrchestrator.instance.syncNow(
        push: true,
        pull: true,
        reason: 'appwrite_background_task',
      );

      if (success) {
        await prefs.setBool(_kPendingFlagKey, false);
      } else {
        await prefs.setBool(_kPendingFlagKey, true);
      }

      return success;
    } catch (e) {
      return false;
    }
  });
}

class AppwriteAutoSyncTask {
  AppwriteAutoSyncTask._();

  static int _debounceToken = 0;
  static bool _initialized = false;

  static Future<void> initialize({bool debug = false}) async {
    if (_initialized) return;
    WidgetsFlutterBinding.ensureInitialized();
    await Workmanager().initialize(
      appwriteAutoSyncCallbackDispatcher,
      isInDebugMode: debug,
    );
    _initialized = true;
  }

  static Future<void> scheduleImmediateSync({
    Duration delay = _kDebounceWindow,
  }) async {
    if (!_initialized) {
      throw StateError('AppwriteAutoSyncTask not initialized');
    }
    final token = ++_debounceToken;
    await Future<void>.delayed(delay, () async {
      if (token != _debounceToken) return;
      await Workmanager().registerOneOffTask(
        _kImmediateWorkName,
        _kImmediateWorkName,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        inputData: const <String, dynamic>{},
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 1),
      );
    });
  }

  static Future<void> schedulePeriodicSync(Duration frequency) async {
    if (!_initialized) {
      throw StateError('AppwriteAutoSyncTask not initialized');
    }
    await Workmanager().registerPeriodicTask(
      _kPeriodicWorkName,
      _kPeriodicWorkName,
      frequency: frequency,
      initialDelay: frequency,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      inputData: const <String, dynamic>{},
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 2),
    );
  }

  static Future<void> cancelAll() async {
    if (!_initialized) return;
    _debounceToken++;
    await Workmanager().cancelByUniqueName(_kImmediateWorkName);
    await Workmanager().cancelByUniqueName(_kPeriodicWorkName);
  }

  static Future<void> consumePendingAndSync({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_kPendingFlagKey) ?? false;
    if (!pending && !force) return;
    await UnifiedSyncOrchestrator.instance.syncNow(
      push: true,
      pull: true,
      reason: 'pending_appwrite_sync',
    );
    await prefs.setBool(_kPendingFlagKey, false);
  }
}
