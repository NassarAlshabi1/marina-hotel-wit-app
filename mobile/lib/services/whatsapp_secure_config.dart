// ═══════════════════════════════════════════════════════════════
//  whatsapp_secure_config.dart — تخزين آمن لإعدادات WhatsApp API
// ═══════════════════════════════════════════════════════════════
//
//  ✅ S4 FIX: ترحيل wa_api_token من SharedPreferences (غير مشفّر على
//  Android) إلى FlutterSecureStorage (Android Keystore / iOS Keychain).
//
//  الإعدادات غير الحساسة (base_url, instance_id, api_type, url_template)
//  تبقى في SharedPreferences — فقط الـ token يُخزَّن بأمان.
//
//  الهجرة: عند أول قراءة، إن وُجد token قديم في prefs يُرحَّل تلقائياً
//  إلى SecureStorage ويُحذف من prefs (نفس نمط Telegram Bot Token).
//

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مفتاح SecureStorage لتوكن WhatsApp API.
const String _kWaTokenSecureKey = 'wa_api_token_secure';

/// مفتاح prefs القديم (للهجرة والحذف).
const String _kWaTokenLegacyKey = 'wa_api_token';

/// قراءة الـ token من SecureStorage مع هجرة تلقائية للقيم القديمة.
Future<String?> readWhatsAppToken() async {
  const secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // 1) اقرأ من SecureStorage أولاً
  final secureToken = await secure.read(key: _kWaTokenSecureKey);
  if (secureToken != null && secureToken.isNotEmpty) {
    return secureToken;
  }

  // 2) إن لم يوجد، تحقق من prefs القديم (هجرة)
  final prefs = await SharedPreferences.getInstance();
  final legacyToken = prefs.getString(_kWaTokenLegacyKey);
  if (legacyToken != null && legacyToken.isNotEmpty) {
    // ✅ هجرة: انقل القيمة إلى SecureStorage واحذفها من prefs
    await secure.write(key: _kWaTokenSecureKey, value: legacyToken);
    await prefs.remove(_kWaTokenLegacyKey);
    return legacyToken;
  }

  return null;
}

/// كتابة الـ token إلى SecureStorage.
Future<void> writeWhatsAppToken(String token) async {
  const secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  if (token.isEmpty) {
    await secure.delete(key: _kWaTokenSecureKey);
  } else {
    await secure.write(key: _kWaTokenSecureKey, value: token);
  }

  // ✅ تأكد من حذف أي نسخة قديمة من prefs (الهجرة نهائية)
  final prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey(_kWaTokenLegacyKey)) {
    await prefs.remove(_kWaTokenLegacyKey);
  }
}

/// حذف الـ token من SecureStorage.
Future<void> deleteWhatsAppToken() async {
  const secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  await secure.delete(key: _kWaTokenSecureKey);

  // ✅ احذف أيضاً من prefs إن بقي (الهجرة)
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kWaTokenLegacyKey);
}
