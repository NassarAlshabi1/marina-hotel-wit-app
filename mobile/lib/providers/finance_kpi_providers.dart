/// Providers المالية العليا: نموذج التدفقات النقدية لـ13 أسبوعاً
/// ولوحة مؤشرات الأداء الأسبوعية.
///
/// مصدر الحقيقة: **Cloudflare D1 الحية** — النموذج يُحسب على الـWorker
/// (`worker/src/finance.ts`) ليكون موحداً عبر كل الأجهزة. عند تعذر
/// الوصول (لا توكن / شبكة ضعيفة / خطأ خادم) يسقط المزود تلقائياً إلى
/// المحركات المحلية في `lib/src/finance` على بيانات drift المتزامنة،
/// فتبقى الشاشات عاملة دون اتصال.
library;

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloudflare_finance_service.dart';
import '../services/local_db.dart' as db;
import '../src/finance/finance_models.dart';
import '../src/finance/forecast_engine.dart';
import '../src/finance/kpi_engine.dart';
import '../src/finance/payment_profile_analyzer.dart';
import 'cloudflare_providers.dart';
import 'repository_providers.dart';

// ── حفظ معاملات السيناريوهات ────────────────────────────────────────

const String _kScenarioPrefsKey = 'finance_scenario_params_v1';

/// وحدة تحكم معاملات السيناريوهات الثلاثة مع حفظ دائم.
class ScenarioSettingsController extends StateNotifier<List<ScenarioParams>> {
  ScenarioSettingsController() : super(ScenarioParams.defaults) {
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kScenarioPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final list = <ScenarioParams>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        list.add(
          ScenarioParams(
            key: m['key'] as String? ?? '',
            name: m['name'] as String? ?? '',
            revenueFactor:
                (m['revenueFactor'] as num?)?.toDouble() ?? 1.0,
            collectionFactor:
                (m['collectionFactor'] as num?)?.toDouble() ?? 1.0,
          ),
        );
      }
      // إبقاء الترتيب الافتراضي وضمان اكتمال السيناريوهات الثلاثة
      final merged = <ScenarioParams>[];
      for (final d in ScenarioParams.defaults) {
        final found = list.where((s) => s.key == d.key).firstOrNull;
        merged.add(found ?? d);
      }
      state = merged;
    } catch (_) {
      state = ScenarioParams.defaults;
    }
  }

  /// تحديث معاملات سيناريو واحد وحفظها.
  Future<void> update(ScenarioParams params) async {
    state = [
      for (final s in state)
        if (s.key == params.key) params else s,
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kScenarioPrefsKey,
        jsonEncode([
          for (final s in state)
            {
              'key': s.key,
              'name': s.name,
              'revenueFactor': s.revenueFactor,
              'collectionFactor': s.collectionFactor,
            },
        ]),
      );
    } catch (_) {
      // الحفظ الدائم غير حرج — القيم الحية تعمل
    }
  }

  /// استعادة الافتراضي.
  Future<void> reset() async {
    state = ScenarioParams.defaults;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kScenarioPrefsKey);
    } catch (_) {}
  }
}

final scenarioSettingsProvider =
    StateNotifierProvider<ScenarioSettingsController, List<ScenarioParams>>(
  (ref) => ScenarioSettingsController(),
);

// ── عميل التمويل السحابي ────────────────────────────────────────────

/// عميل نقاط /api/finance/* — يقرأ توكن الـWorker الحي وقت الإنشاء.
final cloudflareFinanceServiceProvider = Provider<CloudflareFinanceService>(
  (ref) {
    final manager = ref.watch(cloudflareSyncManagerProvider);
    return CloudflareFinanceService(token: manager.token);
  },
);

// ── لقطة البيانات المشتركة (المسار المحلي الاحتياطي) ────────────────

/// لقطة السجلات النشطة المطلوبة للمحركين (تُجلب مرة واحدة).
class FinanceDataBundle {
  const FinanceDataBundle({
    required this.bookings,
    required this.payments,
    required this.expenses,
    required this.employees,
    required this.cashTransactions,
    required this.totalRooms,
    required this.loadedAt,
  });

  /// الحجوزات غير المحذوفة (المحركات تُفلتر الملغاة داخلياً).
  final List<db.Booking> bookings;
  final List<db.Payment> payments;
  final List<db.Expense> expenses;
  final List<db.Employee> employees;
  final List<db.CashTransaction> cashTransactions;
  final int totalRooms;
  final DateTime loadedAt;
}

final financeDataBundleProvider = FutureProvider<FinanceDataBundle>((ref) async {
  final database = ref.read(databaseProvider);

  final rooms = await database.select(database.rooms).get();
  final bookings = await (database.select(database.bookings)
        ..where((b) => b.deletedAt.isNull()))
      .get();
  final payments = await (database.select(database.payments)
        ..where((p) => p.deletedAt.isNull() & p.isVoided.equals(false)))
      .get();
  final expenses = await (database.select(database.expenses)
        ..where((e) => e.deletedAt.isNull()))
      .get();
  final employees = await database.select(database.employees).get();
  final cash = await (database.select(database.cashTransactions)
        ..where((t) => t.deletedAt.isNull()))
      .get();

  return FinanceDataBundle(
    bookings: bookings,
    payments: payments,
    expenses: expenses,
    employees: employees,
    cashTransactions: cash,
    totalRooms: rooms.length,
    loadedAt: DateTime.now(),
  );
});

// ── ملف التحصيل (وسائل الدفع + الإشغال التاريخي) ─────────────────────

final paymentProfileProvider = FutureProvider<PaymentProfile>((ref) async {
  final bundle = await ref.watch(financeDataBundleProvider.future);
  return const PaymentProfileAnalyzer().analyze(
    payments: bundle.payments,
    bookings: bundle.bookings,
    totalRooms: bundle.totalRooms,
  );
});

// ── مصدر الحساب (للعرض الشفاف في الواجهة) ───────────────────────────

/// مصدر آخر حساب للنموذج لكل سيناريو: d1 (خادمي) أو local (احتياطي).
final forecastSourceProvider =
    Provider.family<FinanceComputeSource?, String>((ref, scenarioKey) {
  // يعاد تقييمه عند كل تغير لحالة مزود النموذج (تحميل/نجاح/فشل)
  ref.watch(forecastResultProvider(scenarioKey));
  return _forecastSources[scenarioKey];
});

final _forecastSources = <String, FinanceComputeSource>{};

// ── نموذج الـ13 أسبوعاً (حسب السيناريو) ──────────────────────────────

/// توقع التدفقات لسيناريو بمفتاحه (base / conservative / stress).
///
/// يُحسب على الـWorker من D1 الحية أولاً؛ وعند الفشل يعاد الحساب
/// محلياً بنفس المنطق من بيانات drift المتزامنة.
final forecastResultProvider =
    FutureProvider.family<ForecastResult, String>((ref, scenarioKey) async {
  final scenarios = ref.watch(scenarioSettingsProvider);
  final scenario = scenarios
          .where((s) => s.key == scenarioKey)
          .firstOrNull ??
      ScenarioParams.defaults.first;

  // 1) الخادم أولاً — مصدر الحقيقة الموحد عبر الأجهزة
  if (ref.read(cloudflareSyncManagerProvider).token != null) {
    try {
      final service = ref.read(cloudflareFinanceServiceProvider);
      final result = await service
          .fetchForecast(
            scenarioKey: scenario.key,
            revenueFactor: scenario.revenueFactor,
            collectionFactor: scenario.collectionFactor,
          )
          .timeout(const Duration(seconds: 25));
      _forecastSources[scenarioKey] = FinanceComputeSource.d1;
      return result;
    } catch (_) {
      // سقوط مقصود إلى الحساب المحلي
    }
  }

  // 2) الاحتياطي المحلي (بدون اتصال)
  final bundle = await ref.watch(financeDataBundleProvider.future);
  final profile = await ref.watch(paymentProfileProvider.future);

  final result = const ForecastEngine().build(
    bookings: bundle.bookings,
    payments: bundle.payments,
    expenses: bundle.expenses,
    employees: bundle.employees,
    totalRooms: bundle.totalRooms,
    scenario: scenario,
    profile: profile,
  );
  _forecastSources[scenarioKey] = FinanceComputeSource.local;
  return result;
});

// ── لوحة المؤشرات الأسبوعية ─────────────────────────────────────────

final kpiSnapshotProvider = FutureProvider<KpiSnapshot>((ref) async {
  // 1) الخادم أولاً — يحسب النسبة المؤكدة داخلياً من السيناريو الأساسي
  if (ref.read(cloudflareSyncManagerProvider).token != null) {
    try {
      final service = ref.read(cloudflareFinanceServiceProvider);
      final snapshot =
          await service.fetchKpi().timeout(const Duration(seconds: 25));
      return snapshot;
    } catch (_) {
      // سقوط مقصود إلى الحساب المحلي
    }
  }

  // 2) الاحتياطي المحلي
  final bundle = await ref.watch(financeDataBundleProvider.future);

  // نسبة التدفق المؤكد من الأسبوع الأول للسيناريو الأساسي
  double? confirmedRatio;
  try {
    final base = await ref.watch(forecastResultProvider('base').future);
    if (base.weeks.isNotEmpty) {
      confirmedRatio = base.weeks.first.inflow.confirmedRatio;
    }
  } catch (_) {
    confirmedRatio = null;
  }

  return const KpiEngine().compute(
    bookings: bundle.bookings,
    payments: bundle.payments,
    expenses: bundle.expenses,
    cashTransactions: bundle.cashTransactions,
    totalRooms: bundle.totalRooms,
    forecastWeek1ConfirmedRatio: confirmedRatio,
  );
});

// ── اللقطات الأسبوعية المعتمدة + الفعلي مقابل المتوقع ────────────────

/// قائمة النسخ الأسبوعية المعتمدة (تحتاج manager/admin على الخادم).
final financeSnapshotsProvider =
    FutureProvider<List<FinanceSnapshotMeta>>((ref) async {
  final service = ref.read(cloudflareFinanceServiceProvider);
  return service
      .fetchSnapshots()
      .timeout(const Duration(seconds: 25));
});

/// تقرير الانحراف لنسخة معتمدة بمعرّفها (عتبات 5% / 10%).
final financeVarianceProvider =
    FutureProvider.family<FinanceVarianceReport, int>((ref, snapshotId) async {
  final service = ref.read(cloudflareFinanceServiceProvider);
  return service
      .fetchVariance(snapshotId)
      .timeout(const Duration(seconds: 25));
});
