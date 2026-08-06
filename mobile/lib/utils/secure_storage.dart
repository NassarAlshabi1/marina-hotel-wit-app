import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// ✅ P0-3 FIX (2026-08-06 Audit): استبدال XOR بـ AES-256-CBC حقيقي.
///
/// سابقاً كان `SecureStorage` يستخدم XOR مع سر ثابت — وهو obfuscation
/// فقط وليس تشفيراً حقيقياً. أي مهاجم يفك الـ APK يحصل على السر ويفك
/// تشفير الـ tokens (Telegram Bot Token + WhatsApp API Token).
///
/// الإصلاح: استخدام AES-256-CBC من `encrypt` package مع:
/// - مفتاح 32 بايت مشتق من SHA-256 للسر الثابت (نفس المفتاح على كل
///   الأجهزة لأن الـ tokens تحتاج أن تُفك تشفيرها عبر الأجهزة)
/// - IV عشوائي 16 بايت لكل عملية تشفير (يُخزّن مع ciphertext)
/// - هذا يضمن أن نفس النص يُنتج ciphertext مختلف في كل مرة
///
/// ملاحظة: السر الثابت لا يزال نقطة ضعف — إذا تسرّب، يمكن فك التشفير.
/// الحل الجذري هو استخدام user-specific key مشتق من user ID + device ID،
/// لكن هذا يتطلب تغييرات أكبر (Phase 2).
///
/// توافق رجعي: الإصدار السابق (XOR) لم يُنتج مفتاح صالح (RangeError)،
/// لذا لم تُرفع أي قيمة مشفّرة `ENC:` قط — لا خطر من تغيير الخوارزمية.
class SecureStorage {
  /// سر ثابت للمزامنة عبر الأجهزة.
  ///
  /// ⚠️ تنبيه أمني: هذا السر مُدمج في الكود. أي مهاجم يفك الـ APK
  /// يحصل عليه. الحل الجذري هو اشتقاق المفتاح من بيانات المستخدم
  /// (Phase 2). حالياً، AES-256-CBC أقوى بكثير من XOR السابق.
  static const _staticSecret = 'marina_hotel_sync_secret_2024';

  /// Prefix للقيم المشفّرة (للتمييز عن القيم غير المشفّرة).
  static const _prefix = 'ENC:';

  /// مفتاح AES-256 (32 بايت) مشتق من SHA-256 للسر الثابت.
  ///
  /// SHA-256 يُنتج 32 بايت دائماً، وهو الطول المطلوب لـ AES-256.
  static final Key _aesKey = Key.fromUtf8(
    base64.encode(sha256.convert(utf8.encode(_staticSecret)).bytes).substring(0, 32),
  );

  /// Encrypter singleton (AES-256-CBC).
  static final Encrypter _encrypter = Encrypter(AES(_aesKey, mode: AESMode.cbc));

  /// يُولّد مفتاح تشفير (للتوافق مع الكود القديم).
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
    // ✅ P0-3 FIX: الآن نستخدم AES-256-CBC بدلاً من XOR.
    // الـ deviceId غير مُستخدم حالياً (السر ثابت عبر الأجهزة).
    // في Phase 2: اشتقاق المفتاح من user ID + device ID.
    return base64.encode(_aesKey.bytes);
  }

  /// يشفّر قيمة نصية باستخدام AES-256-CBC مع IV عشوائي.
  ///
  /// الصيغة الناتجة: `ENC:<base64(IV)>:<base64(ciphertext)>`
  /// - IV 16 بايت عشوائي لكل عملية (يمنع pattern analysis)
  /// - Ciphertext بتشفير AES-256-CBC + PKCS7 padding
  static String encryptValue(String plain, String key) {
    // ✅ P0-3 FIX: AES-256-CBC بدلاً من XOR.
    // IV عشوائي لكل عملية تشفير (يُخزّن مع ciphertext لفك التشفير لاحقاً).
    final iv = IV.fromSecureRandom(16);
    final encrypted = _encrypter.encrypt(plain, iv: iv);

    // الصيغة: ENC:<base64(IV)>:<base64(ciphertext)>
    // استخدام الفاصل ':' آمن لأن base64 لا يحتوي عليه.
    return '$_prefix${base64.encode(iv.bytes)}:${encrypted.base64}';
  }

  /// يفك تشفير قيمة نصية مشفّرة بـ AES-256-CBC.
  ///
  /// يقبل:
  /// - القيم المشفّرة الجديدة (AES): `ENC:<base64(IV)>:<base64(ciphertext)>`
  /// - القيم غير المشفّرة (يُعيدها كما هي)
  /// - القيم المشفّرة بـ XOR القديم (يحاول fallback)
  static String decryptValue(String value, String key) {
    if (!value.startsWith(_prefix)) {
      // ليست مشفّرة — إعادة كما هي
      return value;
    }

    final payload = value.substring(_prefix.length);

    // محاولة فك التشفير بصيغة AES الجديدة: <base64(IV)>:<base64(ciphertext)>
    final aesParts = payload.split(':');
    if (aesParts.length == 2) {
      try {
        final iv = IV.fromBase64(aesParts[0]);
        final encrypted = Encrypted.fromBase64(aesParts[1]);
        return _encrypter.decrypt(encrypted, iv: iv);
      } catch (e) {
        // ليس AES صالح — قد يكون XOR قديم، نحاول fallback أدناه
      }
    }

    // Fallback: محاولة فك التشفير بصيغة XOR القديمة (للتوافق الرجعي).
    // ✅ ملاحظة: كما ذُكر في التعليقات، الإصدار السابق لم ينجح في إنتاج
    // مفتاح صالح، لذا من غير المحتمل وجود قيم XOR فعلية. هذا fallback
    // احتياطي فقط.
    try {
      final keyBytes = utf8.encode(key);
      final cipherBytes = base64.decode(payload);
      final decrypted = <int>[];
      for (var i = 0; i < cipherBytes.length; i++) {
        decrypted.add(cipherBytes[i] ^ keyBytes[i % keyBytes.length]);
      }
      return utf8.decode(decrypted);
    } catch (e) {
      // فشل كل المحاولات — إعادة القيمة الأصلية
      return value;
    }
  }
}
