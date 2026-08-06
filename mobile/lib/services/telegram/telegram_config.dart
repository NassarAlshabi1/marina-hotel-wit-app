import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/env.dart';

/// مفاتيح التخزين المحلي لإعدادات Telegram
///
/// ✅ P0-7 FIX (2026-08-06 Audit): Bot Token يُخزَّن الآن في FlutterSecureStorage
/// بدلاً من SharedPreferences. SharedPreferences على Android ليس مشفّراً
/// افتراضياً — أي جهاز rooted يقرأ الـ token مباشرة من
/// `/data/data/<package>/shared_prefs/`.
///
/// FlutterSecureStorage يستخدم:
/// - Android: EncryptedSharedPreferences (AES-256-GCM) + Master Key في Android Keystore
/// - iOS: Keychain
/// - Windows: DPAPI
///
/// توافق رجعي: عند أول استدعاء لـ getBotToken()، إذا كان الـ token موجوداً
/// في SharedPreferences (legacy)، يُهاجر تلقائياً لـ SecureStorage ويُحذف
/// من SharedPreferences.
class TelegramConfig {
  TelegramConfig._();
  static const String _enabledKey = 'telegram_enabled';
  static const String _botTokenKey = 'telegram_bot_token';
  static const String _chatIdKey = 'telegram_chat_id';
  static const String _notificationsEnabledKey =
      'telegram_notifications_enabled';
  static const String _dailyReportEnabledKey = 'telegram_daily_report_enabled';
  static const String _dailyReportTimeKey = 'telegram_daily_report_time';
  static const String _lastReportSentKey = 'telegram_last_report_sent';

  /// ✅ P0-7: مفتاح SecureStorage للـ Bot Token
  static const String _botTokenSecureKey = 'telegram_bot_token_secure';

  // القيم الافتراضية — تُحمّل تلقائياً حتى بعد إلغاء التثبيت وإعادة التثبيت
  static const String defaultReportTime = '02:00';
  static const String telegramApiBase = 'https://api.telegram.org';
  static const String defaultBotToken = Env.telegramBotToken;
  static const String defaultChatId = Env.telegramChatId;

  /// ✅ P0-7: FlutterSecureStorage instance مع إعدادات أمان قوية
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      // استخدام KeyStore مع resetOnError لمنع corruption
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// ✅ P0-7: علامة لإجراء migration مرة واحدة فقط
  static bool _migrationDone = false;

  /// ✅ P0-7: ترحيل Bot Token من SharedPreferences إلى SecureStorage
  static Future<void> _migrateTokenToSecureStorage() async {
    if (_migrationDone) return;
    _migrationDone = true;

    try {
      // 1. التحقق مما إذا كان الـ token موجوداً في SecureStorage بالفعل
      final secureToken = await _secureStorage.read(key: _botTokenSecureKey);
      if (secureToken != null && secureToken.isNotEmpty) {
        // الـ token موجود في SecureStorage — نحذفه من SharedPreferences إن وُجد
        final prefs = await SharedPreferences.getInstance();
        if (prefs.containsKey(_botTokenKey)) {
          await prefs.remove(_botTokenKey);
        }
        return;
      }

      // 2. محاولة قراءة الـ token من SharedPreferences (legacy)
      final prefs = await SharedPreferences.getInstance();
      final legacyToken = prefs.getString(_botTokenKey);

      if (legacyToken != null && legacyToken.isNotEmpty) {
        // 3. ترحيل الـ token إلى SecureStorage
        await _secureStorage.write(
          key: _botTokenSecureKey,
          value: legacyToken,
        );
        // 4. حذف الـ token من SharedPreferences
        await prefs.remove(_botTokenKey);
      }
    } catch (e) {
      // فشل الترحيل — ليس حرجاً، getBotToken() سيتعامل مع fallback
    }
  }

  /// التحقق من تفعيل Telegram/WhatsApp — مفعّل افتراضياً
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  /// Bot Token — يُحمّل القيمة الافتراضية تلقائياً
  ///
  /// ✅ P0-7: يقرأ من FlutterSecureStorage. عند أول استدعاء، يُهاجر
  /// الـ token من SharedPreferences (إن وُجد) إلى SecureStorage.
  static Future<String> getBotToken() async {
    await _migrateTokenToSecureStorage();

    try {
      final token = await _secureStorage.read(key: _botTokenSecureKey);
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (e) {
      // فشل قراءة SecureStorage — fallback إلى default
    }
    return defaultBotToken;
  }

  /// ✅ P0-7: يكتب Bot Token إلى FlutterSecureStorage فقط
  static Future<void> setBotToken(String value) async {
    try {
      await _secureStorage.write(key: _botTokenSecureKey, value: value);
      // حذف الـ token من SharedPreferences إن وُجد (legacy cleanup)
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_botTokenKey)) {
        await prefs.remove(_botTokenKey);
      }
    } catch (e) {
      // فشل الكتابة في SecureStorage — fallback إلى SharedPreferences
      // (أفضل من فقدان الـ token تماماً)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_botTokenKey, value);
    }
  }

  /// Chat ID — يُحمّل القيمة الافتراضية تلقائياً
  /// (Chat ID ليس سرّاً حساساً مثل Bot Token، يبقى في SharedPreferences)
  static Future<String> getChatId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_chatIdKey) ?? defaultChatId;
  }

  static Future<void> setChatId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatIdKey, value);
  }

  /// تفعيل/تعطيل الإشعارات الفورية — مفعّل افتراضياً
  static Future<bool> isNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? true;
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);
  }

  /// تفعيل/تعطيل التقرير اليومي — مفعّل افتراضياً
  static Future<bool> isDailyReportEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dailyReportEnabledKey) ?? true;
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

  /// التحقق من اكتمال إعدادات Telegram — دائماً صحيح بالافتراضي
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
