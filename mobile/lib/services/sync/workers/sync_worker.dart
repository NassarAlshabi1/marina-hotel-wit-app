import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../core/sync_orchestrator.dart';

/// مهام الخلفية للمزامنة
class SyncWorker {
  static const String taskName = 'com.marina.sync.background';
  static const String periodicTaskName = 'com.marina.sync.periodic';
  
  static bool _isInitialized = false;

  /// تهيئة WorkManager
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    
    _isInitialized = true;
  }

  /// جدولة مزامنة دورية
  static Future<void> schedulePeriodicSync({
    Duration frequency = const Duration(hours: 1),
  }) async {
    if (!_isInitialized) await initialize();
    
    await Workmanager().registerPeriodicTask(
      periodicTaskName,
      taskName,
      frequency: frequency,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
    
    developer.log('✅ تم جدولة المزامنة الدورية كل ${frequency.inMinutes} دقيقة');
  }

  /// إلغاء المزامنة الدورية
  static Future<void> cancelPeriodicSync() async {
    await Workmanager().cancelByUniqueName(periodicTaskName);
    developer.log('⏹️ تم إلغاء المزامنة الدورية');
  }

  /// تنفيذ مزامنة فورية في الخلفية
  static Future<void> syncNowInBackground() async {
    if (!_isInitialized) await initialize();
    
    await Workmanager().registerOneOffTask(
      'sync-${DateTime.now().millisecondsSinceEpoch}',
      taskName,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}

/// Dispatcher للمهام في الخلفية
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    developer.log('🔄 تنفيذ مهمة مزامنة في الخلفية: $task');
    
    try {
      final orchestrator = SyncOrchestrator.instance;
      final result = await orchestrator.syncNow();
      
      if (result.isSuccess) {
        developer.log('✅ تمت المزامنة في الخلفية بنجاح');
        return Future.value(true);
      } else {
        developer.log('❌ فشلت المزامنة في الخلفية: ${result.message}');
        return Future.value(false);
      }
    } catch (e) {
      developer.log('❌ خطأ في مزامنة الخلفية: $e');
      return Future.value(false);
    }
  });
}

/// Enhanced sync worker with battery optimization
class BatteryAwareSyncWorker {
  static bool _isBatteryLow = false;
  static bool _isCharging = false;

  /// تحديث حالة البطارية
  static void updateBatteryStatus({
    required bool isLow,
    required bool isCharging,
  }) {
    _isBatteryLow = isLow;
    _isCharging = isCharging;
  }

  /// هل يجب تشغيل المزامنة؟
  static bool shouldSync() {
    // لا تزامن إذا كانت البطارية منخفضة ولا يوجد شحن
    if (_isBatteryLow && !_isCharging) {
      return false;
    }
    return true;
  }
}
