// ═══════════════════════════════════════════════════════════════
//  cloudflare_finance_service.dart — عميل نقاط /api/finance/*
//
//  يجلب النموذج المالي محسوباً على السيرفر من D1 الحية (مصدر حقيقة
//  واحد عبر الأجهزة): نموذج الـ13 أسبوعاً، لوحة المؤشرات، اللقطات
//  الأسبوعية المعتمدة، ومقارنة «الفعلي مقابل المتوقع».
//
//  الاستجابة تُحلّل إلى نفس نماذج `lib/src/finance` التي تستهلكها
//  الشاشات، فالتبديل بين حساب محلي (بدون اتصال) وحساب خادمي شفاف.
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../src/finance/finance_models.dart';
import 'cloudflare_config.dart';

// ── نماذج اللقطات والانحراف (خاصان بطبقة D1) ────────────────────────

/// لقطة أسبوعية معتمدة من نموذج التدفقات (ملخص بدون الأسابيع).
class FinanceSnapshotMeta {
  const FinanceSnapshotMeta({
    required this.id,
    required this.label,
    required this.scenarioKey,
    required this.modelStart,
    required this.modelEnd,
    required this.totalInflow,
    required this.totalOutflow,
    required this.financingNeed,
    required this.approvedBy,
    required this.approvedAt,
  });

  factory FinanceSnapshotMeta.fromJson(Map<String, dynamic> m) {
    return FinanceSnapshotMeta(
      id: (m['id'] as num?)?.toInt() ?? 0,
      label: m['label'] as String? ?? '',
      scenarioKey: m['scenario_key'] as String? ?? 'base',
      modelStart: m['model_start'] as String? ?? '',
      modelEnd: m['model_end'] as String? ?? '',
      totalInflow: (m['total_inflow'] as num?)?.toDouble() ?? 0,
      totalOutflow: (m['total_outflow'] as num?)?.toDouble() ?? 0,
      financingNeed: (m['financing_need'] as num?)?.toDouble() ?? 0,
      approvedBy: m['approved_by'] as String? ?? '',
      approvedAt: DateTime.tryParse(
            m['approved_at']?.toString() ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(
            (m['approved_at'] as num?)?.toInt() ?? 0,
          ),
    );
  }

  final int id;
  final String label;
  final String scenarioKey;
  final String modelStart;
  final String modelEnd;
  final double totalInflow;
  final double totalOutflow;
  final double financingNeed;
  final String approvedBy;
  final DateTime approvedAt;
}

/// مبالغ متوقعة/فعلية لأسبوع واحد في مقارنة الانحراف.
class FinanceVarianceAmounts {
  const FinanceVarianceAmounts({
    required this.inflow,
    required this.outflow,
    required this.netFlow,
  });

  final double inflow;
  final double outflow;
  final double netFlow;

  static FinanceVarianceAmounts? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    return FinanceVarianceAmounts(
      inflow: (m['inflow'] as num?)?.toDouble() ?? 0,
      outflow: (m['outflow'] as num?)?.toDouble() ?? 0,
      netFlow: (m['netFlow'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// أسبوع واحد في مقارنة «الفعلي مقابل المتوقع».
class FinanceVarianceWeek {
  const FinanceVarianceWeek({
    required this.index,
    required this.start,
    required this.end,
    required this.forecast,
    required this.actual,
    required this.status,
    this.varianceInflowPct,
    this.varianceOutflowPct,
    this.varianceNetPct,
  });

  factory FinanceVarianceWeek.fromJson(Map<String, dynamic> m) {
    final variance = Map<String, dynamic>.from(m['variancePct'] as Map? ?? {});
    return FinanceVarianceWeek(
      index: (m['index'] as num?)?.toInt() ?? 0,
      start: m['start'] as String? ?? '',
      end: m['end'] as String? ?? '',
      forecast:
          FinanceVarianceAmounts.fromJson(m['forecast']) ??
          const FinanceVarianceAmounts(inflow: 0, outflow: 0, netFlow: 0),
      actual: FinanceVarianceAmounts.fromJson(m['actual']),
      varianceInflowPct: (variance['inflow'] as num?)?.toDouble(),
      varianceOutflowPct: (variance['outflow'] as num?)?.toDouble(),
      varianceNetPct: (variance['netFlow'] as num?)?.toDouble(),
      status: m['status'] as String? ?? 'unknown',
    );
  }

  final int index;
  final String start;
  final String end;
  final FinanceVarianceAmounts forecast;
  final FinanceVarianceAmounts? actual;

  /// انحراف الداخل/الخارج/الصافي بالنسبة المئوية (null = لا مقارنة).
  final double? varianceInflowPct;
  final double? varianceOutflowPct;
  final double? varianceNetPct;

  /// green | yellow | red | unknown — عتبات 5% / 10%.
  final String status;
}

/// تقرير «الفعلي مقابل المتوقع» لنسخة أسبوعية معتمدة.
class FinanceVarianceReport {
  const FinanceVarianceReport({
    required this.snapshotId,
    required this.label,
    required this.approvedAt,
    required this.weeks,
  });

  factory FinanceVarianceReport.fromJson(Map<String, dynamic> m) {
    final rawWeeks = m['weeks'] as List? ?? [];
    return FinanceVarianceReport(
      snapshotId: (m['snapshotId'] as num?)?.toInt() ?? 0,
      label: m['label'] as String? ?? '',
      approvedAt: m['approvedAt'] as String? ?? '',
      weeks: [
        for (final w in rawWeeks)
          if (w is Map)
            FinanceVarianceWeek.fromJson(Map<String, dynamic>.from(w)),
      ],
    );
  }

  final int snapshotId;
  final String label;
  final String approvedAt;
  final List<FinanceVarianceWeek> weeks;
}

// ── الخدمة ──────────────────────────────────────────────────────────

/// عميل HTTP لنقاط التمويل على الـ Worker (D1 الحية).
class CloudflareFinanceService {
  CloudflareFinanceService({required String? token, http.Client? client})
      : _token = token,
        _client = client ?? http.Client();

  final String? _token;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 25);

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${CloudflareConfig.workerUrl}$path')
        .replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/json',
      };

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final resp = await _client.get(uri, headers: _headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw CloudflareFinanceException(
        'GET ${uri.path} → HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  // ── نموذج الـ13 أسبوعاً ────────────────────────────────────────────

  /// يجلب النموذج محسوباً على السيرفر من D1 الحية.
  ///
  /// [revenueFactor]/[collectionFactor] تُمرَّر معاملات السيناريو المحلية
  /// (تجربة ما-لو) — الخادم يبقى محسوباً بنفس المنطق الموحد.
  Future<ForecastResult> fetchForecast({
    required String scenarioKey,
    double? revenueFactor,
    double? collectionFactor,
    DateTime? start,
    int weeks = 13,
    int coverageTargetWeeks = 4,
  }) async {
    final query = <String, String>{
      'scenario': scenarioKey,
      if (revenueFactor != null) 'revenue': revenueFactor.toString(),
      if (collectionFactor != null) 'collection': collectionFactor.toString(),
      if (start != null)
        'start': start.toUtc().toIso8601String().substring(0, 10),
      'weeks': weeks.toString(),
      'coverage': coverageTargetWeeks.toString(),
    };
    final body = await _getJson(_uri('/api/finance/forecast', query));
    return _forecastFromJson(body);
  }

  // ── لوحة المؤشرات ─────────────────────────────────────────────────

  Future<KpiSnapshot> fetchKpi() async {
    final body = await _getJson(_uri('/api/finance/kpi'));
    return _kpiFromJson(body);
  }

  // ── اللقطات الأسبوعية ─────────────────────────────────────────────

  Future<List<FinanceSnapshotMeta>> fetchSnapshots({int limit = 26}) async {
    final body =
        await _getJson(_uri('/api/finance/snapshots', {'limit': '$limit'}));
    final raw = body['snapshots'] as List? ?? [];
    return [
      for (final s in raw)
        if (s is Map) FinanceSnapshotMeta.fromJson(Map<String, dynamic>.from(s)),
    ];
  }

  /// اعتماد نسخة أسبوعية جديدة (يتطلب دور manager أو admin على الخادم).
  Future<FinanceSnapshotMeta> approveSnapshot({
    String? label,
    String scenarioKey = 'base',
    DateTime? start,
    int weeks = 13,
    int coverageTargetWeeks = 4,
  }) async {
    final resp = await _client
        .post(
          _uri('/api/finance/snapshots'),
          headers: {
            ..._headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            if (label != null) 'label': label,
            'scenario': scenarioKey,
            if (start != null)
              'start': start.toUtc().toIso8601String().substring(0, 10),
            'weeks': weeks,
            'coverage': coverageTargetWeeks,
          }),
        )
        .timeout(_timeout);
    if (resp.statusCode != 201) {
      throw CloudflareFinanceException(
        'POST /api/finance/snapshots → HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final snap = body['snapshot'];
    if (snap is! Map) {
      throw const CloudflareFinanceException('snapshot missing in response');
    }
    return FinanceSnapshotMeta.fromJson(Map<String, dynamic>.from(snap));
  }

  // ── الفعلي مقابل المتوقع ──────────────────────────────────────────

  Future<FinanceVarianceReport> fetchVariance(int snapshotId) async {
    final body =
        await _getJson(_uri('/api/finance/variance', {'snapshot_id': '$snapshotId'}));
    return FinanceVarianceReport.fromJson(body);
  }

  // ── محللات الاستجابة (JSON → نماذج lib/src/finance) ──────────────

  static DateTime _parseDay(String? s) {
    final d = DateTime.tryParse(s ?? '');
    if (d != null) return d;
    return DateTime.utc(1970);
  }

  static PaymentProfile _profileFromJson(Map<String, dynamic> m) {
    final rawProfile = m['paymentProfile'];
    if (rawProfile is! Map) return PaymentProfile.fallback;
    final p = Map<String, dynamic>.from(rawProfile);
    final rawMethods = p['methods'] as List? ?? [];
    final methods = <PaymentMethodProfile>[
      for (final mm in rawMethods)
        if (mm is Map)
          () {
            final x = Map<String, dynamic>.from(mm);
            return PaymentMethodProfile(
              method: x['method'] as String? ?? 'غير محدد',
              share: (x['share'] as num?)?.toDouble() ?? 0,
              lagDays: (x['lagDays'] as num?)?.toInt() ?? 0,
              sampleCount: (x['sampleCount'] as num?)?.toInt() ?? 0,
            );
          }(),
    ];
    return PaymentProfile(
      methods: methods.isEmpty
          ? PaymentProfile.fallback.methods
          : methods,
      historicalOccupancy:
          (p['historicalOccupancy'] as num?)?.toDouble() ?? 0,
      historicalAdr: (p['historicalAdr'] as num?)?.toDouble() ?? 0,
      sampleDays: (p['sampleDays'] as num?)?.toInt() ?? 0,
    );
  }

  static ForecastResult _forecastFromJson(Map<String, dynamic> m) {
    final rawScenario = Map<String, dynamic>.from(m['scenario'] as Map? ?? {});
    final scenario = ScenarioParams(
      key: rawScenario['key'] as String? ?? 'base',
      name: rawScenario['name'] as String? ?? 'أساسي',
      revenueFactor: (rawScenario['revenueFactor'] as num?)?.toDouble() ?? 1,
      collectionFactor:
          (rawScenario['collectionFactor'] as num?)?.toDouble() ?? 1,
    );

    final rawWeeks = m['weeks'] as List? ?? [];
    final weeks = <WeeklyForecast>[];
    for (final rawW in rawWeeks) {
      if (rawW is! Map) continue;
      final w = Map<String, dynamic>.from(rawW);
      final inflow = Map<String, dynamic>.from(w['inflow'] as Map? ?? {});
      final outflow = Map<String, dynamic>.from(w['outflow'] as Map? ?? {});
      weeks.add(WeeklyForecast(
        index: (w['index'] as num?)?.toInt() ?? 0,
        start: _parseDay(w['start'] as String?),
        end: _parseDay(w['end'] as String?),
        inflow: WeeklyInflow(
          confirmed: (inflow['confirmed'] as num?)?.toDouble() ?? 0,
          probable: (inflow['probable'] as num?)?.toDouble() ?? 0,
          estimated: (inflow['estimated'] as num?)?.toDouble() ?? 0,
        ),
        outflow: WeeklyOutflow(
          salaries: (outflow['salaries'] as num?)?.toDouble() ?? 0,
          diesel: (outflow['diesel'] as num?)?.toDouble() ?? 0,
          utilities: (outflow['utilities'] as num?)?.toDouble() ?? 0,
          maintenance: (outflow['maintenance'] as num?)?.toDouble() ?? 0,
          other: (outflow['other'] as num?)?.toDouble() ?? 0,
        ),
        openingBalance: (w['openingBalance'] as num?)?.toDouble() ?? 0,
        closingBalance: (w['closingBalance'] as num?)?.toDouble() ?? 0,
        avgWeeklyOutflow: (w['avgWeeklyOutflow'] as num?)?.toDouble() ?? 0,
        liquidityThreshold:
            (w['liquidityThreshold'] as num?)?.toDouble() ?? 0,
      ));
    }

    return ForecastResult(
      scenario: scenario,
      start: _parseDay(m['start'] as String?),
      openingBalance: (m['openingBalance'] as num?)?.toDouble() ?? 0,
      avgWeeklyOutflow: (m['avgWeeklyOutflow'] as num?)?.toDouble() ?? 0,
      liquidityThreshold: (m['liquidityThreshold'] as num?)?.toDouble() ?? 0,
      coverageTargetWeeks:
          (m['coverageTargetWeeks'] as num?)?.toInt() ?? 4,
      weeks: weeks,
      paymentProfile: _profileFromJson(m),
      generatedAt: DateTime.tryParse(m['generatedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  static AlertLevel _alertFromText(String? s) {
    switch (s) {
      case 'good':
        return AlertLevel.good;
      case 'warning':
        return AlertLevel.warning;
      case 'danger':
        return AlertLevel.danger;
      default:
        return AlertLevel.unknown;
    }
  }

  static KpiSnapshot _kpiFromJson(Map<String, dynamic> m) {
    final rawRows = m['rows'] as List? ?? [];
    final rows = <KpiEntry>[
      for (final rawR in rawRows)
        if (rawR is Map)
          () {
            final r = Map<String, dynamic>.from(rawR);
            return KpiEntry(
              label: r['label'] as String? ?? '',
              hint: r['hint'] as String? ?? '',
              currentText: r['currentText'] as String? ?? '',
              previousText: r['previousText'] as String? ?? '',
              targetText: r['targetText'] as String? ?? '',
              status: _alertFromText(r['status'] as String?),
            );
          }(),
    ];
    return KpiSnapshot(
      rows: rows,
      generatedAt: DateTime.tryParse(m['generatedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      currentPeriodText: m['currentPeriodText'] as String? ?? '',
      previousPeriodText: m['previousPeriodText'] as String? ?? '',
    );
  }
}

/// خطأ نقاط التمويل — يحمل حالة HTTP إن وُجدت.
class CloudflareFinanceException implements Exception {
  const CloudflareFinanceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'CloudflareFinanceException: $message';

  /// 403 = الدور لا يسمح (staff مع اللقطات/المقارنة).
  bool get isForbidden => statusCode == 403;
}

/// تغليف ناتج حساب التمويل مع مصدره — للعرض الشفاف في الواجهة.
enum FinanceComputeSource { d1, local }

class FinanceComputation<T> {
  const FinanceComputation({required this.value, required this.source});

  final T value;
  final FinanceComputeSource source;
}

@visibleForTesting
ForecastResult forecastFromWorkerJsonForTests(Map<String, dynamic> m) =>
    CloudflareFinanceService._forecastFromJson(m);

@visibleForTesting
KpiSnapshot kpiFromWorkerJsonForTests(Map<String, dynamic> m) =>
    CloudflareFinanceService._kpiFromJson(m);
