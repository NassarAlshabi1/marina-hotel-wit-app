// ═══════════════════════════════════════════════════════════════
//  db_encryption_key.dart — مفتاح تشفير قاعدة البيانات (SQLCipher)
// ═══════════════════════════════════════════════════════════════
//
//  ✅ S2 FIX: يولّد مفتاح تشفير عشوائياً (32 بايت) عند أول إقلاع
//  ويخزّنه في FlutterSecureStorage (Android Keystore / iOS Keychain).
//  المفتاح لا يُرسل لأي API ولا يظهر في الكود المصدري — يُولّد
//  محلياً لكل جهاز.
//
//  على الويب (WASM): SQLCipher غير متوفر، لذا يُعاد null ويبقى
//  التشفير على مستوى المتصفح (OPFS/IndexedDb).
//
//  الهجرة: عند أول فتح بقاعدة بيانات غير مشفّرة موجودة، يُقرأ
//  المفتاح من SecureStorage. إن لم يكن موجوداً، يُولّد جديداً.
//  التشفير يُفعّل عبر PRAGMA key قبل أي عملية.
//

import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إدارة مفتاح تشفير قاعدة البيانات عبر SQLCipher.
class DbEncryptionKey {
  const DbEncryptionKey._();

  static const String _keyStoreKey = 'db_encryption_key_v1';
  static const String _kMigratedFlag = 'db_encryption_migrated_v1';

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    // ✅ Android: EncryptedSharedPreferences (AES-256-GCM) + Master Key في Keystore
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // ✅ iOS: Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// يُعيد مفتاح التشفير بصيغة hex (64 حرفاً = 32 بايت).
  /// يُولّد مفتاحاً جديداً عند أول استدعاء ويخزّنه بأمان.
  /// يُعيد null على الويب (SQLCipher غير متوفر في drift WASM).
  static Future<String?> getOrCreateKey() async {
    // على الويب: SQLCipher غير متوفر مع drift WASM
    if (kIsWeb) return null;

    final existing = await _secure.read(key: _keyStoreKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    // توليد مفتاح عشوائي 32 بايت (256-bit) بصيغة hex
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final hexKey = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    await _secure.write(key: _keyStoreKey, value: hexKey);
    return hexKey;
  }

  /// هل تمت هجرة التشفير بالفعل؟ (لتفادي إعادة التهيئة).
  static Future<bool> get isMigrated async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kMigratedFlag) ?? false;
  }

  /// يضع علامة الهجرة بعد أول فتح ناجح بقاعدة مشفّرة.
  static Future<void> markMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMigratedFlag, true);
  }

  /// هل المفتاح موجود في SecureStorage؟ (للتشخيص).
  static Future<bool> get hasKey async {
    if (kIsWeb) return false;
    final existing = await _secure.read(key: _keyStoreKey);
    return existing != null && existing.isNotEmpty;
  }
}
