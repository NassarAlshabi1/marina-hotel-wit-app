// ═══════════════════════════════════════════════════════════════
//  worker_endpoints.dart — سجل نقاط نهاية Worker مع تبديل تلقائي
//  ✅ (2026-09-09) طلب المستخدم: «دعم عدّة عناوين Worker مع تبديل
//  تلقائي (workers.dev + نطاق مخصّص) — يضع المستخدم نطاقه فيعمل
//  التطبيق عبره تلقائياً».
// ═══════════════════════════════════════════════════════════════
//
//  السياق الهندسي: شبكات اليمن تحجب *.workers.dev (فلترة SNI/IP/DNS).
//  لا يوجد إصلاح برمجي بحت يتجاوز حجب SNI بثبات — الحل الصحيح نطاق
//  مخصّص مربوط بنفس الـ Worker (SNI مسموح). هذا السجل يدير المرشحين:
//
//    1. النطاق المخصّص (يضبطه المستخدم من إعدادات المزامنة) — أولوية
//       دائمة ما دام موجوداً: وجوده بحد ذاته إشارة أن المدمج محجوب.
//    2. النطاق المدمج workers.dev (--dart-define CLOUDFLARE_WORKER_URL).
//
//  ويثبّت آخر نقطة نجحت (sticky) محفوظة في SharedPreferences — كل
//  URL لاحق يُبنى مباشرة على الفائز دون دفع كلفة تجريب كل طلب. الفشل
//  يُنزّل الفائز مؤقتاً ويمرّر الطلب للمرشح التالي (يُنفَّذ الفعلي
//  داخل ResilientHttpClient عبر endpointPlanner — نجاح/فشل يرجع هنا
//  عبر reportSuccess/reportFailure).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import '../utils/env.dart';

class WorkerEndpoints {
  WorkerEndpoints._();

  /// مفتاح النطاق المخصّص في SharedPreferences.
  static const String customUrlKey = 'cf_custom_worker_url';

  /// مفتاح آخر نقطة نهاية نجحت (sticky) — يُستعاد عند الإطلاق.
  static const String activeUrlKey = 'cf_worker_active_url';

  static String? _customUrl;
  static String? _activeOverride;

  /// ✅ (2026-09-28) تجاوز مرشّح الجسر للاختبارات فقط: null = اتبع
  /// [Env.cloudflareRelayUrl] (سلوك الإنتاج)، '' = معطّل (عقود
  /// المرشحَين القديمة في الاختبارات)، غير فارغ = قاعدة اختبار محددة.
  static String? _relayOverride;
  static bool _loaded = false;
  static SharedPreferences? _prefsRef;

  /// النقطة المدمجة من بيئة البناء (workers.dev).
  static String get builtin => Env.cloudflareWorkerUrl;

  /// ✅ (2026-09-28) جسر pages.dev المجاني — نطاق مختلف كلياً في SNI
  /// ينهي على نفس حافة Cloudflare ويعيد التوجيه نحو الـ Worker من
  /// داخل شبكة Cloudflare (حل حجب *.workers.dev في اليمن دون شراء
  /// دومين؛ مُثبت تشغيلياً: /health 200 + WebSocket عبره). مرشّح
  /// دائم بين المخصّص والمدمج.
  static String get relay => _relayOverride ?? Env.cloudflareRelayUrl;

  /// هل مرشّح الجسر مفعّل؟ (القيمة الفارغة تعطّله، والتطابق مع المدمج
  /// يعالجه إزالة التكرار في المرشحين تلقائياً).
  static bool get hasRelay => relay.isNotEmpty;

  /// هل حُمّل السجل من التفضيلات؟ (يستدعى من main مبكراً).
  static bool get isLoaded => _loaded;

  /// النطاق المخصّص الحالي (null = غير مضبوط).
  static String? get custom => _customUrl;
  static bool get hasCustom => _customUrl != null;

  /// تطبيع إدخال المستخدم: «mydomain.com» أو «https://mydomain.com/»
  /// أو مع منفذ — يعيد URL نظيفاً https://host[:port] بلا مسار/استعلام.
  /// يعيد null عند إدخال فارغ، ويرمي [FormatException] عند إدخال فاسد.
  /// عامة عمداً — تستخدمها شاشة الإعدادات للتحقق قبل الفحص.
  static String? normalizeCustomUrl(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    var text = trimmed;
    if (!text.contains('://')) text = 'https://$text';
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      throw FormatException('رابط غير صالح: $trimmed');
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty || host.contains(' ') || !host.contains('.')) {
      throw FormatException('اسم نطاق غير صالح: $trimmed');
    }
    if (uri.scheme != 'https') {
      throw FormatException('يجب أن يكون الرابط https: $trimmed');
    }
    if (uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery) {
      throw FormatException('أدخل النطاق الجذر فقط بدون مسار: $trimmed');
    }
    return uri.port == 443 || uri.port == 0
        ? 'https://$host'
        : 'https://$host:${uri.port}';
  }

  /// تحميل الحالة المحفوظة — يستدعى مرة واحدة مبكراً في main().
  /// fail-open: أي فشل يعني الاستمرار بالنطاق المدمج.
  static Future<void> load({SharedPreferences? prefs}) async {
    try {
      final sp = prefs ?? await SharedPreferences.getInstance();
      _prefsRef = sp;
      _customUrl = _sanitize(sp.getString(customUrlKey));
      _activeOverride = _sanitize(sp.getString(activeUrlKey));
      // نطاق مخصّص موجود = إشارة أن المدمج غير موثوق (سبب وضعه أصلاً).
      // ابدأ الجلسة عليه؛ الفشل يصحّح التثبيت تلقائياً عبر التدوير،
      // والنجاح على المدمج يعيده sticky خلال الجلسة.
      if (_customUrl != null && _activeOverride == builtin) {
        _activeOverride = _customUrl;
      } else if (_customUrl == null && hasRelay && _activeOverride == builtin) {
        // ✅ (2026-09-29) C4: ترقية تركيبات ما قبل الجسر — sticky قديم
        // على workers.dev (حُفظ قبل وجود الجسر) كان يُبقي الجلسة الأولى
        // بعد التحديث على النطاق المحجوب فتدخل مسار المهلات كاملاً قبل
        // أي تدوير. نبدأ على الجسر بنفس منطق المخصّص أعلاه: في الذاكرة
        // فقط — النجاح وحده ما يُحفظ، والفشل يدوّر للمدمج تلقائياً.
        _activeOverride = relay;
      }
    } catch (e) {
      dwarn(() => 'WorkerEndpoints.load failed (fail-open to builtin): $e');
      _activeOverride = null;
    } finally {
      _loaded = true;
    }
  }

  /// العنوان الفعّال الذي تُبنى عليه كل روابط الـ Worker.
  /// قبل التحميل يعيد المدمج (سلوك مطابق للسابق — لا كسر للاختبارات).
  /// بلا sticky: أول مرشح مسجّل (المخصّص ← الجسر ← المدمج) — أول نجاح
  /// يبني sticky بعدها (تثبيت الجسر على التركيبات الجديدة في اليمن).
  static String get active {
    if (!_loaded) return builtin;
    final sticky = _sanitize(_activeOverride);
    if (sticky != null && _isRegisteredBase(sticky)) return sticky;
    final bases = _orderedBases;
    return bases.isNotEmpty ? bases.first : builtin;
  }

  /// هل [uri] يشير إلى إحدى نقاط الـ worker المسجلة؟
  static bool isWorkerEndpoint(Uri uri) {
    final key = _hostKey(uri);
    for (final base in _orderedBases) {
      final u = Uri.tryParse(base);
      if (u != null && _hostKey(u) == key) return true;
    }
    return false;
  }

  /// مرشحو نقاط النهاية لطلب نحو [requestUrl]:
  /// - طلب خارج عائلة نقاط الـ worker (api.cloudflare.com مثلًا) →
  ///   قائمة وحيدة = العنوان نفسه (لا تدوير — عزل كامل).
  /// - طلب worker → قاعدة العنوان الحالي أولاً ثم بقية المرشحين
  ///   بترتيب [custom ثم builtin] بعد إزالة التكرار.
  static List<Uri> candidatesFor(Uri requestUrl) {
    if (!isWorkerEndpoint(requestUrl)) {
      return <Uri>[requestUrl];
    }
    final result = <Uri>[];
    void add(String base) {
      final u = Uri.tryParse(base);
      if (u == null) return;
      final key = _hostKey(u);
      if (result.any((r) => _hostKey(r) == key)) return;
      result.add(u);
    }

    // العنوان الذي بُني عليه الطلب أولاً (محاولة صفر كلفة إعادة كتابة).
    add(requestUrl.toString());
    _orderedBases.forEach(add);
    return result;
  }

  /// نجاح طلب على [base] — يثبّته للطلبات اللاحقة (ويعاد استعادته
  /// عند الإطلاق القادم). الحفظ fire-and-forget — لا يعطّل مسار الطلب.
  static void reportSuccess(Uri base) {
    final normalized = _sanitize(_toBaseUrl(base));
    if (normalized == null) return;
    if (!_isRegisteredBase(normalized)) return;
    if (_sanitize(_activeOverride) == normalized) return;
    _activeOverride = normalized;
    dlog(() => '🔗 WorkerEndpoints: sticky endpoint → $normalized');
    final sp = _prefsRef;
    if (sp != null) {
      unawaited(
        sp.setString(activeUrlKey, normalized).catchError((Object _) => false),
      );
    }
  }

  /// فشل طلب على [base] — يُنزّله من الصدارة مؤقتاً (in-memory فقط:
  /// التحميل عند الإطلاق يفرض المخصّص أولاً عند وجوده، والنجاح وحده
  /// ما يُثبَّت — لن يعلق المستخدم على نقطة ميتة عبر جلسة كاملة).
  static void reportFailure(Uri base) {
    final normalized = _sanitize(_toBaseUrl(base));
    if (normalized == null) return;
    final bases = _orderedBases;
    final failedKey = _hostKey(Uri.parse(normalized));
    final idx = bases.indexWhere((b) {
      final u = Uri.tryParse(b);
      return u != null && _hostKey(u) == failedKey;
    });
    if (idx < 0) return;
    // الفعّال المحسوب (sticky خام أو أول مرشح مسجّل بلا sticky) هو
    // الوحيد الذي يُنزَّل — فشل مرشح غير فعّال لا يغيّر التثبيت.
    final effectiveActive =
        _sanitize(_activeOverride) ?? (bases.isNotEmpty ? bases.first : null);
    if (effectiveActive == null ||
        _hostKey(Uri.parse(effectiveActive)) != failedKey) {
      return;
    }
    _activeOverride = bases.length > 1 ? bases[(idx + 1) % bases.length] : null;
    if (_sanitize(_activeOverride) == normalized) _activeOverride = null;
    dwarn(() => '⚠️ WorkerEndpoints: demoted $normalized (failure)');
  }

  /// ضبط/مسح النطاق المخصّص من الإعدادات.
  /// يعيد الرابط المُطبَّع المحفوظ (null عند المسح).
  /// يرمي [FormatException] على إدخال فاسد (لا يلمس الحالة المحفوظة).
  static Future<String?> setCustomUrl(
    String? raw, {
    SharedPreferences? prefs,
  }) async {
    final normalized = normalizeCustomUrl(raw);
    final sp = prefs ?? _prefsRef ?? await SharedPreferences.getInstance();
    _prefsRef = sp;
    if (normalized == null) {
      await sp.setString(customUrlKey, '');
    } else {
      await sp.setString(customUrlKey, normalized);
    }
    _customUrl = normalized;
    // المخصّص الجديد يتقدم فوراً (المستخدم وضعه لسبب) — والمسح يعيد
    // للمدمج. يُحفظ sticky الجديد ليُستعاد عند الإطلاق القادم.
    _activeOverride = normalized ?? (hasRelay ? relay : builtin);
    await sp.setString(activeUrlKey, _activeOverride!);
    return normalized;
  }

  // ─── internals ───────────────────────────────────────────────

  /// المرشحون المسجلون بترتيب الأولوية: المخصّص ثم المدمج.
  static List<String> get _orderedBases => <String>[
    if (_customUrl != null) _customUrl!,
    if (hasRelay) relay,
    builtin,
  ];

  static bool _isRegisteredBase(String base) {
    for (final b in _orderedBases) {
      final u = Uri.tryParse(b);
      final bu = Uri.tryParse(base);
      if (u != null && bu != null && _hostKey(u) == _hostKey(bu)) return true;
    }
    return false;
  }

  static String? _sanitize(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return null;
    return trimmed;
  }

  /// قاعدة نقية scheme://host[:port] — تقص أي مسار/استعلام قد يحمله
  /// الـUri القادم من تقرير نجاح/فشل (المرشح الأول هو الطلب كاملاً).
  /// بدون هذا كان sticky قد يحمل مسار طلب عابر فيفسد بناء الروابط.
  static String _toBaseUrl(Uri u) {
    final port = u.port;
    final hasExplicitPort =
        port != 0 &&
        !((u.scheme == 'https' && port == 443) ||
            (u.scheme == 'http' && port == 80));
    return hasExplicitPort
        ? '${u.scheme}://${u.host.toLowerCase()}:$port'
        : '${u.scheme}://${u.host.toLowerCase()}';
  }

  /// هوية مضيف مستقرة: host:port مع افتراض المنفذ من المخطط.
  static String _hostKey(Uri u) {
    final port = u.port == 0 ? (u.scheme == 'https' ? 443 : 80) : u.port;
    return '${u.host.toLowerCase()}:$port';
  }

  /// Test-only: تفريغ الحالة الساكنة.
  @visibleForTesting
  static void resetForTests() {
    _customUrl = null;
    _activeOverride = null;
    _relayOverride = null;
    _loaded = false;
    _prefsRef = null;
  }

  /// Test-only: ضبط مرشّح الجسر (null = اتبع Env، '' = معطّل).
  @visibleForTesting
  static void setRelayForTests(String? url) => _relayOverride = url;
}
