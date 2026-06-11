import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/alarm_backup.dart';
import '../services/remote_config_service.dart';
import '../services/telegram/telegram_config.dart';
import '../services/telegram/telegram_report_service.dart';
import '../utils/env.dart';

/// حالة إعداد التقرير اليومي عبر واتساب
enum WhatsAppReportStatus {
  idle,
  testing,
  success,
  error,
  sendingReport,
}

/// حالة التقرير اليومي عبر واتساب
class WhatsAppDailyReportState {

  const WhatsAppDailyReportState({
    this.status = WhatsAppReportStatus.idle,
    this.message,
    this.isEnabled = true,
    this.isNotificationsEnabled = true,
    this.isDailyReportEnabled = true,
    this.dailyReportTime = '02:00',
    this.lastReportSent,
    this.phoneNumber = Env.whatsappPhoneNumber,
    this.apiKey = Env.whatsappApiKey,
  });
  final WhatsAppReportStatus status;
  final String? message;
  final bool isEnabled;
  final bool isNotificationsEnabled;
  final bool isDailyReportEnabled;
  final String dailyReportTime;
  final String? lastReportSent;
  final String phoneNumber;
  final String apiKey;

  WhatsAppDailyReportState copyWith({
    WhatsAppReportStatus? status,
    String? message,
    bool? isEnabled,
    bool? isNotificationsEnabled,
    bool? isDailyReportEnabled,
    String? dailyReportTime,
    String? lastReportSent,
    String? phoneNumber,
    String? apiKey,
  }) {
    return WhatsAppDailyReportState(
      status: status ?? this.status,
      message: message ?? this.message,
      isEnabled: isEnabled ?? this.isEnabled,
      isNotificationsEnabled: isNotificationsEnabled ?? this.isNotificationsEnabled,
      isDailyReportEnabled: isDailyReportEnabled ?? this.isDailyReportEnabled,
      dailyReportTime: dailyReportTime ?? this.dailyReportTime,
      lastReportSent: lastReportSent ?? this.lastReportSent,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}

/// Notifier للتحكم في حالة التقرير اليومي عبر واتساب
class WhatsAppDailyReportNotifier extends StateNotifier<WhatsAppDailyReportState> {
  WhatsAppDailyReportNotifier() : super(const WhatsAppDailyReportState()) {
    _initialize();
  }

  final TelegramReportService _reports = TelegramReportService.instance();
  bool _mounted = true;

  /// تهيئة الحالة من SharedPreferences
  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('telegram_enabled') ?? true;
      final notificationsEnabled = prefs.getBool('telegram_notifications_enabled') ?? true;
      final dailyReportEnabled = prefs.getBool('telegram_daily_report_enabled') ?? true;
      final reportTime = prefs.getString('telegram_daily_report_time') ?? '02:00';
      final lastReportSent = prefs.getString('telegram_last_report_sent');

      state = state.copyWith(
        isEnabled: enabled,
        isNotificationsEnabled: notificationsEnabled,
        isDailyReportEnabled: dailyReportEnabled,
        dailyReportTime: reportTime,
        lastReportSent: lastReportSent,
      );

      // حفظ رقم الهاتف ومفتاح API في SharedPreferences كاحتياطي
      final phone = RemoteConfigService.instance.whatsappPhone;
      final apiKey = RemoteConfigService.instance.whatsappApiKey;
      if (phone.isNotEmpty) {
        await prefs.setString('whatsapp_phone', phone);
      }
      if (apiKey.isNotEmpty) {
        await prefs.setString('whatsapp_api_key', apiKey);
      }
    } catch (e) {
      debugPrint('خطأ في تهيئة WhatsAppDailyReportNotifier: $e');
    }
  }

  /// تفعيل/تعطيل واتساب (كامل)
  Future<void> setEnabled(bool enabled) async {
    await TelegramConfig.setEnabled(enabled);
    state = state.copyWith(
      isEnabled: enabled,
      status: WhatsAppReportStatus.success,
      message: enabled ? 'تم تفعيل واتساب — الإشعارات والتقارير نشطة' : 'تم تعطيل واتساب',
    );
    _clearMessageAfterDelay();
  }

  /// تفعيل/تعطيل الإشعارات الفورية
  Future<void> setNotificationsEnabled(bool enabled) async {
    await TelegramConfig.setNotificationsEnabled(enabled);
    state = state.copyWith(
      isNotificationsEnabled: enabled,
      status: WhatsAppReportStatus.success,
      message: enabled ? 'تم تفعيل الإشعارات الفورية عبر واتساب' : 'تم تعطيل الإشعارات الفورية',
    );
    _clearMessageAfterDelay();
  }

  /// تفعيل/تعطيل الإرسال التلقائي
  Future<void> setDailyReportEnabled(bool enabled) async {
    await TelegramConfig.setDailyReportEnabled(enabled);
    state = state.copyWith(
      isDailyReportEnabled: enabled,
      status: WhatsAppReportStatus.success,
      message: enabled ? 'تم تفعيل التقرير اليومي التلقائي' : 'تم تعطيل التقرير اليومي التلقائي',
    );
    // جدولة/إلغاء إنذار التقرير اليومي
    try {
      if (enabled && state.isEnabled) {
        final parts = state.dailyReportTime.split(':');
        await AlarmBackup.rescheduleTelegramReport(
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      } else {
        await AlarmBackup.cancelTelegramReportAlarm();
      }
    } catch (e) {
      debugPrint('خطأ في جدولة إنذار التقرير اليومي: $e');
    }
    _clearMessageAfterDelay();
  }

  /// تحديث وقت التقرير
  Future<void> setDailyReportTime(String time) async {
    await TelegramConfig.setDailyReportTime(time);
    state = state.copyWith(dailyReportTime: time);
    // إعادة جدولة إنذار التقرير بالوقت الجديد
    try {
      if (state.isDailyReportEnabled && state.isEnabled) {
        final parts = time.split(':');
        await AlarmBackup.rescheduleTelegramReport(
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      }
    } catch (e) {
      debugPrint('خطأ في إعادة جدولة إنذار التقرير: $e');
    }
  }

  /// اختبار الاتصال — إرسال رسالة اختبار عبر CallMeBot
  Future<void> testConnection() async {
    state = state.copyWith(
      status: WhatsAppReportStatus.testing,
      message: 'جاري اختبار الاتصال بواتساب...',
    );

    try {
      final success = await _reports.sendReportNow();

      if (success) {
        state = state.copyWith(
          status: WhatsAppReportStatus.success,
          message: 'تم اختبار الاتصال بنجاح! تحقق من واتساب',
        );
      } else {
        state = state.copyWith(
          status: WhatsAppReportStatus.error,
          message: 'فشل اختبار الاتصال — تحقق من رقم الهاتف و API Key',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: WhatsAppReportStatus.error,
        message: 'خطأ في الاتصال: $e',
      );
    }

    _clearMessageAfterDelay();
  }

  /// إرسال تقرير تجريبي
  Future<void> sendTestReport() async {
    state = state.copyWith(
      status: WhatsAppReportStatus.sendingReport,
      message: 'جاري تجميع وإرسال التقرير...',
    );

    try {
      final success = await _reports.sendReportNow();

      if (success) {
        state = state.copyWith(
          status: WhatsAppReportStatus.success,
          message: 'تم إرسال التقرير التجريبي بنجاح عبر واتساب!',
        );
      } else {
        state = state.copyWith(
          status: WhatsAppReportStatus.error,
          message: 'فشل إرسال التقرير — تحقق من الإعدادات',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: WhatsAppReportStatus.error,
        message: 'خطأ في إرسال التقرير: $e',
      );
    }

    _clearMessageAfterDelay();
  }

  /// إرسال التقرير اليومي
  Future<bool> sendDailyReport() async {
    try {
      return await _reports.sendDailyReport();
    } catch (e) {
      debugPrint('خطأ في إرسال التقرير اليومي: $e');
      return false;
    }
  }

  /// مسح رسالة الحالة
  void _clearMessageAfterDelay() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!_mounted) {
        return;
      }
      if (state.status == WhatsAppReportStatus.success ||
          state.status == WhatsAppReportStatus.error) {
        state = state.copyWith(status: WhatsAppReportStatus.idle);
      }
    });
  }

  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }

  /// مسح حالة آخر تقرير
  Future<void> resetLastReport() async {
    await TelegramConfig.clearLastReport();
    state = state.copyWith();
  }
}

/// Provider رئيسي للتقرير اليومي عبر واتساب
final whatsappDailyReportProvider = StateNotifierProvider.autoDispose<WhatsAppDailyReportNotifier, WhatsAppDailyReportState>(
  (ref) => WhatsAppDailyReportNotifier(),
);

/// Provider للوصول إلى خدمة التقارير
final whatsappDailyReportServiceProvider = Provider.autoDispose<TelegramReportService>(
  (ref) => TelegramReportService.instance(),
);
