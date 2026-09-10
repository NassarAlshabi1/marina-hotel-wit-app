// ═══════════════════════════════════════════════════════════════
//  cloudflare_auth_service.dart — مصادقة المستخدم ضد Cloudflare Worker
//  ✅ (2026-09-10) طلب المستخدم: «شاشة تسجيل الدخول إلى Cloudflare
//  واجعلها متصلة» — شاشة الدخول كانت تتحقق محلياً فقط
//  (AuthLocalStore.validateCredentials) ولا تستدعي POST /api/auth/login
//  إطلاقاً. هذه الخدمة تربط الشاشة بالـ Worker: تحقق سحابي حقيقي
//  يعيد JWT يُخزَّن للجلسة، مع سقوط آمن للمصادقة المحلية (offline-first).
// ═══════════════════════════════════════════════════════════════
//
//  ملاحظة معمارية: JWT الناتج هنا خاص **بجلسة المستخدم** ويُخزَّن عبر
//  [AuthLocalStore.saveAuthToken]. أما token المزامنة (CloudflareSyncManager)
//  فيُصدر بحسابات البناء الثابتة (Env) ويبقى منفصلاً عمداً — فصل الجلسة
//  عن المزامنة يمنع انقطاع المزامنة عند تغيير كلمة مرور مستخدم.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/app_logger.dart';
import '../utils/debug_log.dart';
import 'cloudflare_config.dart';
import 'resilient_http_client.dart';

/// نتيجة محاولة الدخول السحابي — حالات صريحة بدل استثناءات.
enum CloudflareAuthStatus {
  /// نجاح — token وبيانات المستخدم متوفرة.
  success,

  /// الخادم رفض بيانات الاعتماد (401) — لا سقوط محلي صامت هنا؛
  /// المتصل (auth_provider) يقرر: غالباً يجرّب المصادقة المحلية
  /// لتغطية الحسابات الثابتة (admin) التي قد لا توجد في جدول users.
  invalidCredentials,

  /// حجب مؤقت لمحاولات كثيرة (429) — مع ثوانٍ الانتظار.
  rateLimited,

  /// الشبكة/النطاق غير متاح (DNS، مهلة، socket) — سقوط للمحلي.
  networkError,

  /// خطأ خادمي (5xx / رد غير متوقع).
  serverError,
}

class CloudflareAuthResult {
  const CloudflareAuthResult({
    required this.status,
    this.token,
    this.userId,
    this.username,
    this.role,
    this.retryAfterSeconds,
    this.detail,
  });

  final CloudflareAuthStatus status;
  final String? token;
  final String? userId;
  final String? username;
  final String? role;
  final int? retryAfterSeconds;
  final String? detail;

  bool get isSuccess => status == CloudflareAuthStatus.success;

  /// رسالة عربية جاهزة للعرض في شاشة الدخول.
  String get userMessage {
    switch (status) {
      case CloudflareAuthStatus.success:
        return 'تم تسجيل الدخول بنجاح';
      case CloudflareAuthStatus.invalidCredentials:
        return 'اسم المستخدم أو كلمة المرور غير صحيحة';
      case CloudflareAuthStatus.rateLimited:
        final s = retryAfterSeconds ?? 0;
        return s > 0
            ? 'محاولات كثيرة — أعد المحاولة بعد $s ثانية'
            : 'محاولات كثيرة — أعد المحاولة بعد قليل';
      case CloudflareAuthStatus.networkError:
        return 'لا يمكن الوصول إلى خادم Cloudflare — تحقق من اتصالك بالإنترنت';
      case CloudflareAuthStatus.serverError:
        return 'خطأ في الخادم — أعد المحاولة لاحقاً';
    }
  }
}

class CloudflareAuthService {
  CloudflareAuthService({
    http.Client? client,
    String Function()? baseUrlResolver,
  }) : _ownsClient = client == null,
       _client = client ?? ResilientHttpClient(timeout: _loginTimeout),
       _baseUrlResolver = baseUrlResolver;

  static const Duration _loginTimeout = Duration(seconds: 12);
  static const Duration _healthTimeout = Duration(seconds: 6);

  final http.Client _client;
  final bool _ownsClient;

  /// مصدر عنوان الـ Worker — افتراضياً [CloudflareConfig.workerUrl]
  /// (نقاط نهاية مرنة مع تبديل تلقائي). قابل للحقن في الاختبارات.
  final String Function()? _baseUrlResolver;

  String get _base {
    final resolver = _baseUrlResolver;
    if (resolver != null) return resolver();
    return CloudflareConfig.workerUrl;
  }

  /// محاولة دخول حقيقية ضد Worker (`POST /api/auth/login`).
  ///
  /// - يعيد [CloudflareAuthStatus.success] مع JWT عند نجاح التحقق في D1.
  /// - يعيد محاولتين للفشل الشبكي العابر (DNS/Socket) بنفس منطق
  ///   CloudflareSyncManager — لكن بلا انتظار طويل: الشاشة تفاعلية.
  /// - لا يرمي استثناءات أبداً — النتيجة صريحة النوع.
  Future<CloudflareAuthResult> login({
    required String username,
    required String password,
    String? deviceId,
  }) async {
    final base = _base;
    if (base.isEmpty) {
      // Worker غير مضبوط في هذه البنية — الشاشة ستعمل محلياً.
      return const CloudflareAuthResult(
        status: CloudflareAuthStatus.networkError,
        detail: 'CLOUDFLARE_WORKER_URL is not configured',
      );
    }

    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _client
            .post(
              Uri.parse('$base/api/auth/login'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(<String, String>{
                'username': username,
                'password': password,
                if (deviceId != null && deviceId.isNotEmpty)
                  'device_id': deviceId,
              }),
            )
            .timeout(_loginTimeout);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final user = data['user'] as Map<String, dynamic>?;
          return CloudflareAuthResult(
            status: CloudflareAuthStatus.success,
            token: data['token'] as String?,
            userId: user?['id']?.toString(),
            username: user?['username']?.toString() ?? username,
            role: user?['role']?.toString(),
          );
        }

        if (response.statusCode == 401) {
          return const CloudflareAuthResult(
            status: CloudflareAuthStatus.invalidCredentials,
          );
        }

        if (response.statusCode == 429) {
          int? retryAfter;
          try {
            final body = jsonDecode(response.body) as Map<String, dynamic>;
            // ✅ worker (2026-09-10) يرسل retry_after_sec صريحاً بالثواني؛
            // retry_after القديم كان epoch-millis (resetAt) — نميّز
            // بالعتبة (يوم بالثواني) ونطبّع إلى ثوانٍ متبقية.
            final sec = (body['retry_after_sec'] as num?)?.toInt();
            retryAfter =
                sec ??
                _normalizeRetryAfter(
                  (body['retry_after'] as num?)?.toInt(),
                );
          } catch (_) {
            // الجسم قد لا يكون JSON — الترويسة القياسية بديل.
            retryAfter = null;
          }
          retryAfter =
              retryAfter ?? int.tryParse(response.headers['retry-after'] ?? '');
          return CloudflareAuthResult(
            status: CloudflareAuthStatus.rateLimited,
            retryAfterSeconds: retryAfter,
          );
        }

        // 4xx آخر أو 5xx — خطأ خادمي/طلب من وجهة نظر الشاشة.
        return CloudflareAuthResult(
          status: response.statusCode >= 500
              ? CloudflareAuthStatus.serverError
              : CloudflareAuthStatus.invalidCredentials,
          detail: 'HTTP ${response.statusCode}: ${_shortBody(response.body)}',
        );
      } catch (e, st) {
        final transient = _isTransient(e.toString());
        if (transient && attempt < maxAttempts) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        dwarn(() => 'CloudflareAuthService.login error: $e');
        AppLogger.warning(
          'فشل الوصول إلى Worker عند تسجيل الدخول: $e',
          tag: 'CF-AUTH',
          error: e,
          stackTrace: st,
        );
        return CloudflareAuthResult(
          status: CloudflareAuthStatus.networkError,
          detail: e.toString(),
        );
      }
    }
    // غير قابل للوصول نظرياً (الحلقة تعيد دائماً).
    return const CloudflareAuthResult(
      status: CloudflareAuthStatus.networkError,
      detail: 'unreachable',
    );
  }

  /// فحص توفر الـ Worker (`GET /api/health`) — لمؤشر الاتصال في الشاشة.
  /// يعيد false عند غياب الضبط أو أي فشل شبكي — لا استثناءات.
  Future<bool> checkHealth() async {
    final base = _base;
    if (base.isEmpty) return false;
    try {
      final response = await _client
          .get(Uri.parse('$base/api/health'))
          .timeout(_healthTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// لا يوجد endpoint خروج في الـ Worker (JWT عديم الحالة) — الإبطال
  /// محلي فقط: حذف الـ token المحفوظ.
  void dispose() {
    if (_ownsClient) _client.close();
  }

  static String _shortBody(String body) {
    final trimmed = body.trim();
    if (trimmed.length <= 160) return trimmed;
    return '${trimmed.substring(0, 160)}…';
  }

  /// تطبيع retry_after القادم من الـ worker: ثوانٍ صريحة (≤ يوم) كما
  /// هي؛ epoch-millis (قيمة resetAt القديمة) تُحوَّل إلى ثوانٍ متبقية
  /// من الآن. قيمة منتهية تعيد 0.
  static int? _normalizeRetryAfter(int? raw) {
    if (raw == null) return null;
    const daySeconds = 86400;
    if (raw <= daySeconds) return raw;
    final remainSec = ((raw - DateTime.now().millisecondsSinceEpoch) / 1000)
        .ceil();
    return remainSec > 0 ? remainSec : 0;
  }

  /// نفس عائلة الأخطاء العابرة التي يعالجها CloudflareSyncManager —
  /// تستحق إعادة محاولة قبل إعلان انقطاع الشبكة.
  static bool _isTransient(String err) {
    return err.contains('Failed host lookup') ||
        err.contains('No address associated with hostname') ||
        err.contains('SocketException') ||
        err.contains('Connection reset') ||
        err.contains('Connection closed') ||
        err.contains('HandshakeException') ||
        err.contains('TimeoutException');
  }
}
