// lib/services/fcm_jwt_helper.dart
//
// ✅ مساعد OAuth2 لـ FCM HTTP v1 API
//
// ignore_for_file: avoid_redundant_argument_values
//
// يحوّل مفتاح حساب الخدمة (Service Account JSON) إلى Access Token صالح
// لإرسال إشعارات FCM عبر HTTP v1 API الحديث:
//
//   POST https://fcm.googleapis.com/v1/projects/{project_id}/messages:send
//   Authorization: Bearer <access_token>
//
// آلية العمل:
//   1. يبني JWT header + payload
//   2. يوقّعها بـ RS256 باستخدام private_key من حساب الخدمة
//   3. يطلب access_token من https://oauth2.googleapis.com/token
//   4. يخزّن الـ token مؤقتاً (1 ساعة) — يُجدّد قبل الانتهاء بـ 5 دقائق
//
// الأمان:
//   - private_key يبقى في الذاكرة فقط — لا يُكتب على القرص
//   - access_token يُخزّن في الذاكرة فقط (لا SharedPreferences)
//
// التنفيذ:
//   - يستخدم pointycastle لـ RS256 signing فقط (PKCS1Encoding + RSASigner).
//   - يستخدم parser DER يدوي بسيط لاستخراج (modulus, privateExponent, prime1,
//     prime2) من مفتاح RSA بصيغة PKCS#8 أو PKCS#1. هذا أكثر موثوقية من
//     الاعتماد على ASN1 classes التي قد تتغير أسماؤها بين إصدارات pointycastle.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' as pc;

/// نموذج مفتاح حساب خدمة Firebase (يحوي الحقول اللازمة فقط).
class FcmServiceAccountCredentials {
  FcmServiceAccountCredentials({
    required this.projectId,
    required this.privateKey,
    required this.clientEmail,
    required this.privateKeyId,
  });

  /// يبني الكائن من JSON (محتوى fcm-key.json).
  ///
  /// يُرمي [FormatException] إذا كان JSON ناقصاً أو تالفاً.
  factory FcmServiceAccountCredentials.fromJson(Map<String, dynamic> json) {
    final projectId = json['project_id'] as String?;
    final privateKey = json['private_key'] as String?;
    final clientEmail = json['client_email'] as String?;
    final privateKeyId = json['private_key_id'] as String?;

    if (projectId == null || projectId.isEmpty) {
      throw const FormatException('missing project_id in service account JSON');
    }
    if (privateKey == null || privateKey.isEmpty) {
      throw const FormatException('missing private_key in service account JSON');
    }
    if (clientEmail == null || clientEmail.isEmpty) {
      throw const FormatException(
        'missing client_email in service account JSON',
      );
    }

    return FcmServiceAccountCredentials(
      projectId: projectId,
      privateKey: privateKey,
      clientEmail: clientEmail,
      privateKeyId: privateKeyId ?? '',
    );
  }

  /// يبني الكائن من سلسلة JSON.
  factory FcmServiceAccountCredentials.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return FcmServiceAccountCredentials.fromJson(json);
  }

  /// يبني الكائن من base64-encoded JSON (الشكل المُمرَّر عبر --dart-define).
  factory FcmServiceAccountCredentials.fromBase64(String base64String) {
    final jsonStr = utf8.decode(base64Decode(base64String));
    return FcmServiceAccountCredentials.fromJsonString(jsonStr);
  }

  final String projectId;
  final String privateKey;
  final String clientEmail;
  final String privateKeyId;
}

/// نتيجة طلب OAuth2 token.
class _TokenResponse {
  const _TokenResponse({required this.accessToken, required this.expiresAt});
  final String accessToken;
  final DateTime expiresAt;
}

/// مسؤول عن minting + caching الـ access tokens لـ FCM HTTP v1.
///
/// Singleton — يُشارك الـ token بين كل الاستدعاءات في نفس دورة حياة التطبيق.
class FcmJwtHelper {
  factory FcmJwtHelper() => _instance;
  FcmJwtHelper._internal();
  static final FcmJwtHelper _instance = FcmJwtHelper._internal();
  static FcmJwtHelper get instance => _instance;

  FcmServiceAccountCredentials? _credentials;
  _TokenResponse? _cachedToken;
  // قفل بسيط لمنع طلبين متزامنين لتجديد الـ token
  bool _refreshing = false;

  /// تعيين بيانات الاعتماد (يُستدعى مرة واحدة من FcmSender عند التهيئة).
  void configure(FcmServiceAccountCredentials credentials) {
    _credentials = credentials;
    _cachedToken = null;
  }

  /// هل تم تكوين البيانات؟
  bool get isConfigured => _credentials != null;

  /// الحصول على access token صالح (يُجدّد تلقائياً عند الاقتراب من الانتهاء).
  ///
  /// يُرجع null إذا لم يتم تكوين البيانات أو فشل التجديد.
  Future<String?> getAccessToken() async {
    if (_credentials == null) {
      debugPrint('⚠️ FcmJwtHelper: not configured');
      return null;
    }

    // تحقق من الـ cache — نُجدّد قبل 5 دقائق من الانتهاء لتجنّب الـ edge cases
    if (_cachedToken != null &&
        _cachedToken!.expiresAt.isAfter(DateTime.now().add(
      const Duration(minutes: 5),
    ))) {
      return _cachedToken!.accessToken;
    }

    // إذا كان هناك تحديث جارٍ، انتظره ثم أعد المحاولة
    if (_refreshing) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return getAccessToken();
    }

    _refreshing = true;
    try {
      final token = await _refreshToken(_credentials!);
      if (token != null) {
        _cachedToken = token;
        return token.accessToken;
      }
      return null;
    } finally {
      _refreshing = false;
    }
  }

  /// طلب access token جديد من Google OAuth2.
  Future<_TokenResponse?> _refreshToken(
    FcmServiceAccountCredentials creds,
  ) async {
    try {
      // 1. بناء JWT
      final jwt = _buildJwt(creds);

      // 2. طلب الـ token
      final response = await http
          .post(
            Uri.parse('https://oauth2.googleapis.com/token'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
              'assertion': jwt,
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
          '⚠️ FcmJwtHelper: OAuth2 token request failed: '
          '${response.statusCode} ${response.body}',
        );
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = body['access_token'] as String?;
      final expiresIn = body['expires_in'] as int?;
      if (accessToken == null || expiresIn == null) {
        debugPrint('⚠️ FcmJwtHelper: malformed OAuth2 response: ${response.body}');
        return null;
      }

      debugPrint('✅ FcmJwtHelper: OAuth2 token obtained (expires in ${expiresIn}s)');
      return _TokenResponse(
        accessToken: accessToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      );
    } catch (e, st) {
      debugPrint('⚠️ FcmJwtHelper: OAuth2 token request error: $e\n$st');
      return null;
    }
  }

  /// بناء JWT موقّع بـ RS256 لاستخدامه في طلب OAuth2.
  String _buildJwt(FcmServiceAccountCredentials creds) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiry = now + 3600; // 1 ساعة

    final header = <String, String>{
      'alg': 'RS256',
      'typ': 'JWT',
      if (creds.privateKeyId.isNotEmpty) 'kid': creds.privateKeyId,
    };

    final payload = <String, dynamic>{
      'iss': creds.clientEmail,
      'scope': 'https://www.googleapis.com/auth/firebase.messaging',
      'aud': 'https://oauth2.googleapis.com/token',
      'exp': expiry,
      'iat': now,
    };

    final headerB64 = _base64Url(jsonEncode(header));
    final payloadB64 = _base64Url(jsonEncode(payload));
    final signingInput = '$headerB64.$payloadB64';

    final signature = _signRs256(signingInput, creds.privateKey);
    return '$signingInput.$signature';
  }

  /// توقيع RS256 لسلسلة باستخدام private key بصيغة PEM.
  ///
  /// الخطوات:
  ///   1. تنظيف PEM من headers و newlines الزائدة
  ///   2. فك base64 → DER bytes
  ///   3. استخراج (modulus, d, p, q) من DER عبر parser يدوي بسيط
  ///   4. توقيع SHA-256 مع PKCS1 v1.5 padding عبر pointycastle
  String _signRs256(String data, String privateKeyPem) {
    // 1. تنظيف PEM من headers و newlines الزائدة
    final keyLines = privateKeyPem
        .split('\n')
        .where(
          (l) => !l.startsWith('-----') && l.trim().isNotEmpty,
        )
        .join('');
    final keyBytes = base64.decode(keyLines);

    // 2. استخراج مكونات RSA من DER
    final rsaComponents = _extractRsaComponents(keyBytes);

    // 3. بناء RSAPrivateKey + توقيع
    final rsaKey = pc.RSAPrivateKey(
      rsaComponents.modulus,
      rsaComponents.privateExponent,
      rsaComponents.primeP,
      rsaComponents.primeQ,
    );

    // 4. RSA signing with PKCS#1 v1.5 padding + SHA-256
    //
    // pointycastle approach: use PKCS1Encoding as an AsymmetricBlockCipher.
    // We "encrypt" the SHA-256 digest of the data with the private key —
    // the result IS the signature (RSA signing = encryption with private key).
    //
    // Note: For RSA signing, init(forEncryption: true) with a private key
    // produces a signature. init(false) would verify with a public key.
    final dataBytes = utf8.encode(data);
    final digest = sha256.convert(dataBytes).bytes;

    // Build the DigestInfo manually (DER-encoded SHA-256 OID + digest).
    // This is required because PKCS1Encoding.process() expects the FULL
    // DigestInfo, not just the raw hash.
    final digestInfo = _buildSha256DigestInfo(digest);

    final cipher = pc.PKCS1Encoding(pc.RSAEngine())
      ..init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(rsaKey));
    final signature = cipher.process(digestInfo);

    return _base64UrlBytes(signature);
  }

  /// Build the DER-encoded DigestInfo for SHA-256.
  ///
  /// PKCS#1 v1.5 signing requires the input to be a DER-encoded structure:
  ///
  ///   DigestInfo ::= SEQUENCE {
  ///     digestAlgorithm  AlgorithmIdentifier,  -- SHA-256 OID
  ///     digest           OCTET STRING          -- the actual hash
  ///   }
  ///
  /// The SHA-256 OID is 2.16.840.1.101.3.4.2.1, DER-encoded as:
  ///   30 31 30 0d 06 09 60 86 48 01 65 03 04 02 01 05 00 04 20 <32-byte hash>
  ///
  /// Total prefix: 19 bytes, then the 32-byte SHA-256 digest = 51 bytes total.
  static Uint8List _buildSha256DigestInfo(List<int> digest) {
    // Pre-computed DER prefix for SHA-256 DigestInfo (RFC 3447 section 9.2)
    const prefix = [
      0x30, 0x31, // SEQUENCE, length 49
      0x30, 0x0d, // SEQUENCE (AlgorithmIdentifier), length 13
      0x06, 0x09, // OID, length 9
      0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, // SHA-256 OID
      0x05, 0x00, // NULL (parameters)
      0x04, 0x20, // OCTET STRING, length 32
    ];
    final result = Uint8List(prefix.length + digest.length);
    result.setRange(0, prefix.length, prefix);
    result.setRange(prefix.length, prefix.length + digest.length, digest);
    return result;
  }

  /// base64Url-encode بدون padding (لمتوافقية JWT).
  String _base64Url(String input) {
    return _base64UrlBytes(utf8.encode(input));
  }

  String _base64UrlBytes(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

// ═══════════════════════════════════════════════════════════════
//  Manual DER parser for RSA private keys
// ═══════════════════════════════════════════════════════════════

/// مكونات RSA private key المستخرجة من DER.
class _RsaComponents {
  const _RsaComponents({
    required this.modulus,
    required this.privateExponent,
    required this.primeP,
    required this.primeQ,
  });
  final BigInt modulus; // n
  final BigInt privateExponent; // d
  final BigInt primeP; // p
  final BigInt primeQ; // q
}

/// Parser DER بسيط لقراءة RSA private keys.
///
/// DER (Distinguished Encoding Rules) هو تنسيق ثنائي لـ ASN.1.
/// RSA private key له بنية:
///
///   RSAPrivateKey ::= SEQUENCE {
///     version           INTEGER,
///     modulus           INTEGER,  -- n
///     publicExponent    INTEGER,  -- e
///     privateExponent   INTEGER,  -- d
///     prime1            INTEGER,  -- p
///     prime2            INTEGER,  -- q
///     exponent1         INTEGER,  -- d mod (p-1)
///     exponent2         INTEGER,  -- d mod (q-1)
///     coefficient       INTEGER,  -- (inverse of q) mod p
///   }
///
/// في PKCS#8، يُغلّف هذا الـ SEQUENCE داخل:
///
///   PrivateKeyInfo ::= SEQUENCE {
///     version         INTEGER (0),
///     algorithm       AlgorithmIdentifier,  -- SEQUENCE { OID, NULL }
///     privateKey      OCTET STRING           -- يحوي RSAPrivateKey DER-encoded
///   }
class _DerReader {
  _DerReader(this.bytes);
  final List<int> bytes;
  int offset = 0;

  bool get hasMore => offset < bytes.length;

  /// قراءة byte واحد وتحريك المؤشر.
  int readByte() {
    if (offset >= bytes.length) {
      throw FormatException('Unexpected end of DER at offset $offset');
    }
    return bytes[offset++];
  }

  /// قراءة طول حقل DER (قد يكون 1-byte short form أو multi-byte long form).
  int readLength() {
    final first = readByte();
    if (first < 0x80) {
      // Short form: length is the byte itself (0-127)
      return first;
    }
    // Long form: first byte's lower 7 bits = number of length bytes
    final numBytes = first & 0x7F;
    if (numBytes == 0 || numBytes > 4) {
      throw FormatException('Invalid DER length encoding: $first');
    }
    var length = 0;
    for (var i = 0; i < numBytes; i++) {
      length = (length << 8) | readByte();
    }
    return length;
  }

  /// قراءة tag + length + value. يُرجع الـ value bytes.
  ///
  /// [expectedTag] إن لم يكن null، يتحقق أن الـ tag المطابق متطابق.
  List<int> readTaggedValue({int? expectedTag}) {
    final tag = readByte();
    if (expectedTag != null && tag != expectedTag) {
      throw FormatException(
        'Expected DER tag 0x${expectedTag.toRadixString(16)}, got 0x${tag.toRadixString(16)} at offset ${offset - 1}',
      );
    }
    final length = readLength();
    final value = bytes.sublist(offset, offset + length);
    offset += length;
    return value;
  }

  /// قراءة SEQUENCE (tag 0x30) — يُرجع reader جديد للمحتوى.
  _DerReader readSequence() {
    final value = readTaggedValue(expectedTag: 0x30);
    return _DerReader(value);
  }

  /// قراءة INTEGER (tag 0x02) — يُرجع BigInt.
  BigInt readInteger() {
    final value = readTaggedValue(expectedTag: 0x02);
    // DER INTEGER قد يبدأ بـ 0x00 padding byte لضمان أن القيمة موجبة
    return _decodeBigInt(value);
  }

  /// قراءة OCTET STRING (tag 0x04) — يُرجع bytes.
  List<int> readOctetString() {
    return readTaggedValue(expectedTag: 0x04);
  }

  /// فك ترميز BigInt من bytes (big-endian, signed).
  static BigInt _decodeBigInt(List<int> bytes) {
    if (bytes.isEmpty) return BigInt.zero;
    // تجاهل الـ 0x00 padding الأولي إن وُجد (يُستخدم لضمان الإشارة الموجبة)
    var start = 0;
    while (start < bytes.length - 1 && bytes[start] == 0) {
      start++;
    }
    var result = BigInt.zero;
    for (var i = start; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }
}

/// استخراج (modulus, d, p, q) من RSA private key بصيغة DER.
///
/// يدعم PKCS#8 (يبدأ بـ SEQUENCE { INTEGER(0), SEQUENCE, OCTET STRING })
/// و PKCS#1 (يبدأ مباشرة بـ RSAPrivateKey SEQUENCE).
_RsaComponents _extractRsaComponents(List<int> derBytes) {
  // محاولة 1: PKCS#8
  try {
    final pkcs8Reader = _DerReader(derBytes);
    final topSeq2 = pkcs8Reader.readSequence();
    // version (INTEGER 0)
    topSeq2.readInteger();
    // algorithm (SEQUENCE) — نتخطاه
    topSeq2.readSequence();
    // privateKey (OCTET STRING) — يحوي RSAPrivateKey DER-encoded
    final rsaKeyDer = topSeq2.readOctetString();
    // الآن نحلل RSAPrivateKey من الداخل
    final innerReader = _DerReader(rsaKeyDer);
    final rsaSeq = innerReader.readSequence();
    rsaSeq.readInteger(); // version
    final modulus = rsaSeq.readInteger(); // n
    rsaSeq.readInteger(); // e
    final d = rsaSeq.readInteger(); // d
    final p = rsaSeq.readInteger(); // p
    final q = rsaSeq.readInteger(); // q
    return _RsaComponents(
      modulus: modulus,
      privateExponent: d,
      primeP: p,
      primeQ: q,
    );
  } catch (e) {
      debugPrint('⚠️ Swallowed error in fcm_jwt_helper.dart: ');
    // ليست PKCS#8 — جرب PKCS#1
  }

  // محاولة 2: PKCS#1
  // نعيد القراءة من البداية باستخدام reader جديد
  final pkcs1Reader = _DerReader(derBytes);
  final rsaSeq2 = pkcs1Reader.readSequence();
  rsaSeq2.readInteger(); // version
  final modulus = rsaSeq2.readInteger(); // n
  rsaSeq2.readInteger(); // e
  final d = rsaSeq2.readInteger(); // d
  final p = rsaSeq2.readInteger(); // p
  final q = rsaSeq2.readInteger(); // q
  return _RsaComponents(
    modulus: modulus,
    privateExponent: d,
    primeP: p,
    primeQ: q,
  );
}
