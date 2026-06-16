import 'package:flutter/widgets.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';
import 'package:workmanager/workmanager.dart';

import 'google_drive_backup_service.dart';
import 'local_backup_service.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

class AutoBackupTask {
  static const String taskName = 'autoBackupTask';
  static const String taskId = 'autoBackup';

  /// تهيئة Workmanager
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );
      AppLogger.info('✅ تم تهيئة AutoBackupTask', tag: 'APP');
    } catch (e) {
      AppLogger.warning('❌ خطأ في تهيئة AutoBackupTask: $e', tag: 'APP');
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

      AppLogger.info('✅ تم جدولة النسخ اليومي في $time', tag: 'APP');
    } catch (e) {
      AppLogger.warning('❌ خطأ في جدولة النسخ اليومي: $e', tag: 'APP');
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

      AppLogger.info('✅ تم جدولة النسخ الأسبوعي في $time يوم $weekday', tag: 'APP');
    } catch (e) {
      AppLogger.warning('❌ خطأ في جدولة النسخ الأسبوعي: $e', tag: 'APP');
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

      AppLogger.info('✅ تم جدولة النسخ الشهري في $time يوم $day', tag: 'APP');
    } catch (e) {
      AppLogger.warning('❌ خطأ في جدولة النسخ الشهري: $e', tag: 'APP');
    }
  }

  /// إلغاء المهام المجدولة
  static Future<void> cancelScheduled() async {
    try {
      await _cancelExisting();
      AppLogger.info('✅ تم إلغاء جميع مهام النسخ المجدولة', tag: 'APP');
    } catch (e) {
      AppLogger.warning('❌ خطأ في إلغاء المهام المجدولة: $e', tag: 'APP');
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
    final targetHour = int.tryParse(timeParts[0]) ?? 0;
    final targetMinute = int.tryParse(timeParts[1]) ?? 0;

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
    final targetHour = int.tryParse(timeParts[0]) ?? 0;
    final targetMinute = int.tryParse(timeParts[1]) ?? 0;

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
    final targetHour = int.tryParse(timeParts[0]) ?? 0;
    final targetMinute = int.tryParse(timeParts[1]) ?? 0;

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
      AppLogger.info('✅ تم تشغيل مهمة النسخ الفوري', tag: 'APP');
    } catch (e) {
      AppLogger.warning('❌ خطأ في تشغيل مهمة النسخ الفوري: $e', tag: 'APP');
    }
  }
}

/// نقطة الدخول لمعالجة المهام الخلفية
@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    try {
      AppLogger.info('🔄 بدء تنفيذ مهمة النسخ الخلفية: $task', tag: 'APP');

      // قراءة إعدادات النسخ التلقائي
      final prefs = getSharedPrefs();
      final enableGoogleDrive = prefs.getBool('auto_backup_enabled') ?? false;
      final enableLocal = prefs.getBool('auto_local_backup_enabled') ?? true;

      final localBackupService = LocalBackupService();
      final backupFormat = await localBackupService.getPreferredBackupFormat();
      bool success = true;

      // تنفيذ النسخ المحلي إذا كان مُفعلاً
      if (enableLocal) {
        try {
          AppLogger.info('📱 بدء النسخ الاحتياطي المحلي...', tag: 'APP');
          await localBackupService.createLocalBackup(format: backupFormat);
          AppLogger.info('✅ تم النسخ الاحتياطي المحلي بنجاح', tag: 'APP');
        } catch (e) {
          AppLogger.warning('❌ خطأ في النسخ الاحتياطي المحلي: $e', tag: 'APP');
          success = false;
        }
      }

      // تنفيذ النسخ السحابي إذا كان مُفعلاً ومتصل
      if (enableGoogleDrive) {
        try {
          AppLogger.info('☁️ بدء النسخ الاحتياطي السحابي...', tag: 'APP');
          final driveBackupService = GoogleDriveBackupService();
          if (!driveBackupService.isSignedIn) {
            await driveBackupService.attemptSilentSignIn();
          }
          if (driveBackupService.isSignedIn) {
            await driveBackupService.performAutoBackup();
            AppLogger.info('✅ تم النسخ الاحتياطي السحابي بنجاح', tag: 'APP');
          } else {
            AppLogger.warning(
  '⚠️ تعذر تسجيل الدخول تلقائياً إلى Google Drive، تم تخطي النسخ السحابي',
  tag: 'APP',
);
          }
        } catch (e) {
          AppLogger.warning('❌ خطأ في النسخ الاحتياطي السحابي: $e', tag: 'APP');
          // عدم فشل المهمة إذا فشل النسخ السحابي فقط
        }
      }

      if (success || enableLocal) {
        AppLogger.info('✅ تم تنفيذ مهمة النسخ الخلفية بنجاح', tag: 'APP');
        return Future.value(true);
      } else {
        AppLogger.warning('❌ فشل في تنفيذ جميع أنواع النسخ', tag: 'APP');
        return Future.value(false);
      }
    } catch (e) {
      AppLogger.warning('❌ خطأ في تنفيذ مهمة النسخ الخلفية: $e', tag: 'APP');

      // إرجاع false سيؤدي إلى إعادة تشغيل المهمة
      return Future.value(false);
    }
  });
}
