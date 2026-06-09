import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lark/lark_api_client.dart';
import '../services/lark/lark_config.dart';
import '../services/lark/lark_notification_service.dart';
import '../services/lark/lark_report_service.dart';

/// حالة Lark في الواجهة
enum LarkSetupStatus {
  idle,
  testing,
  success,
  error,
  sendingReport,
}

/// حالة Lark الكاملة
class LarkState {

  const LarkState({
    this.status = LarkSetupStatus.idle,
    this.message,
    this.isEnabled = false,
    this.isConfigured = false,
    this.isNotificationsEnabled = false,
    this.isDailyReportEnabled = false,
    this.webhookUrl = '',
    this.appId = '',
    this.dailyReportTime = '08:00',
    this.dailyReportChatId = '',
    this.lastReportSent,
    this.hasValidToken = false,
  });
  final LarkSetupStatus status;
  final String? message;
  final bool isEnabled;
  final bool isConfigured;
  final bool isNotificationsEnabled;
  final bool isDailyReportEnabled;
  final String webhookUrl;
  final String appId;
  final String dailyReportTime;
  final String dailyReportChatId;
  final String? lastReportSent;
  final bool hasValidToken;

  LarkState copyWith({
    LarkSetupStatus? status,
    String? message,
    bool? isEnabled,
    bool? isConfigured,
    bool? isNotificationsEnabled,
    bool? isDailyReportEnabled,
    String? webhookUrl,
    String? appId,
    String? dailyReportTime,
    String? dailyReportChatId,
    String? lastReportSent,
    bool? hasValidToken,
  }) {
    return LarkState(
      status: status ?? this.status,
      message: message ?? this.message,
      isEnabled: isEnabled ?? this.isEnabled,
      isConfigured: isConfigured ?? this.isConfigured,
      isNotificationsEnabled: isNotificationsEnabled ?? this.isNotificationsEnabled,
      isDailyReportEnabled: isDailyReportEnabled ?? this.isDailyReportEnabled,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      appId: appId ?? this.appId,
      dailyReportTime: dailyReportTime ?? this.dailyReportTime,
      dailyReportChatId: dailyReportChatId ?? this.dailyReportChatId,
      lastReportSent: lastReportSent ?? this.lastReportSent,
      hasValidToken: hasValidToken ?? this.hasValidToken,
    );
  }
}

/// Notifier للتحكم في حالة Lark
class LarkNotifier extends StateNotifier<LarkState> {
  LarkNotifier() : super(const LarkState()) {
    _initialize();
  }

  final LarkApiClient _api = LarkApiClient.instance;
  final LarkReportService _reports = LarkReportService.instance;
  bool _mounted = true;

  /// تهيئة الحالة من SharedPreferences
  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('lark_enabled') ?? false;
      final webhookUrl = prefs.getString('lark_webhook_url') ?? '';
      final appId = prefs.getString('lark_app_id') ?? '';
      final notificationsEnabled = prefs.getBool('lark_notifications_enabled') ?? true;
      final dailyReportEnabled = prefs.getBool('lark_daily_report_enabled') ?? false;
      final reportTime = prefs.getString('lark_daily_report_time') ?? '08:00';
      final reportChatId = prefs.getString('lark_daily_report_chat_id') ?? '';
      final lastReportSent = prefs.getString('lark_last_report_sent');
      final configured = await LarkConfig.isConfigured();
      final hasToken = await LarkConfig.hasValidToken();

      state = state.copyWith(
        isEnabled: enabled,
        webhookUrl: webhookUrl,
        appId: appId,
        isConfigured: configured,
        isNotificationsEnabled: notificationsEnabled,
        isDailyReportEnabled: dailyReportEnabled,
        dailyReportTime: reportTime,
        dailyReportChatId: reportChatId,
        lastReportSent: lastReportSent,
        hasValidToken: hasToken,
      );
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة LarkNotifier: $e');
    }
  }

  /// تفعيل/تعطيل Lark بشكل عام
  Future<void> setEnabled(bool enabled) async {
    await LarkConfig.setEnabled(enabled);

    // عند التعطيل، مسح الرمز المخزن
    if (!enabled) {
      await _api.invalidateToken();
    }

    state = state.copyWith(
      isEnabled: enabled,
      status: LarkSetupStatus.success,
      message: enabled ? 'تم تفعيل Lark Suite' : 'تم تعطيل Lark Suite',
    );

    // مسح الرسالة بعد 3 ثوانٍ
    _clearMessageAfterDelay();
  }

  /// تحديث Webhook URL
  Future<void> setWebhookUrl(String url) async {
    await LarkConfig.setWebhookUrl(url);
    final configured = await LarkConfig.isConfigured();

    state = state.copyWith(
      webhookUrl: url,
      isConfigured: configured,
    );
  }

  /// تحديث App ID
  Future<void> setAppId(String id) async {
    await LarkConfig.setAppId(id);
    await _api.invalidateToken();
    final configured = await LarkConfig.isConfigured();

    state = state.copyWith(
      appId: id,
      isConfigured: configured,
      hasValidToken: false,
    );
  }

  /// تحديث App Secret
  Future<void> setAppSecret(String secret) async {
    await LarkConfig.setAppSecret(secret);
    await _api.invalidateToken();

    final configured = await LarkConfig.isConfigured();
    state = state.copyWith(
      isConfigured: configured,
      hasValidToken: false,
    );
  }

  /// تفعيل/تعطيل الإشعارات الفورية
  Future<void> setNotificationsEnabled(bool enabled) async {
    await LarkConfig.setNotificationsEnabled(enabled);
    state = state.copyWith(
      isNotificationsEnabled: enabled,
      status: LarkSetupStatus.success,
      message: enabled
          ? 'تم تفعيل الإشعارات الفورية'
          : 'تم تعطيل الإشعارات الفورية',
    );
    _clearMessageAfterDelay();
  }

  /// تفعيل/تعطيل التقرير اليومي
  Future<void> setDailyReportEnabled(bool enabled) async {
    await LarkConfig.setDailyReportEnabled(enabled);
    state = state.copyWith(
      isDailyReportEnabled: enabled,
      status: LarkSetupStatus.success,
      message: enabled
          ? 'تم تفعيل التقرير اليومي التلقائي'
          : 'تم تعطيل التقرير اليومي التلقائي',
    );
    _clearMessageAfterDelay();
  }

  /// تحديث وقت إرسال التقرير اليومي
  Future<void> setDailyReportTime(String time) async {
    await LarkConfig.setDailyReportTime(time);
    state = state.copyWith(dailyReportTime: time);
  }

  /// تحديث معرف مجموعة التقرير
  Future<void> setReportChatId(String chatId) async {
    await LarkConfig.setDailyReportChatId(chatId);
    state = state.copyWith(dailyReportChatId: chatId);
  }

  /// اختبار الاتصال
  Future<void> testConnection() async {
    state = state.copyWith(
      status: LarkSetupStatus.testing,
      message: 'جاري اختبار الاتصال...',
    );

    try {
      final success = await _api.testConnection();

      if (success) {
        state = state.copyWith(
          status: LarkSetupStatus.success,
          message: '✅ تم اختبار الاتصال بنجاح!',
        );
      } else {
        state = state.copyWith(
          status: LarkSetupStatus.error,
          message: '❌ فشل اختبار الاتصال — تحقق من الإعدادات',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: LarkSetupStatus.error,
        message: '❌ خطأ في الاتصال: $e',
      );
    }

    _clearMessageAfterDelay();
  }

  /// إرسال تقرير تجريبي (فوري)
  Future<void> sendTestReport() async {
    state = state.copyWith(
      status: LarkSetupStatus.sendingReport,
      message: 'جاري تجميع وإرسال التقرير...',
    );

    try {
      final success = await _reports.sendReportNow();

      if (success) {
        state = state.copyWith(
          status: LarkSetupStatus.success,
          message: '✅ تم إرسال التقرير التجريبي بنجاح!',
        );
      } else {
        state = state.copyWith(
          status: LarkSetupStatus.error,
          message: '❌ فشل إرسال التقرير — تحقق من Webhook URL',
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: LarkSetupStatus.error,
        message: '❌ خطأ في إرسال التقرير: $e',
      );
    }

    _clearMessageAfterDelay();
  }

  /// إرسال التقرير اليومي (مجدول أو يدوي)
  Future<bool> sendDailyReport() async {
    try {
      return await _reports.sendDailyReport();
    } catch (e) {
      debugPrint('❌ خطأ في إرسال التقرير اليومي: $e');
      return false;
    }
  }

  /// مسح رسالة الحالة بعد 3 ثوانٍ
  void _clearMessageAfterDelay() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!_mounted) {
        return;
      }
      if (state.status == LarkSetupStatus.success ||
          state.status == LarkSetupStatus.error) {
        state = state.copyWith(status: LarkSetupStatus.idle);
      }
    });
  }

  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }

  /// مسح حالة آخر تقرير (لسماح بإعادة الإرسال)
  Future<void> resetLastReport() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lark_last_report_sent');
    state = state.copyWith();
    debugPrint('🔄 Lark: تم مسح حالة آخر تقرير');
  }
}

/// Provider رئيسي لـ Lark
final larkProvider = StateNotifierProvider.autoDispose<LarkNotifier, LarkState>(
  (ref) => LarkNotifier(),
);

/// Provider للوصول إلى خدمة الإشعارات
final larkNotificationServiceProvider = Provider.autoDispose<LarkNotificationService>(
  (ref) => LarkNotificationService.instance,
);

/// Provider للوصول إلى خدمة التقارير
final larkReportServiceProvider = Provider.autoDispose<LarkReportService>(
  (ref) => LarkReportService.instance,
);
