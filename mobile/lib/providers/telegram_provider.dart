import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/telegram/telegram_config.dart';
import '../services/telegram/telegram_service.dart';
import '../services/telegram/telegram_notification_service.dart';
import '../services/telegram/telegram_report_service.dart';

/// حالة إعداد Telegram
enum TelegramSetupStatus {
  idle,
  testing,
  success,
  error,
  sendingReport,
}

/// حالة Telegram الكاملة
class TelegramState {
  final TelegramSetupStatus status;
  final String? message;
  final bool isEnabled;
  final bool isConfigured;
  final bool isNotificationsEnabled;
  final bool isDailyReportEnabled;
  final String botToken;
  final String chatId;
  final String dailyReportTime;
  final String? lastReportSent;

  const TelegramState({
    this.status = TelegramSetupStatus.idle,
    this.message,
    this.isEnabled = false,
    this.isConfigured = false,
    this.isNotificationsEnabled = false,
    this.isDailyReportEnabled = false,
    this.botToken = '',
    this.chatId = '',
    this.dailyReportTime = '08:00',
    this.lastReportSent,
  });

  TelegramState copyWith({
    TelegramSetupStatus? status,
    String? message,
    bool? isEnabled,
    bool? isConfigured,
    bool? isNotificationsEnabled,
    bool? isDailyReportEnabled,
    String? botToken,
    String? chatId,
    String? dailyReportTime,
    String? lastReportSent,
  }) {
    return TelegramState(
      status: status ?? this.status,
      message: message ?? this.message,
      isEnabled: isEnabled ?? this.isEnabled,
      isConfigured: isConfigured ?? this.isConfigured,
      isNotificationsEnabled: isNotificationsEnabled ?? this.isNotificationsEnabled,
      isDailyReportEnabled: isDailyReportEnabled ?? this.isDailyReportEnabled,
      botToken: botToken ?? this.botToken,
      chatId: chatId ?? this.chatId,
      dailyReportTime: dailyReportTime ?? this.dailyReportTime,
      lastReportSent: lastReportSent ?? this.lastReportSent,
    );
  }
}

/// Notifier للتحكم في حالة Telegram
class TelegramNotifier extends StateNotifier<TelegramState> {
  TelegramNotifier() : super(const TelegramState()) {
    _initialize();
  }

  final TelegramApiClient _api = TelegramApiClient.instance;
  final TelegramNotificationService _notifications = TelegramNotificationService.instance;
  final TelegramReportService _reports = TelegramReportService.instance;

  /// تهيئة الحالة من SharedPreferences
  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('telegram_enabled') ?? false;
      final botToken = prefs.getString('telegram_bot_token') ?? '';
      final chatId = prefs.getString('telegram_chat_id') ?? '';
      final notificationsEnabled = prefs.getBool('telegram_notifications_enabled') ?? true;
      final dailyReportEnabled = prefs.getBool('telegram_daily_report_enabled') ?? false;
      final reportTime = prefs.getString('telegram_daily_report_time') ?? '08:00';
      final lastReportSent = prefs.getString('telegram_last_report_sent');
      final configured = await TelegramConfig.isConfigured();

      state = state.copyWith(
        isEnabled: enabled,
        botToken: botToken,
        chatId: chatId,
        isConfigured: configured,
        isNotificationsEnabled: notificationsEnabled,
        isDailyReportEnabled: dailyReportEnabled,
        dailyReportTime: reportTime,
        lastReportSent: lastReportSent,
      );
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة TelegramNotifier: $e');
    }
  }

  /// تفعيل/تعطيل Telegram
  Future<void> setEnabled(bool enabled) async {
    await TelegramConfig.setEnabled(enabled);
    state = state.copyWith(
      isEnabled: enabled,
      status: TelegramSetupStatus.success,
      message: enabled ? 'تم تفعيل Telegram' : 'تم تعطيل Telegram',
    );
    _clearMessageAfterDelay();
  }

  /// تحديث Bot Token
  Future<void> setBotToken(String token) async {
    await TelegramConfig.setBotToken(token);
    final configured = await TelegramConfig.isConfigured();
    state = state.copyWith(
      botToken: token,
      isConfigured: configured,
    );
  }

  /// تحديث Chat ID
  Future<void> setChatId(String id) async {
    await TelegramConfig.setChatId(id);
    final configured = await TelegramConfig.isConfigured();
    state = state.copyWith(
      chatId: id,
      isConfigured: configured,
    );
  }

  /// تفعيل/تعطيل الإشعارات الفورية
  Future<void> setNotificationsEnabled(bool enabled) async {
    await TelegramConfig.setNotificationsEnabled(enabled);
    state = state.copyWith(
      isNotificationsEnabled: enabled,
      status: TelegramSetupStatus.success,
      message: enabled ? 'تم تفعيل الإشعارات الفورية' : 'تم تعطيل الإشعارات الفورية',
    );
    _clearMessageAfterDelay();
  }

  /// تفعيل/تعطيل التقرير اليومي
  Future<void> setDailyReportEnabled(bool enabled) async {
    await TelegramConfig.setDailyReportEnabled(enabled);
    state = state.copyWith(
      isDailyReportEnabled: enabled,
      status: TelegramSetupStatus.success,
      message: enabled ? 'تم تفعيل التقرير اليومي التلقائي' : 'تم تعطيل التقرير اليومي التلقائي',
    );
    _clearMessageAfterDelay();
  }

  /// تحديث وقت التقرير
  Future<void> setDailyReportTime(String time) async {
    await TelegramConfig.setDailyReportTime(time);
    state = state.copyWith(dailyReportTime: time);
  }

  /// اختبار الاتصال
  Future<void> testConnection() async {
    state = state.copyWith(
      status: TelegramSetupStatus.testing,
      message: 'جاري اختبار الاتصال...',
    );

    try {
      final success = await _api.testSendMessage();

      if (success) {
        state = state.copyWith(
          status: TelegramSetupStatus.success,
          message: '✅ تم اختبار الاتصال بنجاح! تحقق من Telegram',
        );
      } else {
        state = state.copyWith(
          status: TelegramSetupStatus.error,
          message: '❌ فشل اختبار الاتصال — تحقق من Bot Token و Chat ID',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: TelegramSetupStatus.error,
        message: '❌ خطأ في الاتصال: ${e.toString()}',
      );
    }

    _clearMessageAfterDelay();
  }

  /// إرسال تقرير تجريبي
  Future<void> sendTestReport() async {
    state = state.copyWith(
      status: TelegramSetupStatus.sendingReport,
      message: 'جاري تجميع وإرسال التقرير...',
    );

    try {
      final success = await _reports.sendReportNow();

      if (success) {
        state = state.copyWith(
          status: TelegramSetupStatus.success,
          message: '✅ تم إرسال التقرير التجريبي بنجاح!',
        );
      } else {
        state = state.copyWith(
          status: TelegramSetupStatus.error,
          message: '❌ فشل إرسال التقرير — تحقق من الإعدادات',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: TelegramSetupStatus.error,
        message: '❌ خطأ في إرسال التقرير: ${e.toString()}',
      );
    }

    _clearMessageAfterDelay();
  }

  /// إرسال التقرير اليومي
  Future<bool> sendDailyReport() async {
    try {
      return await _reports.sendDailyReport();
    } catch (e) {
      debugPrint('❌ خطأ في إرسال التقرير اليومي: $e');
      return false;
    }
  }

  /// مسح رسالة الحالة
  void _clearMessageAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (state.status == TelegramSetupStatus.success ||
          state.status == TelegramSetupStatus.error) {
        state = state.copyWith(status: TelegramSetupStatus.idle, message: null);
      }
    });
  }

  /// مسح حالة آخر تقرير
  Future<void> resetLastReport() async {
    await TelegramConfig.clearLastReport();
    state = state.copyWith(lastReportSent: null);
  }
}

/// Provider رئيسي لـ Telegram
final telegramProvider = StateNotifierProvider<TelegramNotifier, TelegramState>(
  (ref) => TelegramNotifier(),
);

/// Provider للوصول إلى خدمة الإشعارات
final telegramNotificationServiceProvider = Provider<TelegramNotificationService>(
  (ref) => TelegramNotificationService.instance,
);

/// Provider للوصول إلى خدمة التقارير
final telegramReportServiceProvider = Provider<TelegramReportService>(
  (ref) => TelegramReportService.instance,
);
