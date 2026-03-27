import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_drive_backup_service.dart';
import 'local_backup_service.dart';
import 'package:flutter/widgets.dart';

class AlarmBackup {
  static const int alarmId = 0;

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
    await _notif.initialize(initializationSettings: initSettings);
    debugPrint('✅ Alarm system initialized');

    // تفعيل النسخ المجدول تلقائياً عند التثبيت لأول مرة
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('scheduled_backup_enabled') == null) {
      debugPrint('🚀 First run: Enable scheduled backup by default');
      await prefs.setBool('scheduled_backup_enabled', true);
      // وقت افتراضي 9:00 مساءً
      await prefs.setString('auto_backup_time', '21:00');
      await scheduleDailyAlarm(21, 0);
    }
  }

  /// جدولة إنذار يومي وقت محدد (hour, minute)
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

    debugPrint('✅ Alarm scheduled at $scheduled');
  }

  /// لإلغاء وإعادة جدولة — استخدمها عند تغيير الوقت
  static Future<void> rescheduleDaily(int hour, int minute) async {
    await AndroidAlarmManager.cancel(alarmId);
    await Future.delayed(const Duration(milliseconds: 300));
    await scheduleDailyAlarm(hour, minute);
    debugPrint('♻️ Alarm rescheduled to $hour:$minute');
  }

  /// الكولباك الذي ينفذ وقت الإنذار — يجب أن يكون top-level أو static annotated
  @pragma('vm:entry-point')
  static Future<void> _alarmCallback() async {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('🔔 Alarm fired: performing backup');

    try {
      final prefs = await SharedPreferences.getInstance();
      final enableGoogleDrive = prefs.getBool('auto_backup_enabled') ?? false;
      final enableLocal = prefs.getBool('auto_local_backup_enabled') ?? true;

      final localService = LocalBackupService();
      final format = await localService.getPreferredBackupFormat();

      if (enableLocal) {
        try {
          await localService.createLocalBackup(format: format);
          debugPrint('✅ Local backup done from alarm');
        } catch (e) {
          debugPrint('❌ Local backup error: $e');
        }
      }

      if (enableGoogleDrive) {
        try {
          final drive = GoogleDriveBackupService();

          // حاول تسجيل الدخول بهدوء
          final signed = await drive.signInSilentlyIfNeeded();
          if (signed) {
            await drive.performAutoBackup();
            debugPrint('✅ Drive backup done from alarm');
          } else {
            debugPrint('⚠️ Drive not signed in (alarm). Notifying user...');
            await _showOpenAppNotification();
          }
        } catch (e) {
          debugPrint('❌ Drive backup error: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Alarm backup general error: $e');
    } finally {
      // أعد جدولة الإنذار لليوم التالي في نفس الوقت
      final prefs = await SharedPreferences.getInstance();
      final timeString = prefs.getString('auto_backup_time') ?? '21:00';
      final timeParts = timeString.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
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
      playSound: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notif.show(
      id: 0,
      title: 'نسخة احتياطية فشلت',
      body: 'يرجى فتح التطبيق لتسجيل الدخول وإكمال النسخة',
      notificationDetails: details,
    );
  }

  /// إلغاء الإنذار
  static Future<void> cancelAlarm() async {
    await AndroidAlarmManager.cancel(alarmId);
    debugPrint('🚫 Alarm cancelled');
  }
}
