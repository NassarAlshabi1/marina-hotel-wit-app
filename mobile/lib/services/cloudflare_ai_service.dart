import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../utils/env.dart';
import 'cloudflare_config.dart';
import 'cloudflare_sync_manager.dart';

class CloudflareAiResult {
  const CloudflareAiResult({
    required this.answer,
    this.plan,
    this.rows = const [],
    this.requiresConfirmation = false,
  });
  final String answer;
  final Map<String, dynamic>? plan;
  final List<Map<String, dynamic>> rows;
  final bool requiresConfirmation;
}

/// مساعد الفندق عبر Cloudflare Workers AI (‎/api/ai/query‎).
///
/// ✅ (2026-09-20) طلب المستخدم: «توكن ai worker اضفة الى ai» —
/// كانت الخدمة تقرأ توكن التخزين الآمن القديم 'auth_token' حصراً، وهو
/// مفتاح لا يكتبه إلا دخول PHP API القديم (ApiService.login). دخول
/// Cloudflare الحقيقي (‎/api/auth/login‎) يُخزَّن توكنه في مدير المزامنة
/// وEnv فقط — فكان طلب AI يخرج بلا Authorization صالحة فيرجع الـ Worker
/// بـ 401 وتتعطل المحادثة. الآن توكن الـ Worker الحي يُرفَق بالطلب.
class CloudflareAiService {
  CloudflareAiService._();
  static final instance = CloudflareAiService._();

  static const _storage = FlutterSecureStorage();

  /// مفتاح التوكن القديم في التخزين الآمن (PHP API) — احتياط أخير فقط:
  /// توكن PHP لن تُقبله بوابة الـ Worker لكن إرساله لا يضر (401 كما كان).
  @visibleForTesting
  static const String legacyTokenStorageKey = 'auth_token';

  /// ✅ (2026-09-20) حقن للاختبارات: عميل HTTP بديل (MockClient) يفحص
  /// الترويسات بلا شبكة حقيقية — نفس نمط connection_status_d1_test.
  /// null = المسار الإنتاجي (http.post لكل طلب كما كان).
  @visibleForTesting
  static http.Client? debugHttpClient;

  /// ✅ (2026-09-20) حقن مصدر التوكن للاختبارات. null = المصدر الإنتاجي.
  @visibleForTesting
  static Future<String?> Function()? debugTokenResolver;

  /// ✅ (2026-09-20) توكن الـ Worker الحي بتسلسل أولوية:
  /// 1. مدير المزامنة (دخول ‎/api/auth/login‎ حي — الدور admin افتراضياً
  ///    فيجتاز بوابة صلاحية AI للكتابة)
  /// 2. [Env.cloudflareAuthToken] (النسخة المرآتية التي يضبطها المدير)
  /// 3. لا شيء هنا — التخزين الآمن القديم احتياط داخل
  ///    [_productionTokenResolver] فقط (يحتاج await).
  @visibleForTesting
  static String? resolveWorkerToken({
    String? managerToken,
    String? envToken,
  }) {
    final live = (managerToken ?? CloudflareSyncManager.instance.token)?.trim();
    if (live != null && live.isNotEmpty) return live;
    final mirrored = (envToken ?? Env.cloudflareAuthToken)?.trim();
    if (mirrored != null && mirrored.isNotEmpty) return mirrored;
    return null;
  }

  Future<CloudflareAiResult> ask(String prompt) async {
    return _send({'prompt': prompt});
  }

  Future<CloudflareAiResult> confirm(Map<String, dynamic> plan) async {
    return _send({'plan': plan, 'confirm': true});
  }

  /// المصدر الإنتاجي للتوكن: الحي أولاً؛ فإن غاب (شاشة AI فُتحت قبل اكتمال
  /// دخول الإقلاع) يُشغَّل دخول كسول واحد محدود للمدير — idempotent لأن
  /// الإقلاع يستدعي initialize أصلاً — ثم يُعاد القراءة، وأخيراً التخزين
  /// الآمن القديم للتوافق الخلفي.
  static Future<String?> _productionTokenResolver() async {
    final live = resolveWorkerToken();
    if (live != null) return live;
    try {
      await CloudflareSyncManager.instance
          .initialize(loginAttempts: 1)
          .timeout(const Duration(seconds: 18));
    } catch (_) {
      // فشل الدخول الكسول (شبكة/قاعدة) — نكمل بالاحتياط الأخير أدناه؛
      // الطلب نفسه سيظهر خطأ الـ 401/الشبكة في المحادثة كما ينبغي.
    }
    final afterLogin = resolveWorkerToken();
    if (afterLogin != null) return afterLogin;
    try {
      final stored = await _storage.read(key: legacyTokenStorageKey);
      final trimmed = stored?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    } catch (_) {
      // قراءة التخزين الآمن فشلت (بيئة بلا Keystore) — بلا توكن.
    }
    return null;
  }

  Future<CloudflareAiResult> _send(Map<String, dynamic> body) async {
    final token = await (debugTokenResolver ?? _productionTokenResolver)();
    final response = await _post(
      Uri.parse('${CloudflareConfig.workerUrl}/api/ai/query'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: body,
    ).timeout(const Duration(seconds: 45));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('استجابة غير صالحة من Cloudflare');
    }
    if (response.statusCode >= 400) {
      throw Exception(decoded['error']?.toString() ?? 'فشل الطلب');
    }
    return CloudflareAiResult(
      answer: decoded['answer']?.toString() ?? 'تم استلام الطلب.',
      plan: decoded['plan'] is Map
          ? Map<String, dynamic>.from(decoded['plan'] as Map)
          : null,
      requiresConfirmation: decoded['requires_confirmation'] == true,
      rows: decoded['rows'] is List
          ? (decoded['rows'] as List).whereType<Map<String, dynamic>>().toList()
          : const [],
    );
  }

  /// إرسال POST عبر العميل المحقون في الاختبارات، أو http.post المباشر
  /// في الإنتاج (سلوك ما قبل التعديل حرفياً).
  Future<http.Response> _post(
    Uri url, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) {
    final injected = debugHttpClient;
    if (injected != null) {
      return injected.post(url, headers: headers, body: jsonEncode(body));
    }
    return http.post(url, headers: headers, body: jsonEncode(body));
  }
}
