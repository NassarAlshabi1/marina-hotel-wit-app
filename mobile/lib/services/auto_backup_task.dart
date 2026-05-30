import '../utils/app_logger.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'local_backup_service.dart';

class AutoBackupTask {
  static const String taskName = 'autoBackupTask';
  static const String taskId = 'autoBackup';

  /// تهيئة Workmanager
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );
      AppLogger.info('تم تهيئة AutoBackupTask');
    } catch (e) {
      AppLogger.error('خطأ في تهيئة AutoBackupTask: $e');
    }
  }

  /// جدولة النسخ اليومي
  static Future<void> scheduleDaily({String time = '02:00'}) async {
    try {
      await _cancelExisting();

      // حساب التأخير الأولي
      final initialDelay = _calculateInitialDelay(time);

      await Workmanager().registerPeriodicTask(
        taskId,
        taskName,
        frequency: const Duration(days: 1),
        initialDelay: initialDelay,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
          requiresStorageNotLow: true,
        ),
        inputData: {'frequency': 'daily', 'time': time},
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );

      AppLogger.info('تم جدولة النسخ اليومي في $time');
    } catch (e) {
      AppLogger.error('خطأ في جدولة النسخ اليومي: $e');
    }
  }

  /// جدولة النسخ الأسبوعي
  static Future<void> scheduleWeekly({
    String time = '02:00',
    int weekday = 1,
  }) async {
    try {
      await _cancelExisting();

      // حساب التأخير الأولي للوصول للأسبوع القادم في اليوم المحدد
      final initialDelay = _calculateWeeklyInitialDelay(time, weekday);

      await Workmanager().registerPeriodicTask(
        taskId,
        taskName,
        frequency: const Duration(days: 7),
        initialDelay: initialDelay,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
          requiresStorageNotLow: true,
        ),
        inputData: {'frequency': 'weekly', 'time': time, 'weekday': weekday},
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );

      AppLogger.info('تم جدولة النسخ الأسبوعي في $time يوم $weekday');
    } catch (e) {
      AppLogger.error('خطأ في جدولة النسخ الأسبوعي: $e');
    }
  }

  /// جدولة النسخ الشهري
  static Future<void> scheduleMonthly({
    String time = '02:00',
    int day = 1,
  }) async {
    try {
      await _cancelExisting();

      // حساب التأخير الأولي للوصول للشهر القادم في اليوم المحدد
      final initialDelay = _calculateMonthlyInitialDelay(time, day);

      await Workmanager().registerPeriodicTask(
        taskId,
        taskName,
        frequency: const Duration(days: 30), // تقريباً شهرياً
        initialDelay: initialDelay,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
          requiresStorageNotLow: true,
        ),
        inputData: {'frequency': 'monthly', 'time': time, 'day': day},
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );

      AppLogger.info('تم جدولة النسخ الشهري في $time يوم $day');
    } catch (e) {
      AppLogger.error('خطأ في جدولة النسخ الشهري: $e');
    }
  }

  /// إلغاء المهام المجدولة
  static Future<void> cancelScheduled() async {
    try {
      await _cancelExisting();
      AppLogger.info('تم إلغاء جميع مهام النسخ المجدولة');
    } catch (e) {
      AppLogger.error('خطأ في إلغاء المهام المجدولة: $e');
    }
  }

  /// إلغاء المهام الموجودة
  static Future<void> _cancelExisting() async {
    await Workmanager().cancelByUniqueName(taskId);
  }

  /// حساب التأخير الأولي للنسخ اليومي
  static Duration _calculateInitialDelay(String time) {
    final now = DateTime.now();
    final timeParts = time.split(':');
    final targetHour = int.parse(timeParts[0]);
    final targetMinute = int.parse(timeParts[1]);

    var targetTime = DateTime(
      now.year,
      now.month,
      now.day,
      targetHour,
      targetMinute,
    );

    // إذا كان الوقت المستهدف قد مر اليوم، اجدوله للغد
    if (targetTime.isBefore(now)) {
      targetTime = targetTime.add(const Duration(days: 1));
    }

    return targetTime.difference(now);
  }

  /// حساب التأخير الأولي للنسخ الأسبوعي
  static Duration _calculateWeeklyInitialDelay(String time, int weekday) {
    final now = DateTime.now();
    final timeParts = time.split(':');
    final targetHour = int.parse(timeParts[0]);
    final targetMinute = int.parse(timeParts[1]);

    // العثور على التاريخ المستهدف في الأسبوع الحالي أو التالي
    final daysUntilWeekday = (weekday - now.weekday + 7) % 7;
    final targetDate = now.add(Duration(days: daysUntilWeekday));

    var targetTime = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      targetHour,
      targetMinute,
    );

    // إذا كان الوقت المستهدف قد مر، اجدوله للأسبوع القادم
    if (targetTime.isBefore(now)) {
      targetTime = targetTime.add(const Duration(days: 7));
    }

    return targetTime.difference(now);
  }

  /// حساب التأخير الأولي للنسخ الشهري
  static Duration _calculateMonthlyInitialDelay(String time, int day) {
    final now = DateTime.now();
    final timeParts = time.split(':');
    final targetHour = int.parse(timeParts[0]);
    final targetMinute = int.parse(timeParts[1]);

    var targetDate = DateTime(now.year, now.month, day);

    // إذا كان اليوم المحدد قد مر في هذا الشهر، اجدوله للشهر القادم
    if (targetDate.isBefore(now)) {
      targetDate = DateTime(now.year, now.month + 1, day);

      // التعامل مع نهاية السنة
      if (targetDate.month > 12) {
        targetDate = DateTime(now.year + 1, 1, day);
      }
    }

    final targetTime = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      targetHour,
      targetMinute,
    );

    return targetTime.difference(now);
  }

  /// تشغيل المهمة على الفور (للاختبار)
  static Future<void> runImmediately() async {
    try {
      await Workmanager().registerOneOffTask(
        'immediateBackup',
        taskName,
        constraints: Constraints(networkType: NetworkType.connected),
        inputData: {
          'frequency': 'immediate',
          'time': DateTime.now().toIso8601String(),
        },
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      AppLogger.info('تم تشغيل مهمة النسخ الفوري');
    } catch (e) {
      AppLogger.error('خطأ في تشغيل مهمة النسخ الفوري: $e');
    }
  }
}

/// نقطة الدخول لمعالجة المهام الخلفية
@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    try {
      AppLogger.debug('بدء تنفيذ مهمة النسخ الخلفية: $task');

      // قراءة إعدادات النسخ التلقائي
      final prefs = await SharedPreferences.getInstance();
      final enableLocal = prefs.getBool('auto_local_backup_enabled') ?? true;

      final localBackupService = LocalBackupService();
      final backupFormat = await localBackupService.getPreferredBackupFormat();
      bool success = true;

      // تنفيذ النسخ المحلي
      if (enableLocal) {
        try {
          AppLogger.debug('بدء النسخ الاحتياطي المحلي...');
          await localBackupService.createLocalBackup(format: backupFormat);
          AppLogger.info('تم النسخ الاحتياطي المحلي بنجاح');
        } catch (e) {
          AppLogger.error('خطأ في النسخ الاحتياطي المحلي: $e');
          success = false;
        }
      }

      if (success || enableLocal) {
        AppLogger.info('تم تنفيذ مهمة النسخ الخلفية بنجاح');
        return Future.value(true);
      } else {
        AppLogger.error('فشل في تنفيذ جميع أنواع النسخ');
        return Future.value(false);
      }
    } catch (e) {
      AppLogger.error('خطأ في تنفيذ مهمة النسخ الخلفية: $e');

      // إرجاع false سيؤدي إلى إعادة تشغيل المهمة
      return Future.value(false);
    }
  });
}
