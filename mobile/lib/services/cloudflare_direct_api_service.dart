import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/app_logger.dart';
import 'cloudflare_d1_service.dart';

/// تسجيل الارتباط مع Cloudflare عبر **API المباشر** (api.cloudflare.com).
///
/// على عكس فحص `/health` الخاص بالـ Worker، هذه الخدمة تتصل مباشرةً بـ
/// `https://api.cloudflare.com/client/v4` بنفس أسلوب أمر curl المرجعي:
///
/// ```bash
/// curl "https://api.cloudflare.com/client/v4/user/tokens/verify" \
///   -H "Authorization: Bearer <TOKEN>"
/// ```
///
/// المسار الكامل للتسجيل (كله قراءة فقط — لا كتابة إطلاقاً):
///  1. `GET /user/tokens/verify` — التحقق من التوكن (توكنات المستخدم).
///  2. عند الفشل: `GET /accounts/{accountId}/tokens/verify` — توكنات
///     الحساب (Account Owned Tokens، بادئة `cfat_`) تُفحص عبر هذه النقطة
///     **فقط**؛ ومعرّف الحساب يُكتشف تلقائياً عبر `GET /accounts` إن لم
///     يكن محفوظاً (مؤكد تجريبياً أن توكنات cfat_ تستطيع سرد الحسابات).
///  3. `GET /accounts/{accountId}/d1/database` — إثبات وصول الحساب
///     والتأكد أن قاعدة D1 المحفوظة معرّفها موجود فعلاً (وإظهار اسمها).
///
/// ملاحظات مثبتة تجريبياً (مسبارات 2026-09):
/// - Cloudflare يرجّع HTTP 400/401 **مع جسم JSON** عند توكن غير صالح —
///   لذلك يُقرأ الجسم دائماً بغضّ النظر عن كود الحالة.
/// - السلسلة السداسية الطويلة (32 hex) هي **معرّف الحساب** وليست توكن؛
///   تمريرها كـ Bearer يُرجّع خطأ 6003/6111 «Invalid format for
///   Authorization header» — الخدمة تترجم هذا الخطأ إلى رسالة عربية واضحة.
/// - توكن `cfat_` **صالح ونشط** يفشل حتماً في `/user/tokens/verify`
///   برمز 1000 «Invalid API Token» رغم صحته — نقطة الحساب هي التي
///   تُرجّع 200 مع `status: active`. لذلك لا يجوز عرض خطأ `/user`
///   وحده على المستخدم عند فشل المسارين: نقطة الحساب هي مصدر الحقيقة.
class CloudflareDirectApiService {
  CloudflareDirectApiService(this._config, {http.Client? client})
    : _client = client ?? http.Client();

  static const String _baseUrl = 'https://api.cloudflare.com/client/v4';

  final CloudflareD1Config _config;
  final http.Client _client;

  // ذاكرة اكتشاف معرّف الحساب داخل نسخة الخدمة — يكفي نداء
  // GET /accounts واحد لكل عملية تسجيل كاملة (توكن ← حساب ← قاعدة).
  String? _discoveredAccountId;
  String? _discoveredAccountName;

  /// معرّف الحساب المكتشف تلقائياً خلال آخر فحص (null إن لم يحدث اكتشاف
  /// — أي أن المعرّف كان محفوظاً مسبقاً أو فشل الاكتشاف).
  String? get discoveredAccountId => _discoveredAccountId;

  /// اسم الحساب المكتشف تلقائياً (للعرض فقط).
  String? get discoveredAccountName => _discoveredAccountName;

  // ─── نقاط النهاية المباشرة ────────────────────────────────────

  /// تحويل آمن لنتيجة Cloudflare الخام إلى خريطة (قد تكون null/قائمة).
  static Map<String, dynamic>? _asMap(Object? raw) =>
      raw is Map<String, dynamic> ? raw : null;

  /// تنفيذ أمر التحقق المرجعي: `GET /user/tokens/verify`.
  ///
  /// يُرجّع نتيجة منظمة مهما كان كود HTTP — لأن Cloudflare يرفق جسم
  /// JSON واصفاً للخطأ حتى مع 400/401.
  Future<CloudflareTokenVerifyResult> verifyToken() async {
    final token = _config.apiToken.trim();
    if (token.isEmpty) {
      return const CloudflareTokenVerifyResult(
        ok: false,
        endpoint: null,
        status: null,
        errors: ['لا يوجد توكن محفوظ — أكمله من تبويب Cloudflare D1'],
      );
    }

    // 1) نقطة توكنات المستخدم — نفس أمر curl المرجعي حرفياً.
    final userAttempt = await _callApi('GET', '/user/tokens/verify');
    if (userAttempt.ok) {
      final userResult = _asMap(userAttempt.result);
      return CloudflareTokenVerifyResult(
        ok: userResult?['status'] == 'active',
        endpoint: '/user/tokens/verify',
        status: userResult?['status']?.toString(),
        expiresOn: userResult?['expires_on']?.toString(),
        tokenId: userResult?['id']?.toString(),
      );
    }

    // 2) توكنات الحساب (Account Owned Tokens) لا تُفحص عبر /user —
    //    نقطة الحساب هي البديل الصحيح، ومعرّف الحساب يُكتشف تلقائياً
    //    عبر GET /accounts إن لم يكن محفوظاً.
    final resolution = await _resolveAccountId();
    if (resolution.accountId != null) {
      final accountId = resolution.accountId!;
      final accountAttempt = await _callApi(
        'GET',
        '/accounts/$accountId/tokens/verify',
      );
      if (accountAttempt.ok) {
        final accountResult = _asMap(accountAttempt.result);
        return CloudflareTokenVerifyResult(
          ok: accountResult?['status'] == 'active',
          endpoint: '/accounts/$accountId/tokens/verify',
          status: accountResult?['status']?.toString(),
          expiresOn: accountResult?['expires_on']?.toString(),
          tokenId: accountResult?['id']?.toString(),
          discoveredAccountId: resolution.discovered
              ? resolution.accountId
              : null,
          discoveredAccountName: resolution.discovered
              ? resolution.accountName
              : null,
        );
      }

      // فشل نقطة الحساب — هذا هو الخطأ الحقيقي لتوكنات الحساب (فشل
      // /user برمز 1000 متوقع وليس هو السبب).
      return CloudflareTokenVerifyResult(
        ok: false,
        endpoint: '/accounts/$accountId/tokens/verify',
        status: null,
        errors: _translateErrors(
          accountAttempt.errors,
          accountAttempt.statusCode,
        ),
      );
    }

    // 3) تعذّر فحص نقطة الحساب (لم يُحفظ المعرّف ولم يُكتشف) — نعرض
    //    أخطاء الاكتشاف وأخطاء /user معاً لتشخيص صادق لا مضلل.
    return CloudflareTokenVerifyResult(
      ok: false,
      endpoint: null,
      status: null,
      errors: [
        ...resolution.errors,
        ..._translateErrors(userAttempt.errors, userAttempt.statusCode),
        if (token.startsWith('cfat_'))
          'التوكن من نوع توكنات الحساب (cfat_) ويُفحص عبر نقطة الحساب — أدخل معرّف الحساب من تبويب Cloudflare D1 أو امنح التوكن صلاحية قراءة الحساب',
      ],
    );
  }

  /// إثبات وصول الحساب: عرض قواعد D1 التابعة للحساب (قراءة فقط).
  ///
  /// يُرجّع قائمة القواعد واسم القاعدة المطابقة للمعرّف المحفوظ إن وُجدت.
  /// يعيد استخدام معرّف الحساب المكتشف تلقائياً في [verifyToken] إن حصل.
  Future<CloudflareAccountD1Result> listAccountD1Databases() async {
    final resolution = await _resolveAccountId();
    final accountId = resolution.accountId;
    if (accountId == null) {
      return CloudflareAccountD1Result(
        ok: false,
        databases: const [],
        errors: [
          ...resolution.errors,
          if (resolution.errors.isEmpty)
            'معرّف الحساب غير محفوظ ولم يتمكّن التوكن من اكتشافه',
        ],
      );
    }

    final attempt = await _callApi(
      'GET',
      '/accounts/$accountId/d1/database?per_page=50',
    );
    if (!attempt.ok) {
      return CloudflareAccountD1Result(
        ok: false,
        databases: const [],
        errors: _translateErrors(attempt.errors, attempt.statusCode),
      );
    }

    final result = attempt.result;
    final rows = (result is Map ? result['results'] : result) as List?;
    final databases = <CloudflareD1DatabaseInfo>[];
    for (final row in (rows ?? const [])) {
      if (row is Map) {
        databases.add(
          CloudflareD1DatabaseInfo(
            uuid: row['uuid']?.toString() ?? '',
            name: row['name']?.toString() ?? '',
            fileSize: (row['file_size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }

    final savedId = _config.databaseId.trim();
    String? matchedName;
    for (final db in databases) {
      if (savedId.isNotEmpty && db.uuid == savedId) {
        matchedName = db.name;
        break;
      }
    }

    return CloudflareAccountD1Result(
      ok: true,
      databases: databases,
      matchedDatabaseName: matchedName,
      matchedDatabaseFound: savedId.isNotEmpty && matchedName != null,
    );
  }

  /// التسجيل الكامل: توكن → حساب → قاعدة D1 (قراءة فقط بالكامل).
  ///
  /// لا يرمي استثناءات — كل فشل يُترجم إلى نتيجة منظمة برسائل عربية.
  Future<CloudflareDirectCheckResult> registerConnection() async {
    final sw = Stopwatch()..start();

    if (_config.apiToken.trim().isEmpty) {
      return CloudflareDirectCheckResult(
        ok: false,
        summary: const [
          'لا يوجد توكن محفوظ — أدخله من تبويب Cloudflare D1 ثم أعد المحاولة',
        ],
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    final verify = await verifyToken();
    if (!verify.ok) {
      return CloudflareDirectCheckResult(
        ok: false,
        verify: verify,
        summary: [
          'التوكن غير صالح أو منتهي — فحصنا ${verify.endpoint ?? '/user/tokens/verify'}',
          ...verify.errors,
          'أنشئ توكناً جديداً بصلاحية D1 Edit من لوحة Cloudflare (My Profile → API Tokens)',
        ],
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    final account = await listAccountD1Databases();
    if (!account.ok) {
      return CloudflareDirectCheckResult(
        ok: false,
        verify: verify,
        summary: [
          'التوكن صالح (${verify.status ?? 'active'}) لكن الوصول للحساب فشل',
          ...account.errors,
          'تأكد أن التوكن يملك صلاحية Account → D1 → Edit ومعرّف الحساب صحيح',
        ],
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    final summary = <String>[
      'التوكن نشط عبر ${verify.endpoint} ${verify.expiresOn == null ? '' : '(ينتهي: ${verify.expiresOn})'}',
      if (discoveredAccountId != null)
        'تم اكتشاف معرّف الحساب تلقائياً: $discoveredAccountId${discoveredAccountName == null ? '' : ' — $discoveredAccountName'}',
      'الحساب متاح — ${account.databases.length} قاعدة D1',
      if (account.matchedDatabaseFound)
        'قاعدة D1 المحفوظة موجودة: ${account.matchedDatabaseName}'
      else if (account.databases.isEmpty)
        'لا توجد قواعد D1 في هذا الحساب'
      else
        'معرّف القاعدة المحفوظ غير موجود ضمن قواعد الحساب — راجع تبويب Cloudflare D1',
    ];

    return CloudflareDirectCheckResult(
      ok: account.matchedDatabaseFound,
      verify: verify,
      account: account,
      summary: summary,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  // ─── طبقة HTTP المباشرة ───────────────────────────────────────

  /// تحديد معرّف الحساب المستخدم للفحص: المحفوظ أولاً، وعند غيابه
  /// اكتشاف تلقائي عبر `GET /accounts` (مؤكد تجريبياً أنه يعمل حتى مع
  /// توكنات الحساب cfat_). النتيجة تُحفظ في ذاكرة النسحة لتفادي تكرار
  /// النداء بين [verifyToken] و[listAccountD1Databases].
  Future<_AccountResolution> _resolveAccountId() async {
    final saved = _config.accountId.trim();
    if (saved.isNotEmpty) {
      return _AccountResolution(accountId: saved);
    }
    if (_discoveredAccountId != null) {
      return _AccountResolution(
        accountId: _discoveredAccountId,
        accountName: _discoveredAccountName,
        discovered: true,
      );
    }

    final attempt = await _callApi('GET', '/accounts?per_page=5');
    if (!attempt.ok) {
      return _AccountResolution(
        errors: _translateErrors(attempt.errors, attempt.statusCode),
      );
    }

    // مغلف Cloudflare القياسي يضع القائمة مباشرة في result.
    final rows = attempt.result is List
        ? attempt.result! as List
        : const <dynamic>[];
    for (final row in rows) {
      if (row is Map) {
        final id = row['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          _discoveredAccountId = id;
          _discoveredAccountName = row['name']?.toString();
          return _AccountResolution(
            accountId: id,
            accountName: _discoveredAccountName,
            discovered: true,
          );
        }
      }
    }
    return const _AccountResolution(
      errors: ['التوكن لا يملك أي حساب قابل للاكتشاف عبر GET /accounts'],
    );
  }

  Future<_CloudflareApiAttempt> _callApi(String method, String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      'Authorization': 'Bearer ${_config.apiToken.trim()}',
      'Content-Type': 'application/json',
    };

    try {
      final http.Response resp;
      if (method == 'GET') {
        resp = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
      } else {
        resp = await _client
            .post(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
      }

      Map<String, dynamic>? decoded;
      try {
        final dynamic raw = jsonDecode(utf8.decode(resp.bodyBytes));
        decoded = raw is Map<String, dynamic>
            ? raw
            : <String, dynamic>{};
      } catch (_) {
        return _CloudflareApiAttempt(
          ok: false,
          statusCode: resp.statusCode,
          errors: ['استجابة غير متوقعة من Cloudflare (HTTP ${resp.statusCode})'],
        );
      }

      final errors = <String>[];
      final rawErrors = decoded['errors'];
      if (rawErrors is List) {
        for (final e in rawErrors) {
          if (e is Map) {
            errors.add('${e['code']}: ${e['message']}');
          } else if (e != null) {
            errors.add(e.toString());
          }
        }
      }

      return _CloudflareApiAttempt(
        ok: decoded['success'] == true,
        statusCode: resp.statusCode,
        result: decoded['result'],
        errors: errors,
      );
    } on TimeoutException {
      return const _CloudflareApiAttempt(
        ok: false,
        statusCode: null,
        errors: ['انتهت مهلة الاتصال بـ api.cloudflare.com'],
      );
    } catch (e) {
      AppLogger.error(
        'فشل الاتصال المباشر بـ Cloudflare API',
        tag: 'CF-DIRECT',
        error: e,
      );
      return const _CloudflareApiAttempt(
        ok: false,
        statusCode: null,
        errors: ['تعذر الوصول إلى api.cloudflare.com — تحقق من الشبكة'],
      );
    }
  }

  /// ترجمة أخطاء Cloudflare الخام إلى رسائل عربية مفهومة.
  List<String> _translateErrors(List<String> raw, int? statusCode) {
    if (raw.isEmpty) {
      return ['فشل الطلب (HTTP ${statusCode ?? '؟'})'];
    }
    final translated = <String>[];
    for (final e in raw) {
      if (e.contains('6111') || e.contains('6003')) {
        translated.add(
          'صيغة التوكن غير صحيحة — هذه السلسلة معرّف حساب وليست توكن؛ '
          'انسخ التوكن من صفحة My Profile ← API Tokens في لوحة Cloudflare',
        );
      } else if (e.contains('1000')) {
        translated.add('التوكن غير صالح (ملغى أو محذوف أو منسوخ ناقصاً)');
      } else if (e.contains('9109') || e.contains('Unauthorized')) {
        translated.add('التوكن لا يملك صلاحية الوصول لهذا المورد');
      } else {
        translated.add(e);
      }
    }
    return translated;
  }
}

// ══════════════════════════════════════════════════════════════════
//  النماذج
// ══════════════════════════════════════════════════════════════════

/// نتيجة تحديد معرّف الحساب للفحص (محفوظ أو مكتشف تلقائياً أو فاشل).
class _AccountResolution {
  const _AccountResolution({
    this.accountId,
    this.accountName,
    this.errors = const [],
    this.discovered = false,
  });

  /// معرّف الحساب الجاهز للفحص — null إن فشل الحفظ والاكتشاف معاً.
  final String? accountId;
  final String? accountName;
  final List<String> errors;

  /// true إذا جاء المعرّف من اكتشاف تلقائي (وليس من الإعدادات المحفوظة)
  /// — يُستخدم لإظهار سطر «تم الاكتشاف تلقائياً» في الملخص.
  final bool discovered;
}

/// نتيجة نداء خام واحد ضد api.cloudflare.com.
class _CloudflareApiAttempt {
  const _CloudflareApiAttempt({
    required this.ok,
    required this.statusCode,
    this.result,
    this.errors = const [],
  });

  final bool ok;
  final int? statusCode;
  final Object? result;
  final List<String> errors;
}

/// نتيجة التحقق من التوكن عبر النقطة المباشرة.
class CloudflareTokenVerifyResult {
  const CloudflareTokenVerifyResult({
    required this.ok,
    required this.endpoint,
    required this.status,
    this.expiresOn,
    this.tokenId,
    this.discoveredAccountId,
    this.discoveredAccountName,
    this.errors = const [],
  });

  final bool ok;

  /// النقطة التي نجح الفحص عبرها (user أو account) — null عند الفشل الكلي.
  final String? endpoint;
  final String? status;
  final String? expiresOn;
  final String? tokenId;

  /// معرّف الحساب المكتشف تلقائياً أثناء هذا الفحص (null إن كان محفوظاً).
  final String? discoveredAccountId;

  /// اسم الحساب المكتشف تلقائياً (للعرض).
  final String? discoveredAccountName;
  final List<String> errors;
}

/// نتيجة قراءة قواعد D1 التابعة للحساب.
class CloudflareAccountD1Result {
  const CloudflareAccountD1Result({
    required this.ok,
    required this.databases,
    this.matchedDatabaseName,
    this.matchedDatabaseFound = false,
    this.errors = const [],
  });

  final bool ok;
  final List<CloudflareD1DatabaseInfo> databases;
  final String? matchedDatabaseName;
  final bool matchedDatabaseFound;
  final List<String> errors;
}

/// نتيجة تسجيل الارتباط الكامل (توكن + حساب + قاعدة).
class CloudflareDirectCheckResult {
  const CloudflareDirectCheckResult({
    required this.ok,
    required this.summary,
    this.verify,
    this.account,
    this.elapsedMs = 0,
  });

  /// نجاح كامل: توكن نشط + حساب متاح + القاعدة المحفوظة موجودة.
  final bool ok;
  final CloudflareTokenVerifyResult? verify;
  final CloudflareAccountD1Result? account;
  final List<String> summary;
  final int elapsedMs;
}
