// ═══════════════════════════════════════════════════════════════
//  cloudflare_dual_run_service.dart — Dual-Run kill switch + shadow
//  comparison (خطة الانتقال — المرحلتان 6 و5.3)
//
//  المرحلة 6 (Dual-Run):
//    - التطبيق يدفع ويقرأ من Cloudflare فقط.
//    - مفتاح إيقاف عن بُعد (Remote Config: cloudflare_sync_enabled)
//      يسمح بتعطيل المسار الجديد فوراً بلا نشر تحديث — خطة الرجوع
//      (القسم 11.2): مفتاح=false → دقائق.
//    - قراءة ظل من Appwrite (قراءة-فقط): مقارنة عدّادات كل كيان بين
//      /api/stats (D1) وعدّاد Appwrite — تسجيل الفروق فقط، بلا أي
//      كتابة. صفر فروق يومياً = بوابة التبديل (المرحلة 7).
//
//  عزل الاعتماديات: هذا الملف لا يستورد appwrite_service ولا
//  cloudflare_sync_manager — التوصيل الحقيقي يُحقن من main.dart
//  عبر configure() (يمنع دورات الاستيراد ويجعل الاختبار ممكناً).
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import 'cloudflare_config.dart';
import 'remote_config_service.dart';

/// نتيجة مقارنة كيان واحد بين الغازيتين.
@visibleForTesting
class ShadowEntityComparison {
  const ShadowEntityComparison({
    required this.entity,
    required this.cloudflareCount,
    required this.appwriteCount,
  });

  final String entity;
  final int cloudflareCount;
  final int appwriteCount;

  bool get matches => cloudflareCount == appwriteCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'entity': entity,
    'cloudflare': cloudflareCount,
    'appwrite': appwriteCount,
    'match': matches,
  };
}

/// ملخص جولة المقارنة الظلّية.
@visibleForTesting
class ShadowComparisonResult {
  const ShadowComparisonResult({
    required this.comparisons,
    required this.completedAt,
    this.error,
  });

  final List<ShadowEntityComparison> comparisons;
  final DateTime completedAt;

  /// خطأ جولة كاملة (مثل فشل /api/stats) — الفروق الجزئية تُسجّل
  /// داخل القائمة نفسها ككيانات بقيم -1.
  final String? error;

  /// الفروق الحقيقية فقط — القياسات الغائبة (-1) لا تُحتسب عدم
  /// تطابق (تعذّر القياس ≠ اختلاف بيانات).
  int get mismatchCount => comparisons
      .where(
        (c) => c.cloudflareCount >= 0 && c.appwriteCount >= 0 && !c.matches,
      )
      .length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'completed_at': completedAt.toIso8601String(),
    'error': error,
    'mismatches': mismatchCount,
    'comparisons': comparisons.map((c) => c.toJson()).toList(),
  };
}

class CloudflareDualRunService {
  factory CloudflareDualRunService() => _instance;
  CloudflareDualRunService._internal();
  static final CloudflareDualRunService _instance =
      CloudflareDualRunService._internal();

  static const String _kLastComparisonKey = 'cloudflare_shadow_last_compare';

  // ─── حقن التوصيل (من main.dart) ──────────────────────────────
  Future<String?> Function()? _tokenProvider;

  /// عدّاد كيان واحد من Appwrite (قراءة ظل) — يُحقن من main لأنه
  /// يحتاج AppwriteService (تجنّب دورة استيراد هنا).
  /// عوّد -1 إذا تعذّر العدّ.
  Future<int> Function(String entity)? _appwriteCounter;

  /// جالب /api/stats الخام — قابل للحقن للاختبار.
  @visibleForTesting
  Future<Map<String, dynamic>?> Function()? statsFetcherForTest;

  void configure({
    required Future<String?> Function() tokenProvider,
    required Future<int> Function(String entity) appwriteCounter,
  }) {
    _tokenProvider = tokenProvider;
    _appwriteCounter = appwriteCounter;
  }

  // ─── المرحلة 6: مفتاح الإيقاف عن بُعد ────────────────────────

  /// true = مسار Cloudflare مفعّل (الافتراضي).
  /// مصادر القيمة بالترتيب: تجاوز محلي يدوي (تشغيليات) ← Remote Config
  /// ← true.
  Future<bool> isCloudflareSyncEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // تجاوز محلي موثّق (يستخدمه التشغيل لإيقاف محلي بلا Firebase)
      if (prefs.containsKey('cloudflare_sync_local_override')) {
        return prefs.getBool('cloudflare_sync_local_override') ?? true;
      }
    } catch (_) {
      // prefs غير متاحة — نكمل بالقيمة البعيدة
    }
    // RemoteConfigService يعمل بالقيم الافتراضية حتى بلا Firebase
    // (initialize() آمن للفشل ويضبط defaults) — لكن إن لم يُهيّأ
    // بعد نُبقي المسار مفعّلاً (لا نُعطّل مزامنة لإخفاق قياس).
    try {
      final rc = RemoteConfigService();
      if (rc.isInitialized) return rc.cloudflareSyncEnabled;
    } catch (_) {}
    return true;
  }

  /// تجاوز محلي يدوي (null = إزالة التجاوز والعودة للتحكم البعيد).
  Future<void> setLocalOverride(bool? enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled == null) {
      await prefs.remove('cloudflare_sync_local_override');
    } else {
      await prefs.setBool('cloudflare_sync_local_override', enabled);
    }
  }

  // ─── المرحلة 5.3/6: المقارنة الظلّية ─────────────────────────

  /// مقارنة عدّادات كل الكيانات: D1 (/api/stats) مقابل Appwrite
  /// (قراءة-فقط). لا كتابة على أي مصدر — تسجيل فروق فقط.
  Future<ShadowComparisonResult> runShadowComparison() async {
    final comparisons = <ShadowEntityComparison>[];

    // 1) عدّادات D1 من مسار واحد (/api/stats — مصدر واحد للحقيقة)
    Map<String, dynamic>? stats;
    String? error;
    try {
      stats = await _fetchWorkerStats();
    } catch (e) {
      error = 'stats fetch failed: $e';
      dwarn(() => 'shadow: $error');
    }

    final entities = CloudflareConfig.entityToTable.keys.toList()..sort();
    for (final entity in entities) {
      final int cfCount = _countFromStats(stats, entity) ?? -1;
      var awCount = -1;
      try {
        awCount = await _appwriteCounter?.call(entity) ?? -1;
      } catch (e) {
        dwarn(() => 'shadow: appwrite count failed for $entity: $e');
      }
      // -1 (تعذّر القياس) لا يُحتسب عدم تطابق — يُسجّل كما هو
      comparisons.add(
        ShadowEntityComparison(
          entity: entity,
          cloudflareCount: cfCount,
          appwriteCount: awCount,
        ),
      );
      if (awCount >= 0 && cfCount >= 0 && cfCount != awCount) {
        dwarn(
          () =>
              '⚠️ shadow MISMATCH $entity: cloudflare=$cfCount '
              'appwrite=$awCount',
        );
      }
    }

    final result = ShadowComparisonResult(
      comparisons: comparisons,
      completedAt: DateTime.now(),
      error: error,
    );

    // 2) تثبيت آخر نتيجة للفحص من الإعدادات/التشخيص
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kLastComparisonKey,
        jsonEncode(result.toJson()),
      );
    } catch (_) {}

    debugPrint(
      '📊 Shadow comparison: ${comparisons.length} entities, '
      '${result.mismatchCount} mismatches${error == null ? '' : ' (error: $error)'}',
    );
    return result;
  }

  /// آخر نتيجة مقارنة محفوظة (null إن لم تجري جولة بعد).
  Future<Map<String, dynamic>?> lastComparisonJson() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLastComparisonKey);
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  int? _countFromStats(
    Map<String, dynamic>? stats,
    String entity,
  ) {
    if (stats == null) return -1;
    // شكل استجابة /api/stats الموثق (index.ts:331):
    // { tables: {entity: count, ...}, rate_limit_entries, server_time }
    final body = stats['tables'] is Map<String, dynamic>
        ? stats['tables'] as Map<String, dynamic>
        : stats;
    final value = body[entity];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return -1;
  }

  Future<Map<String, dynamic>?> _fetchWorkerStats() async {
    // حقن الاختبار له الأولوية
    if (statsFetcherForTest != null) {
      return statsFetcherForTest!();
    }
    final token = await _tokenProvider?.call();
    if (token == null || token.isEmpty) {
      throw StateError('no cloudflare token for /api/stats');
    }
    final uri = Uri.parse(
      '${CloudflareConfig.workerUrl}/api/stats',
    );
    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('stats HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
