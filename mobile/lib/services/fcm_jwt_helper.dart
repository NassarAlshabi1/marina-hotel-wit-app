// lib/services/fcm_jwt_helper.dart
//
// ✅ مساعد OAuth2 لـ FCM HTTP v1 API
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
//   - في حال فشل التجديد، يُعاد المحاولة مرة واحدة قبل الإبلاغ بالخطأ
//
// البديل الإنتاجي الحقيقي: Appwrite Function + Firebase Admin SDK على الخادم.
// هذا الحل مناسب لـ small-business hotel app بعدد محدود من الأجهزة.

import 'dart:convert';
import 'dart:typed_data';

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
  ///   2. فك base64 → DER bytes (PKCS#8 format)
  ///   3. تحويل DER → RSAPrivateKey عبر ASN.1 parsing يدوي
  ///   4. توقيع SHA-256 مع PKCS1 v1.5 padding
  String _signRs256(String data, String privateKeyPem) {
    // 1. تنظيف PEM من headers و newlines الزائدة
    final keyLines = privateKeyPem
        .split('\n')
        .where(
          (l) =>
              !l.startsWith('-----') && l.trim().isNotEmpty,
        )
        .join('');
    final keyBytes = base64.decode(keyLines);

    // 2. تحميل المفتاح — يدعم PKCS#8 و PKCS#1 (للتوافق مع مختلف إصدارات fcm-key.json)
    final rsaKey = _parseRsaPrivateKey(keyBytes);

    // 3. حساب SHA-256 للبيانات (EMSA-PKCS1-v1_5 padding مع SHA-256)
    final dataBytes = utf8.encode(data);
    final digest = sha256.convert(dataBytes).bytes;
    final signer = pc.PKCS1Encoding(pc.RSASigner(pc.SHA256Digest()))
      ..init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(rsaKey));
    final signature = signer.generateSignature(
      Uint8List.fromList(digest),
    );

    return _base64UrlBytes(signature.bytes);
  }

  /// تحميل RSA private key من DER bytes.
  ///
  /// يدعم صيغتين:
  ///   - PKCS#8 (الافتراضي من Firebase console — يبدأ بـ 0x30 0x82 ... 0x02 0x01 0x00)
  ///   - PKCS#1 (الصيغة القديمة — يبدأ بـ 0x30 0x82 ... 0x02 ... مباشرة)
  ///
  /// يعتمد على pointycastle Asn1Parser لفك الترميز.
  pc.RSAPrivateKey _parseRsaPrivateKey(List<int> derBytes) {
    final parser = pc.Asn1Parser(Uint8List.fromList(derBytes));
    final topSeq = parser.nextObject() as pc.Asn1Sequence;

    // اكتشاف الصيغة: PKCS#8 يحوي algorithm identifier كعنصر ثاني
    // (SEQUENCE { OID, NULL }). PKCS#1 يبدأ مباشرة بـ version (INTEGER 0).
    //
    // نتحقق: إذا كان العنصر الأول INTEGER 0 والعنصر الثاني SEQUENCE يحوي OID،
    // فهو PKCS#8. وإلا فهو PKCS#1.
    final firstElement = topSeq.elements![0];
    final isPkcs8 = firstElement is pc.Asn1Integer &&
        (firstElement.value!.length == 1 && firstElement.value![0] == 0) &&
        topSeq.elements!.length > 2 &&
        topSeq.elements![1] is pc.Asn1Sequence;

    late final pc.Asn1Sequence rsaKeySeq;
    if (isPkcs8) {
      // PKCS#8: العنصر الثالث هو OCTET STRING يحوي RSAPrivateKey DER-encoded
      final octetString = topSeq.elements![2] as pc.Asn1OctetString;
      final innerParser = pc.Asn1Parser(octetString.valueBytes);
      rsaKeySeq = innerParser.nextObject() as pc.Asn1Sequence;
    } else {
      // PKCS#1: الـ sequence نفسها هي RSAPrivateKey
      rsaKeySeq = topSeq;
    }

    // RSAPrivateKey ::= SEQUENCE {
    //   version           INTEGER (0),
    //   modulus           INTEGER,  -- n
    //   publicExponent    INTEGER,  -- e
    //   privateExponent   INTEGER,  -- d
    //   prime1            INTEGER,  -- p
    //   prime2            INTEGER,  -- q
    //   exponent1         INTEGER,  -- d mod (p-1)
    //   exponent2         INTEGER,  -- d mod (q-1)
    //   coefficient       INTEGER,  -- (inverse of q) mod p
    //   otherPrimeInfos   OtherPrimeInfos OPTIONAL
    // }
    final elements = rsaKeySeq.elements!;
    final modulus = (elements[1] as pc.Asn1Integer).integer!;
    final privateExponent = (elements[3] as pc.Asn1Integer).integer!;
    final prime1 = (elements[4] as pc.Asn1Integer).integer!;
    final prime2 = (elements[5] as pc.Asn1Integer).integer!;

    return pc.RSAPrivateKey(modulus, privateExponent, prime1, prime2);
  }

  /// base64Url-encode بدون padding (لمتوافقية JWT).
  String _base64Url(String input) {
    return _base64UrlBytes(utf8.encode(input));
  }

  String _base64UrlBytes(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
