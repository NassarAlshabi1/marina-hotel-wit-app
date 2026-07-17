import 'package:shared_preferences/shared_preferences.dart';

/// مفاتيح التخزين المحلي لإعدادات Lark
class LarkConfig { // 5 دقائق قبل الانتهاء

  LarkConfig._();
  static const String _enabledKey = 'lark_enabled';
  static const String _appIdKey = 'lark_app_id';
  static const String _appSecretKey = 'lark_app_secret';
  static const String _webhookUrlKey = 'lark_webhook_url';
  static const String _notificationsEnabledKey = 'lark_notifications_enabled';
  static const String _dailyReportEnabledKey = 'lark_daily_report_enabled';
  static const String _dailyReportTimeKey = 'lark_daily_report_time';
  static const String _dailyReportChatIdKey = 'lark_daily_report_chat_id';
  static const String _lastReportSentKey = 'lark_last_report_sent';
  static const String _tokenCacheKey = 'lark_token_cache';
  static const String _tokenExpiryKey = 'lark_token_expiry';
  static const String _baseUrlKey = 'lark_base_url';

  // القيم الافتراضية
  static const String defaultBaseUrl = 'https://open.larksuite.com';
  static const String defaultReportTime = '08:00';
  static const int tokenExpiryBufferSeconds = 300;

  /// التحقق من تفعيل Lark بشكل عام
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  /// App ID
  static Future<String> getAppId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_appIdKey) ?? '';
  }

  static Future<void> setAppId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appIdKey, value);
  }

  /// App Secret
  static Future<String> getAppSecret() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_appSecretKey) ?? '';
  }

  static Future<void> setAppSecret(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appSecretKey, value);
  }

  /// Webhook URL (للإشعارات السريعة بدون مصادقة)
  static Future<String> getWebhookUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_webhookUrlKey) ?? '';
  }

  static Future<void> setWebhookUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_webhookUrlKey, value);
  }

  /// تفعيل/تعطيل الإشعارات الفورية
  static Future<bool> isNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? true;
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);
  }

  /// تفعيل/تعطيل التقرير اليومي
  static Future<bool> isDailyReportEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dailyReportEnabledKey) ?? false;
  }

  static Future<void> setDailyReportEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dailyReportEnabledKey, enabled);
  }

  /// وقت إرسال التقرير اليومي
  static Future<String> getDailyReportTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dailyReportTimeKey) ?? defaultReportTime;
  }

  static Future<void> setDailyReportTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyReportTimeKey, time);
  }

  /// معرف مجموعة/محادثة Lark لإرسال التقرير
  static Future<String> getDailyReportChatId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dailyReportChatIdKey) ?? '';
  }

  static Future<void> setDailyReportChatId(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyReportChatIdKey, chatId);
  }

  /// آخر تقرير تم إرساله (لمنع التكرار)
  static Future<String?> getLastReportSent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastReportSentKey);
  }

  static Future<void> setLastReportSent(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastReportSentKey, dateKey);
  }

  /// تخزين مؤقت لرمز المصادقة
  static Future<String?> getTokenCache() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenCacheKey);
  }

  static Future<void> setTokenCache(String token, int expiryEpoch) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenCacheKey, token);
    await prefs.setInt(_tokenExpiryKey, expiryEpoch);
  }

  static Future<int?> getTokenExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_tokenExpiryKey);
  }

  static Future<void> clearTokenCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenCacheKey);
    await prefs.remove(_tokenExpiryKey);
  }

  /// Base URL (larksuite.com أو feishu.cn)
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
  }

  /// التحقق من اكتمال إعدادات Lark (App ID + App Secret)
  static Future<bool> isConfigured() async {
    final appId = await getAppId();
    final appSecret = await getAppSecret();
    final webhookUrl = await getWebhookUrl();
    return appId.isNotEmpty && appSecret.isNotEmpty || webhookUrl.isNotEmpty;
  }

  /// التحقق من صلاحية رمز المصادقة المخزن
  static Future<bool> hasValidToken() async {
    final token = await getTokenCache();
    final expiry = await getTokenExpiry();
    if (token == null || expiry == null) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now < (expiry - tokenExpiryBufferSeconds);
  }
}
