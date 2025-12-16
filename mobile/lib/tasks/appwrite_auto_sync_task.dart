import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../services/appwrite_sync_manager.dart';

const _kImmediateWorkName = 'appwrite_auto_sync_now';
const _kPeriodicWorkName = 'appwrite_auto_sync_periodic';
const _kPendingFlagKey = 'appwrite_auto_sync_pending';
const _kDebounceWindow = Duration(seconds: 8);

@pragma('vm:entry-point')
void appwriteAutoSyncCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPendingFlagKey, true);
    return true;
  });
}

class AppwriteAutoSyncTask {
  AppwriteAutoSyncTask._();

  static int _debounceToken = 0;
  static Future<void>? _pendingDebounce;
  static bool _initialized = false;

  static Future<void> initialize({bool debug = false}) async {
    if (_initialized) return;
    WidgetsFlutterBinding.ensureInitialized();
    await Workmanager().initialize(appwriteAutoSyncCallbackDispatcher, isInDebugMode: debug);
    _initialized = true;
  }

  static Future<void> scheduleImmediateSync({Duration delay = _kDebounceWindow}) async {
    if (!_initialized) {
      throw StateError('AppwriteAutoSyncTask not initialized');
    }
    final token = ++_debounceToken;
    _pendingDebounce = Future<void>.delayed(delay, () async {
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
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
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
    _pendingDebounce = null;
    await Workmanager().cancelByUniqueName(_kImmediateWorkName);
    await Workmanager().cancelByUniqueName(_kPeriodicWorkName);
  }

  static Future<void> consumePendingAndSync(AppwriteSyncManager manager, {bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_kPendingFlagKey) ?? false;
    if (!pending) return;
    await manager.sync();
    await prefs.setBool(_kPendingFlagKey, false);
  }
}
