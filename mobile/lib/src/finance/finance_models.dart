/// نماذج محرك التدفقات النقدية ومؤشرات الأداء المالي — فندق مارينا.
///
/// هذا الملف يحتوي نماذج البيانات البحتة (بدون اعتماديات Flutter) لطبقة
/// `lib/src/finance`:
/// - مستويات الإنذار (أخضر/أصفر/أحمر) ودرجات يقين التدفق.
/// - ملف وسائل الدفع المستخرج من التاريخ الفعلي (نسبة + أيام تأخر).
/// - معاملات السيناريوهات (أساسي / متحفظ / ضغط).
/// - توقع الأسبوع الواحد ونتيجة نموذج الـ13 أسبوعاً.
/// - صفوف لوحة المؤشرات الأسبوعية.
library;

// ── مستويات الإنذار ─────────────────────────────────────────────────

/// مستوى حالة المؤشر وفق نظام الألوان المعتمد.
enum AlertLevel {
  /// أخضر — الوضع المستقر.
  good,

  /// أصفر — يرقب ولا يستدعي إجراء فورياً.
  warning,

  /// أحمر — يتطلب إجراء تصحيحياً.
  danger,

  /// غير محسوب (بيانات ناقصة).
  unknown,
}

// ── درجات يقين التدفق ───────────────────────────────────────────────

/// تصنيف التدفقات حسب درجة اليقين (مؤكد / مرجح / تقديري).
enum FlowCertainty {
  /// مؤكد: نزيل داخل الفندق أو حجز مدفوع جزئياً — بقايا مستحقة شبه مؤكدة.
  confirmed,

  /// مرجّح: حجز مستقبلي مؤكد لم يُدفع منه شيء بعد.
  probable,

  /// تقديري: ليالي غير محجوزة تُتوقع وفق الإشغال التاريخي.
  estimated,
}

// ── ملف وسائل الدفع ─────────────────────────────────────────────────

/// توزيع وسيلة دفع واحدة كما ظهرت في التاريخ الفعلي.
class PaymentMethodProfile {
  const PaymentMethodProfile({
    required this.method,
    required this.share,
    required this.lagDays,
    required this.sampleCount,
  });

  /// اسم الوسيلة كما هو مخزّن في `payments.payment_method`.
  final String method;

  /// حصة الوسيلة من إجمالي المبالغ (0.0 — 1.0).
  final double share;

  /// متوسط أيام التأخر بين تاريخ الإقامة (الدخول) وتاريخ دخول النقد.
  final int lagDays;

  /// عدد الدفعات التي بُني عليها التقدير.
  final int sampleCount;
}

/// ملف التحصيل المستخرج من سجل المدفوعات الفعلي.
class PaymentProfile {
  const PaymentProfile({
    required this.methods,
    required this.historicalOccupancy,
    required this.historicalAdr,
    required this.sampleDays,
  });

  /// وسائل الدفع مرتبة تنازلياً بالحصة.
  final List<PaymentMethodProfile> methods;

  /// الإشغال التاريخي (آخر 30 يوماً) — يغذي التدفق التقديري.
  final double historicalOccupancy;

  /// متوسط سعر الغرفة التاريخي (ADR) — يغذي التدفق التقديري.
  final double historicalAdr;

  /// عدد الأيام التي غطاها التحليل التاريخي.
  final int sampleDays;

  /// الوسيلة الافتراضية عند غياب البيانات (نقد فوري).
  static const PaymentProfile fallback = PaymentProfile(
    methods: [
      PaymentMethodProfile(
        method: 'نقدي',
        share: 1,
        lagDays: 0,
        sampleCount: 0,
      ),
    ],
    historicalOccupancy: 0.5,
    historicalAdr: 0,
    sampleDays: 0,
  );

  /// حصة وسيلة معينة، أو صفر إن لم تظهر في التاريخ.
  double shareFor(String method) {
    for (final m in methods) {
      if (m.method == method) return m.share;
    }
    return 0;
  }

  /// متوسط أيام التأخر الموزون بالنسب — للاستخدام في التفسير فقط.
  double get weightedLagDays {
    if (methods.isEmpty) return 0;
    var sum = 0.0;
    for (final m in methods) {
      sum += m.share * m.lagDays;
    }
    return sum;
  }
}

// ── السيناريوهات ────────────────────────────────────────────────────

/// معاملات سيناريو واحد قابلة للتعديل من واجهة الإعدادات.
class ScenarioParams {
  const ScenarioParams({
    required this.key,
    required this.name,
    required this.revenueFactor,
    required this.collectionFactor,
  });

  /// مفتاح الحفظ في الإعدادات: base / conservative / stress.
  final String key;

  /// الاسم المعروض: أساسي / متحفظ / ضغط.
  final String name;

  /// معامل الإيراد (ضرب التدفق الداخل الكلي).
  final double revenueFactor;

  /// معامل التحصيل (ضرب التدفق الداخل المرجّح والتقديري فقط؛
  /// المبالغ المستحقة على نزلاء داخل الفندق تبقى مؤكدة).
  final double collectionFactor;

  /// السيناريو الثلاثي الافتراضي (أساسي 100%، متحفظ 90/85، ضغط 80/70).
  static const List<ScenarioParams> defaults = [
    ScenarioParams(
      key: 'base',
      name: 'أساسي',
      revenueFactor: 1.0,
      collectionFactor: 1.0,
    ),
    ScenarioParams(
      key: 'conservative',
      name: 'متحفظ',
      revenueFactor: 0.90,
      collectionFactor: 0.85,
    ),
    ScenarioParams(
      key: 'stress',
      name: 'ضغط',
      revenueFactor: 0.80,
      collectionFactor: 0.70,
    ),
  ];

  ScenarioParams copyWith({double? revenueFactor, double? collectionFactor}) {
    return ScenarioParams(
      key: key,
      name: name,
      revenueFactor: revenueFactor ?? this.revenueFactor,
      collectionFactor: collectionFactor ?? this.collectionFactor,
    );
  }
}

// ── بنية الأسبوع ────────────────────────────────────────────────────

/// التدفق الداخل لأسبوع مفصولة بطبقات اليقين.
class WeeklyInflow {
  const WeeklyInflow({
    required this.confirmed,
    required this.probable,
    required this.estimated,
  });

  /// مؤكد: بقايا مستحقة على نزلاء حاليين أو حجوزات مدفوعة جزئياً.
  final double confirmed;

  /// مرجّح: بقايا حجوزات مستقبلية لم تُدفع بعد.
  final double probable;

  /// تقديري: إيراد ليالي غير محجوزة وفق الإشغال التاريخي.
  final double estimated;

  double get total => confirmed + probable + estimated;

  /// نسبة التدفق المؤكد من الإجمالي (هدفها أكثر من 80%).
  double get confirmedRatio =>
      total <= 0 ? 0 : (confirmed / total).clamp(0.0, 1.0);
}

/// التدفق الخارج لأسبوع مفصولة بفئات المصروفات.
class WeeklyOutflow {
  const WeeklyOutflow({
    required this.salaries,
    required this.diesel,
    required this.utilities,
    required this.maintenance,
    required this.other,
  });

  final double salaries;
  final double diesel;
  final double utilities;
  final double maintenance;
  final double other;

  double get total => salaries + diesel + utilities + maintenance + other;
}

/// توقع أسبوع واحد ضمن نموذج الـ13 أسبوعاً.
class WeeklyForecast {
  const WeeklyForecast({
    required this.index,
    required this.start,
    required this.end,
    required this.inflow,
    required this.outflow,
    required this.openingBalance,
    required this.closingBalance,
    required this.avgWeeklyOutflow,
    required this.liquidityThreshold,
  });

  /// ترتيب الأسبوع (1 — 13).
  final int index;

  /// بداية الأسبوع (خميس) شاملة.
  final DateTime start;

  /// نهاية الأسبوع (أربعاء) شاملة.
  final DateTime end;

  final WeeklyInflow inflow;
  final WeeklyOutflow outflow;

  /// رصيد بداية الأسبوع.
  final double openingBalance;

  /// رصيد نهاية الأسبوع = البداية + صافي التدفق.
  final double closingBalance;

  /// متوسط الخارج الأسبوعي (أساس أسابيع التغطية والحد الأدنى).
  final double avgWeeklyOutflow;

  /// حد السيولة الأدنى = متوسط الخارج × أسابيع التغطية المستهدفة.
  final double liquidityThreshold;

  double get netFlow => inflow.total - outflow.total;

  /// الفائض عن الحد الأدنى (سالب = عجز).
  double get surplusOverThreshold => closingBalance - liquidityThreshold;

  /// أسابيع التغطية = الرصيد ÷ متوسط الخارج الأسبوعي.
  double get coverageWeeks =>
      avgWeeklyOutflow <= 0 ? 99 : (closingBalance / avgWeeklyOutflow);

  /// احتياج التمويل لهذا الأسبوع إن كان الرصيد تحت الحد الأدنى.
  double get financingNeed =>
      surplusOverThreshold < 0 ? -surplusOverThreshold : 0;

  AlertLevel get status {
    if (closingBalance < 0 || surplusOverThreshold < 0) return AlertLevel.danger;
    if (coverageWeeks < 4) return AlertLevel.warning;
    return AlertLevel.good;
  }
}

/// نتيجة نموذج الـ13 أسبوعاً كاملة لسيناريو واحد.
class ForecastResult {
  const ForecastResult({
    required this.scenario,
    required this.start,
    required this.openingBalance,
    required this.avgWeeklyOutflow,
    required this.liquidityThreshold,
    required this.coverageTargetWeeks,
    required this.weeks,
    required this.paymentProfile,
    required this.generatedAt,
  });

  final ScenarioParams scenario;
  final DateTime start;
  final double openingBalance;
  final double avgWeeklyOutflow;
  final double liquidityThreshold;

  /// أسابيع التغطية المستهدفة المستخدمة في حساب الحد الأدنى (افتراضي 4).
  final int coverageTargetWeeks;

  final List<WeeklyForecast> weeks;
  final PaymentProfile paymentProfile;
  final DateTime generatedAt;

  /// أكبر عجز تحت الحد الأدنى عبر الأسابيع — التمويل المطلوب.
  double get financingNeed {
    var worst = 0.0;
    for (final w in weeks) {
      if (w.financingNeed > worst) worst = w.financingNeed;
    }
    return worst;
  }

  /// الأسبوع الأكثر ضعفاً (أدنى رصيد ختامي).
  WeeklyForecast? get worstWeek {
    if (weeks.isEmpty) return null;
    WeeklyForecast worst = weeks.first;
    for (final w in weeks) {
      if (w.closingBalance < worst.closingBalance) worst = w;
    }
    return worst;
  }

  /// إجمالي الداخل المتوقع للفترة.
  double get totalInflow {
    var sum = 0.0;
    for (final w in weeks) {
      sum += w.inflow.total;
    }
    return sum;
  }

  /// إجمالي الخارج المتوقع للفترة.
  double get totalOutflow {
    var sum = 0.0;
    for (final w in weeks) {
      sum += w.outflow.total;
    }
    return sum;
  }

  /// عدد الأسابيع التي يقف فيها الرصيد تحت الحد الأدنى.
  int get weeksBelowThreshold =>
      weeks.where((w) => w.surplusOverThreshold < 0).length;
}

// ── لوحة المؤشرات ───────────────────────────────────────────────────

/// صف واحد في لوحة المؤشرات الأسبوعية.
class KpiEntry {
  const KpiEntry({
    required this.label,
    required this.hint,
    required this.currentText,
    required this.previousText,
    required this.targetText,
    this.status = AlertLevel.unknown,
  });

  /// اسم المؤشر (مثل: الإشغال، ADR...).
  final String label;

  /// المعادلة أو ملاحظة توضيحية قصيرة.
  final String hint;

  /// قيمة الأسبوع الحالي منسّقة نصياً.
  final String currentText;

  /// قيمة الأسبوع السابق منسّقة نصياً.
  final String previousText;

  /// الهدف الرقابي نصياً.
  final String targetText;

  final AlertLevel status;
}

/// لوحة المؤشرات الأسبوعية كاملة.
class KpiSnapshot {
  const KpiSnapshot({
    required this.rows,
    required this.generatedAt,
    required this.currentPeriodText,
    required this.previousPeriodText,
  });

  final List<KpiEntry> rows;
  final DateTime generatedAt;
  final String currentPeriodText;
  final String previousPeriodText;
}
