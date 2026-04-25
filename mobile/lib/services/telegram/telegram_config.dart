import 'package:shared_preferences/shared_preferences.dart';

/// مفاتيح التخزين المحلي لإعدادات WhatsApp عبر CallMeBot
class TelegramConfig {
  static const String _enabledKey = 'telegram_enabled';
  static const String _botTokenKey = 'telegram_bot_token';
  static const String _chatIdKey = 'telegram_chat_id';
  static const String _notificationsEnabledKey = 'telegram_notifications_enabled';
  static const String _dailyReportEnabledKey = 'telegram_daily_report_enabled';
  static const String _dailyReportTimeKey = 'telegram_daily_report_time';
  static const String _lastReportSentKey = 'telegram_last_report_sent';

  // القيم الافتراضية — CallMeBot WhatsApp
  static const String defaultReportTime = '02:00';
  static const String callMeBotUrl = 'https://api.callmebot.com/whatsapp.php';
  static const String defaultBotToken = '7379268'; // CallMeBot API Key
  static const String defaultChatId = '967773749389'; // رقم الهاتف بدون +

  TelegramConfig._();

  /// التحقق من تفعيل WhatsApp
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  /// API Key — يُحمّل القيمة الافتراضية تلقائياً
  static Future<String> getBotToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_botTokenKey) ?? defaultBotToken;
  }

  static Future<void> setBotToken(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_botTokenKey, value);
  }

  /// رقم الهاتف — يُحمّل القيمة الافتراضية تلقائياً
  static Future<String> getChatId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_chatIdKey) ?? defaultChatId;
  }

  static Future<void> setChatId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatIdKey, value);
  }

  /// تفعيل/تعطيل الإشعارات الفورية
  static Future<bool> isNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? false;
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

  /// آخر تقرير تم إرساله
  static Future<String?> getLastReportSent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastReportSentKey);
  }

  static Future<void> setLastReportSent(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastReportSentKey, dateKey);
  }

  /// التحقق من اكتمال إعدادات CallMeBot — دائماً صحيح بالافتراضي
  static Future<bool> isConfigured() async {
    final token = await getBotToken();
    final chatId = await getChatId();
    return token.isNotEmpty && chatId.isNotEmpty;
  }

  /// مسح حالة آخر تقرير
  static Future<void> clearLastReport() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastReportSentKey);
  }
}
