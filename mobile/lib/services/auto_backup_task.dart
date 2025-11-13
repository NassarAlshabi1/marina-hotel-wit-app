import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../tasks/auto_sync_task.dart';

/// واجهة توافقية للشفرة القديمة تعتمد الآن على GoogleDriveAutoSyncTask
class AutoBackupTask {
  static const String taskName = kGoogleDriveAutoSyncTask;
  static const String taskId = kGoogleDriveAutoSyncTask;

  /// تهيئة Workmanager (تستند إلى GoogleDriveAutoSyncTask)
  static Future<void> initialize() async {
    try {
      await GoogleDriveAutoSyncTask.instance.initialize();
      debugPrint('✅ تم تهيئة GoogleDriveAutoSyncTask');
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة GoogleDriveAutoSyncTask: $e');
    }
  }

  /// جدولة المزامنة اليومية (كل 24 ساعة)
  static Future<void> scheduleDaily({String time = '02:00'}) async {
    await GoogleDriveAutoSyncTask.instance.schedule(interval: const Duration(days: 1));
    debugPrint('✅ تم جدولة المزامنة اليومية (كل 24 ساعة)');
  }

  /// جدولة المزامنة الأسبوعية (كل 7 أيام)
  static Future<void> scheduleWeekly({String time = '02:00', int weekday = 1}) async {
    await GoogleDriveAutoSyncTask.instance.schedule(interval: const Duration(days: 7));
    debugPrint('✅ تم جدولة المزامنة الأسبوعية (كل 7 أيام)');
  }

  /// جدولة المزامنة الشهرية (كل 30 يوم تقريباً)
  static Future<void> scheduleMonthly({String time = '02:00', int day = 1}) async {
    await GoogleDriveAutoSyncTask.instance.schedule(interval: const Duration(days: 30));
    debugPrint('✅ تم جدولة المزامنة الشهرية (كل 30 يوم)');
  }

  /// إلغاء المهام المجدولة
  static Future<void> cancelScheduled() async {
    await GoogleDriveAutoSyncTask.instance.cancel();
    debugPrint('✅ تم إلغاء مهام المزامنة التلقائية');
  }

  /// تشغيل المزامنة فوراً (للاختبار)
  static Future<void> runImmediately() async {
    await GoogleDriveAutoSyncTask.instance.runNow();
    debugPrint('✅ تم تشغيل المزامنة الفورية');
  }
}

/// نقطة الدخول لمعالجة المهام الخلفية
@pragma('vm:entry-point')
void callbackDispatcher() {
  googleDriveAutoSyncCallbackDispatcher();
}
