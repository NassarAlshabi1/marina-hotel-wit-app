// lib/utils/whatsapp_token_storage.dart
//
// ✅ إصلاح أمني: WhatsApp API Token يُخزَّن الآن في FlutterSecureStorage
// بدلاً من SharedPreferences. SharedPreferences على Android ليس مشفّراً
// افتراضياً — أي جهاز rooted يقرأ الـ token مباشرة من
// `/data/data/<package>/shared_prefs/`.
//
// هذا يُطابق الإصلاح الذي طُبّق على Telegram Bot Token (انظر
// `telegram_config.dart` — P0-7، 2026-08-06) الذي كان بلا مقابل لتوكن
// الواتساب حتى الآن.
//
// FlutterSecureStorage يستخدم:
// - Android: EncryptedSharedPreferences (AES-256-GCM) + Master Key في Android Keystore
// - iOS: Keychain
// - Windows: DPAPI
//
// توافق رجعي: عند أول استدعاء لـ [read]، إذا كان الـ token موجوداً في
// SharedPreferences (الصيغة القديمة)، يُهاجر تلقائياً إلى SecureStorage
// ويُحذف من SharedPreferences.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تخزين آمن لتوكن API الخاص بالواتساب.
class WhatsAppTokenStorage {
  WhatsAppTokenStorage._();

  /// المفتاح القديم في SharedPreferences (نص صريح — غير آمن).
  static const String legacyKey = 'wa_api_token';

  /// المفتاح الجديد في FlutterSecureStorage.
  static const String _secureKey = 'wa_api_token_secure';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static bool _migrationDone = false;

  /// ترحيل التوكن من SharedPreferences (نص صريح) إلى SecureStorage، مرة واحدة فقط.
  static Future<void> _migrateIfNeeded() async {
    if (_migrationDone) return;
    _migrationDone = true;

    try {
      final secureValue = await _secureStorage.read(key: _secureKey);
      final prefs = await SharedPreferences.getInstance();
      if (secureValue != null && secureValue.isNotEmpty) {
        // موجود بالفعل في SecureStorage — تنظيف أي بقايا قديمة.
        if (prefs.containsKey(legacyKey)) {
          await prefs.remove(legacyKey);
        }
        return;
      }

      final legacyValue = prefs.getString(legacyKey);
      if (legacyValue != null && legacyValue.isNotEmpty) {
        await _secureStorage.write(key: _secureKey, value: legacyValue);
        await prefs.remove(legacyKey);
      }
    } catch (_) {
      // فشل الترحيل — ليس حرجاً، read() سيتعامل مع fallback.
    }
  }

  /// قراءة التوكن الحالي (بعد ترحيل أي قيمة قديمة إن وُجدت).
  static Future<String?> read() async {
    await _migrateIfNeeded();
    try {
      return await _secureStorage.read(key: _secureKey);
    } catch (_) {
      return null;
    }
  }

  /// كتابة التوكن إلى SecureStorage فقط — بلا fallback إلى SharedPreferences
  /// (تخزينه بنص صريح يُفشي التوكن على الأجهزة المروَّتة).
  static Future<void> write(String value) async {
    await _secureStorage.write(key: _secureKey, value: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(legacyKey)) {
        await prefs.remove(legacyKey);
      }
    } catch (_) {
      // تنظيف اختياري — فشله لا يمنع الحفظ الآمن أعلاه.
    }
  }

  /// حذف التوكن من كلا المخزنين (الآمن والقديم).
  static Future<void> delete() async {
    try {
      await _secureStorage.delete(key: _secureKey);
    } catch (_) {
      // تجاهل — المحاولة الثانية تالياً.
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(legacyKey)) {
        await prefs.remove(legacyKey);
      }
    } catch (_) {
      // لا شيء آخر يمكن فعله هنا.
    }
  }
}
