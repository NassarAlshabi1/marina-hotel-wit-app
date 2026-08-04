// lib/services/password_hasher.dart
//
// ✅ تشفير كلمات المرور (2026-06-28 P2)
//
// يُسلّط كلمات المرور باستخدام PBKDF2 (Password-Based Key Derivation Function 2)
// مع SHA-256 و salt عشوائي لكل كلمة مرور.
//
// لماذا PBKDF2 وليس bcrypt/argon2؟
// - bcrypt و argon2 غير متوفرين بشكل أصلي في Flutter/Dart
// - PBKDF2 متوفر عبر pointycastle (موجود بالفعل في pubspec)
// - مع 100,000 تكرار، PBKDF2-HMAC-SHA-256 مقاوم للهجمات
//
// الصيغة المخزّنة: `pbkdf2_sha256$<iterations>$<salt_base64>$<hash_base64>`
// مثال: `pbkdf2_sha256$100000$Yc2lzZWx0c29sdA==$z3Jv...==`

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

/// خدمة تشفير كلمات المرور
class PasswordHasher {
  PasswordHasher._();

  /// عدد تكرارات PBKDF2 (100K — يوازن بين الأمان والأداء على الأجهزة المحمولة)
  static const int defaultIterations = 100000;

  /// طول salt بالبايت (16 بايت = 128 بت)
  static const int _saltLength = 16;

  /// طول الـ hash الناتج بالبايت (32 بايت = 256 بت)
  static const int _hashLength = 32;

  /// بادئة الخوارزمية (للتعرّف على الصيغة المستقبلية)
  static const String _algorithmPrefix = 'pbkdf2_sha256';

  /// مولّد أرقام عشوائي آمن
  static final _secureRandom = pc.SecureRandom('Fortuna')
    ..seed(pc.KeyParameter(_generateSeed()));

  /// توليد seed عشوائي للـ Fortuna PRNG
  static Uint8List _generateSeed() {
    final random = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      seed[i] = random.nextInt(256);
    }
    return seed;
  }

  /// تشفير كلمة مرور نصية → hash مخزّن
  ///
  /// يُرجع صيغة: `pbkdf2_sha256$<iterations>$<salt_base64>$<hash_base64>`
  static String hash(String password, {int? iterations}) {
    final iter = iterations ?? defaultIterations;
    final salt = _generateSalt();
    final hash = _pbkdf2(password, salt, iter);

    final saltB64 = base64.encode(salt);
    final hashB64 = base64.encode(hash);

    return '$_algorithmPrefix\$$iter\$$saltB64\$$hashB64';
  }

  /// التحقق من كلمة مرور مقابل hash مخزّن
  ///
  /// يدعم:
  /// - `pbkdf2_sha256$...` (الصيغة الجديدة)
  /// - نص صريح (legacy — للتوافق مع الإصدارات السابقة)
  static bool verify(String password, String stored) {
    if (stored.isEmpty || password.isEmpty) return false;

    // إذا لم يبدأ بالبادئة، فهو نص صريح (legacy)
    if (!stored.startsWith('$_algorithmPrefix\$')) {
      return password == stored;
    }

    try {
      final parts = stored.split(r'$');
      if (parts.length != 4) return false;
      if (parts[0] != _algorithmPrefix) return false;

      final iterations = int.parse(parts[1]);
      final salt = base64.decode(parts[2]);
      final expectedHash = base64.decode(parts[3]);

      final actualHash = _pbkdf2(password, salt, iterations);

      // مقارنة ثابتة الزمن (constant-time comparison) لمنع timing attacks
      return _constantTimeEquals(expectedHash, actualHash);
    } catch (_) {
      return false;
    }
  }

  /// هل كلمة المرور المخزّنة مشفّرة (وليست نصاً صريحاً)؟
  static bool isHashed(String stored) {
    return stored.startsWith('$_algorithmPrefix\$');
  }

  /// توليد salt عشوائي
  static Uint8List _generateSalt() {
    return _secureRandom.nextBytes(_saltLength);
  }

  /// تنفيذ PBKDF2-HMAC-SHA-256
  static Uint8List _pbkdf2(String password, Uint8List salt, int iterations) {
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final keyDerivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, iterations, _hashLength));
    return keyDerivator.process(passwordBytes);
  }

  /// مقارنة ثابتة الزمن لمنع timing attacks
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// ✅ دالة مساعدة: تشفير SHA-256 بسيط (للاستخدامات غير كلمات المرور)
  /// لكلمات المرور، استخدم [hash] و [verify] فقط.
  static String sha256Hex(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
