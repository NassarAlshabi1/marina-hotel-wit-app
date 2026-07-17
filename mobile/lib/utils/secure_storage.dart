import 'dart:convert';

import 'package:crypto/crypto.dart';

class SecureStorage {
  static const _staticSecret = 'marina_hotel_sync_secret_2024';
  static const _prefix = 'ENC:';

  /// يُولّد مفتاح تشفير ثابت (32 بايت) مشتق من [_staticSecret].
  ///
  /// ✅ إصلاح RangeError (2026-07-04): كان الإصدار السابق يبني `keyBytes`
  /// بطول السر (29 بايت) ثم يستدعي `keyBytes.sublist(0, 32)` — وهذا يرمي
  /// `RangeError (end): Invalid value: Not in inclusive range 0..29: 32`
  /// لأن القائمة أقصر من 32. كان يمنع رفع `app_settings` نهائيًا.
  ///
  /// الحل: SHA-256 يُنتج 32 بايت دائمًا بغضّ النظر عن طول السر، فلا RangeError.
  /// ملاحظة توافق رجعي: الإصدار السابق لم ينجح أبدًا في إنتاج مفتاح صالح،
  /// لذا لم تُرفع أي قيمة مشفّرة (`ENC:...`) قط — لا خطر من تغيير الاشتقاق.
  static String getEncryptionKey(String? deviceId) {
    // For shared settings synced across devices, use constant key.
    // SECURITY: XOR is obfuscation only - use encrypt package for production.
    final digest = sha256.convert(utf8.encode(_staticSecret));
    return base64.encode(digest.bytes); // digest.bytes.length == 32 مضمونة
  }

  static String encryptValue(String plain, String key) {
    final keyBytes = utf8.encode(key);
    final plainBytes = utf8.encode(plain);
    final encrypted = <int>[];
    for (var i = 0; i < plainBytes.length; i++) {
      encrypted.add(plainBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    return '$_prefix${base64.encode(encrypted)}';
  }

  static String decryptValue(String value, String key) {
    if (!value.startsWith(_prefix)) {
      return value;
    }
    final cipherText = value.substring(_prefix.length);
    try {
      final keyBytes = utf8.encode(key);
      final cipherBytes = base64.decode(cipherText);
      final decrypted = <int>[];
      for (var i = 0; i < cipherBytes.length; i++) {
        decrypted.add(cipherBytes[i] ^ keyBytes[i % keyBytes.length]);
      }
      return utf8.decode(decrypted);
    } catch (e) {
      return value;
    }
  }
}
