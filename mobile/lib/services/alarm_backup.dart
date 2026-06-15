import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_drive_backup_service.dart';
import 'lark/lark_report_service.dart';
import 'local_backup_service.dart';
import 'telegram/telegram_config.dart';
import 'telegram/telegram_report_service.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

class AlarmBackup {
  static const int alarmId = 0;
  static const int larkReportAlarmId = 1;
  static const int telegramReportAlarmId = 2;

  static final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  /// استدعِ هذه في main() قبل runApp
  static Future<void> initAlarmSystem() async {
    await AndroidAlarmManager.initialize();
    // تهيئة الإشعارات
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await _notif.initialize(initSettings);
    AppLogger.info('✅ Alarm system initialized', tag: 'APP');

    // تفعيل النسخ المجدول تلقائياً عند التثبيت لأول مرة
    final prefs = await getSharedPrefs();
    if (prefs.getBool('scheduled_backup_enabled') == null) {
      AppLogger.info('🚀 First run: Enable scheduled backup by default', tag: 'APP');
      await prefs.setBool('scheduled_backup_enabled', true);
      // وقت افتراضي 9:00 مساءً
      await prefs.setString('auto_backup_time', '21:00');
      await scheduleDailyAlarm(21, 0);
    }

    // تهيئة أولية لإعدادات تقرير WhatsApp/Telegram اليومي
    // مثل إنذار النسخ الاحتياطي — يُفعّل تلقائياً عند التثبيت لأول مرة
    if (prefs.getBool('telegram_enabled') == null) {
      AppLogger.info('🚀 First run: Enable WhatsApp/Telegram report by default', tag: 'APP');
      await prefs.setBool('telegram_enabled', true);
      await prefs.setBool('telegram_notifications_enabled', true);
      await prefs.setBool('telegram_daily_report_enabled', true);
      await prefs.setString('telegram_daily_report_time', '02:00');
    }

    // جدولة تقرير Lark اليومي إذا كان مفعّلاً
    await _scheduleLarkReportIfNeeded(prefs);

    // جدولة تقرير WhatsApp/Telegram اليومي إذا كان مفعّلاً
    await _scheduleTelegramReportIfNeeded(prefs);
  }
  static Future<void> scheduleDailyAlarm(int hour, int minute) async {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    // استخدم oneShotAt مع exact و wakeup و allowWhileIdle
    await AndroidAlarmManager.oneShotAt(
      scheduled,
      alarmId,
      _alarmCallback,
      exact: true,
      wakeup: true, // يسمح بالإيقاظ من Doze
      rescheduleOnReboot: true,
      allowWhileIdle: true,
    );

    AppLogger.info('✅ Alarm scheduled at $scheduled', tag: 'APP');
  }

  /// لإلغاء وإعادة جدولة — استخدمها عند تغيير الوقت
  static Future<void> rescheduleDaily(int hour, int minute) async {
    await AndroidAlarmManager.cancel(alarmId);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await scheduleDailyAlarm(hour, minute);
    AppLogger.info('♻️ Alarm rescheduled to $hour:$minute', tag: 'APP');
  }

  /// الكولباك الذي ينفذ وقت الإنذار — يجب أن يكون top-level أو static annotated
  @pragma('vm:entry-point')
  static Future<void> _alarmCallback() async {
    WidgetsFlutterBinding.ensureInitialized();
    AppLogger.info('🔔 Alarm fired: performing backup', tag: 'APP');

    try {
      final prefs = getSharedPrefs();
      final enableGoogleDrive = prefs.getBool('auto_backup_enabled') ?? false;
      final enableLocal = prefs.getBool('auto_local_backup_enabled') ?? true;

      final localService = LocalBackupService();
      final format = await localService.getPreferredBackupFormat();

      if (enableLocal) {
        try {
          await localService.createLocalBackup(format: format);
          AppLogger.info('✅ Local backup done from alarm', tag: 'APP');
        } catch (e) {
          AppLogger.error('❌ Local backup error: $e', tag: 'APP');
        }
      }

      if (enableGoogleDrive) {
        try {
          final drive = GoogleDriveBackupService();

          // حاول تسجيل الدخول بهدوء
          final signed = await drive.signInSilentlyIfNeeded();
          if (signed) {
            await drive.performAutoBackup();
            AppLogger.info('✅ Drive backup done from alarm', tag: 'APP');
          } else {
            AppLogger.warning('⚠️ Drive not signed in (alarm). Notifying user...', tag: 'APP');
            await _showOpenAppNotification();
          }
        } catch (e) {
          AppLogger.error('❌ Drive backup error: $e', tag: 'APP');
        }
      }
    } catch (e) {
      AppLogger.error('❌ Alarm backup general error: $e', tag: 'APP');
    } finally {
      // أعد جدولة الإنذار لليوم التالي في نفس الوقت
      final prefs = getSharedPrefs();
      final timeString = prefs.getString('auto_backup_time') ?? '21:00';
      final timeParts = timeString.split(':');
      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;
      await scheduleDailyAlarm(hour, minute);
    }
  }

  static Future<void> _showOpenAppNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'backup_channel',
      'Backups',
      channelDescription: 'Backup notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notif.show(
      0,
      'نسخة احتياطية فشلت',
      'يرجى فتح التطبيق لتسجيل الدخول وإكمال النسخة',
      details,
    );
  }

  /// إلغاء الإنذار
  static Future<void> cancelAlarm() async {
    await AndroidAlarmManager.cancel(alarmId);
    AppLogger.info('🚫 Alarm cancelled', tag: 'APP');
  }

  /// جدولة تقرير Lark اليومي إذا كان مفعّلاً
  static Future<void> _scheduleLarkReportIfNeeded(SharedPreferences prefs) async {
    final larkEnabled = prefs.getBool('lark_enabled') ?? false;
    final reportEnabled = prefs.getBool('lark_daily_report_enabled') ?? false;

    if (larkEnabled && reportEnabled) {
      final timeString = prefs.getString('lark_daily_report_time') ?? '08:00';
      final parts = timeString.split(':');
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      await scheduleLarkReportAlarm(hour, minute);
    } else {
      await AndroidAlarmManager.cancel(larkReportAlarmId);
    }
  }

  /// جدولة إنذار يومي لإرسال تقرير Lark
  static Future<void> scheduleLarkReportAlarm(int hour, int minute) async {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await AndroidAlarmManager.oneShotAt(
      scheduled,
      larkReportAlarmId,
      _larkReportCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      allowWhileIdle: true,
    );

    AppLogger.info('✅ Lark report alarm scheduled at $scheduled', tag: 'APP');
  }

  /// إعادة جدولة تقرير Lark
  static Future<void> rescheduleLarkReport(int hour, int minute) async {
    await AndroidAlarmManager.cancel(larkReportAlarmId);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await scheduleLarkReportAlarm(hour, minute);
    AppLogger.info('♻️ Lark report alarm rescheduled to $hour:$minute', tag: 'APP');
  }

  /// جدولة تقرير Telegram/WhatsApp اليومي إذا كان مفعّلاً
  /// القيم الافتراضية = true لتتطابق مع TelegramConfig.isEnabled() و isDailyReportEnabled()
  static Future<void> _scheduleTelegramReportIfNeeded(SharedPreferences prefs) async {
    final tgEnabled = prefs.getBool('telegram_enabled') ?? true;
    final reportEnabled = prefs.getBool('telegram_daily_report_enabled') ?? true;

    if (tgEnabled && reportEnabled) {
      final timeString = prefs.getString('telegram_daily_report_time') ?? '02:00';
      final parts = timeString.split(':');
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      await scheduleTelegramReportAlarm(hour, minute);
    } else {
      await AndroidAlarmManager.cancel(telegramReportAlarmId);
    }
  }

  /// جدولة إنذار يومي لإرسال تقرير Telegram
  static Future<void> scheduleTelegramReportAlarm(int hour, int minute) async {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await AndroidAlarmManager.oneShotAt(
      scheduled,
      telegramReportAlarmId,
      _telegramReportCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      allowWhileIdle: true,
    );

    AppLogger.info('✅ Telegram report alarm scheduled at $scheduled', tag: 'APP');
  }

  /// إعادة جدولة تقرير Telegram
  static Future<void> rescheduleTelegramReport(int hour, int minute) async {
    await AndroidAlarmManager.cancel(telegramReportAlarmId);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await scheduleTelegramReportAlarm(hour, minute);
    AppLogger.info('♻️ Telegram report alarm rescheduled to $hour:$minute', tag: 'APP');
  }

  /// إلغاء إنذار تقرير Telegram
  static Future<void> cancelTelegramReportAlarm() async {
    await AndroidAlarmManager.cancel(telegramReportAlarmId);
    AppLogger.info('🚫 Telegram report alarm cancelled', tag: 'APP');
  }

  /// Callback لإرسال تقرير Telegram اليومي
  @pragma('vm:entry-point')
  static Future<void> _telegramReportCallback() async {
    WidgetsFlutterBinding.ensureInitialized();
    AppLogger.info('🔔 Telegram report alarm fired', tag: 'APP');

    try {
      final prefs = getSharedPrefs();
      final tgEnabled = prefs.getBool('telegram_enabled') ?? true;
      final reportEnabled = prefs.getBool('telegram_daily_report_enabled') ?? true;

      if (tgEnabled && reportEnabled) {
        final configured = await TelegramConfig.isConfigured();
        if (configured) {
          final reportService = TelegramReportService.instance();
          await reportService.sendDailyReport();
          AppLogger.info('✅ Telegram daily report sent from alarm', tag: 'APP');
        } else {
          AppLogger.warning('⚠️ Telegram report skipped: bot token or chat ID not configured', tag: 'APP');
        }
      }
    } catch (e) {
      AppLogger.error('❌ Telegram report alarm error: $e', tag: 'APP');
    } finally {
      // أعد جدولة لليوم التالي
      final prefs = getSharedPrefs();
      final timeString = prefs.getString('telegram_daily_report_time') ?? '02:00';
      final parts = timeString.split(':');
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      await scheduleTelegramReportAlarm(hour, minute);
    }
  }

  /// Callback لإرسال تقرير Lark اليومي
  @pragma('vm:entry-point')
  static Future<void> _larkReportCallback() async {
    WidgetsFlutterBinding.ensureInitialized();
    AppLogger.info('🔔 Lark report alarm fired', tag: 'APP');

    try {
      final prefs = getSharedPrefs();
      final larkEnabled = prefs.getBool('lark_enabled') ?? false;
      final reportEnabled = prefs.getBool('lark_daily_report_enabled') ?? false;

      if (larkEnabled && reportEnabled) {
        final webhookUrl = prefs.getString('lark_webhook_url') ?? '';
        if (webhookUrl.isNotEmpty) {
          final reportService = LarkReportService.instance;
          await reportService.sendDailyReport();
          AppLogger.info('✅ Lark daily report sent from alarm', tag: 'APP');
        } else {
          AppLogger.warning('⚠️ Lark report skipped: no webhook URL configured', tag: 'APP');
        }
      }
    } catch (e) {
      AppLogger.error('❌ Lark report alarm error: $e', tag: 'APP');
    } finally {
      // أعد جدولة لليوم التالي
      final prefs = getSharedPrefs();
      final timeString = prefs.getString('lark_daily_report_time') ?? '08:00';
      final parts = timeString.split(':');
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      await scheduleLarkReportAlarm(hour, minute);
    }
  }
}
