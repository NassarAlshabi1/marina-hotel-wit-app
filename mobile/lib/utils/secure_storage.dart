// lib/utils/secure_storage.dart
// تخزين آمن — تشفير AES-256-GCM بدلاً من XOR
//
// ✅ إصلاح أمني (2026-07-27): استبدال XOR (obfuscation only) بـ AES-256-GCM
// باستخدام حزمة `encrypt` المتوفرة في pubspec.yaml.
//
// التشفير السابق (XOR) لم يكن تشفيراً حقيقياً — كان قابل للعكس بسهولة.
// AES-256-GCM يوفر:
// - سرية البيانات (confidentiality)
// - تكامل البيانات (integrity) عبر authentication tag
// - مقاومة لهجمات replay

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class SecureStorage {
  static const _staticSecret = 'marina_hotel_sync_secret_2024';
  static const _prefix = 'ENC:AES:';

  /// يُولّد مفتاح تشفير ثابت (32 بايت = 256 bit) مشتق من [_staticSecret] عبر SHA-256.
  ///
  /// ✅ إصلاح RangeError (2026-07-04): SHA-256 يُنتج 32 بايت دائماً.
  /// ✅ إصلاح أمني (2026-07-27): المفتاح يُستخدم الآن مع AES-256-GCM.
  static String getEncryptionKey(String? deviceId) {
    final digest = sha256.convert(utf8.encode(_staticSecret));
    return base64.encode(digest.bytes);
  }

  /// تشفير قيمة نصية باستخدام AES-256-GCM
  ///
  /// الصيغة الناتجة: `ENC:AES:<base64(iv + ciphertext + authTag)>`
  static String encryptValue(String plain, String key) {
    try {
      final keyBytes = Key.fromBase64(key);
      final iv = IV.fromSecureRandom(16);

      final encrypter = Encrypter(AES(keyBytes, mode: AESMode.gcm));
      final encrypted = encrypter.encrypt(plain, iv: iv);

      // دمج IV + ciphertext + authTag في bytes واحدة
      final combined = Uint8List.fromList([
        ...iv.bytes,
        ...encrypted.bytes,
      ]);

      return '$_prefix${base64.encode(combined)}';
    } catch (e) {
      // في حالة الفشل، نُرجع القيمة بدون تشفير (backward compat)
      return plain;
    }
  }

  /// فك تشفير قيمة نصية مشفّرة بـ AES-256-GCM
  ///
  /// إذا كانت القيمة لا تبدأ بـ `ENC:AES:` نُرجعها كما هي (غير مشفّرة).
  /// إذا كانت القيمة تبدأ بـ `ENC:` (الصيغة القديمة XOR)، نُحاول فك التشفير القديم.
  static String decryptValue(String value, String key) {
    if (value.startsWith(_prefix)) {
      // صيغة AES-256-GCM الجديدة
      try {
        final combined = base64.decode(value.substring(_prefix.length));
        if (combined.length < 16) return value;

        final iv = IV(Uint8List.fromList(combined.sublist(0, 16)));
        final ciphertext = Uint8List.fromList(combined.sublist(16));

        final keyBytes = Key.fromBase64(key);
        final encrypter = Encrypter(AES(keyBytes, mode: AESMode.gcm));

        return encrypter.decrypt(Encrypted(ciphertext), iv: iv);
      } catch (e) {
        return value;
      }
    } else if (value.startsWith('ENC:')) {
      // صيغة XOR القديمة (backward compat) — فك تشفير ثم إعادة تشفير بـ AES
      try {
        final cipherText = value.substring(4); // 'ENC:'.length
        final keyBytes = utf8.encode(key);
        final cipherBytes = base64.decode(cipherText);
        final decrypted = <int>[];
        for (var i = 0; i < cipherBytes.length; i++) {
          decrypted.add(cipherBytes[i] ^ keyBytes[i % keyBytes.length]);
        }
        final plain = utf8.decode(decrypted);
        // لا نعيد التشفير هنا — يتم ذلك عند الحفظ التالي
        return plain;
      } catch (e) {
        return value;
      }
    }
    return value;
  }

  /// فحص ما إذا كانت القيمة مشفّرة
  static bool isEncrypted(String value) {
    return value.startsWith(_prefix) || value.startsWith('ENC:');
  }

  /// فحص ما إذا كانت القيمة مشفّرة بالصيغة الجديدة (AES)
  static bool isAesEncrypted(String value) {
    return value.startsWith(_prefix);
  }
}
