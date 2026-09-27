/// محرك مؤشرات الأداء المالي الأسبوعية — فندق مارينا.
///
/// يحسب لوحة المؤشرات الكاملة (التشغيل / الإيراد / التكلفة / السيولة)
/// لآخر 7 أيام مقابل الأسبوع السابق، مع تصنيف حالة كل مؤشر بالألوان
/// (أخضر/أصفر/أحمر) وفق حدود الأهداف المعتمدة:
/// - نسبة التحصيل ≥ 95%، «أخرى» < 5%، أسابيع التغطية ≥ 4،
///   الرواتب/الإيرادات ≈ 11.8%، الديزل/الإيرادات ≈ 12.2%،
///   التدفق المؤكد > 80%، والفرق الصفري لفرقي الصندوق والإيرادات.
///
/// المصدر: قاعدة البيانات المحلية المتزامنة حياً من Appwrite.
library;

import 'package:intl/intl.dart';

import '../../services/local_db.dart' as db;
import 'finance_date_utils.dart';
import 'finance_models.dart';
import 'payment_profile_analyzer.dart';

class KpiEngine {
  const KpiEngine();

  static final NumberFormat _num = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _pct = NumberFormat('#,##0.0', 'en_US');

  /// يحسب لوحة المؤشرات. القوائم يجب أن تكون السجلات النشطة.
  KpiSnapshot compute({
    required List<db.Booking> bookings,
    required List<db.Payment> payments,
    required List<db.Expense> expenses,
    required List<db.CashTransaction> cashTransactions,
    required int totalRooms,
    DateTime? now,
    double? forecastWeek1ConfirmedRatio,
    int coverageTargetWeeks = 4,
  }) {
    final ref = now ?? DateTime.now();
    final today = dayStart(ref);
    final curStart = today.subtract(const Duration(days: 6));
    final prevStart = today.subtract(const Duration(days: 13));
    final prevEnd = curStart.subtract(const Duration(days: 1));

    final cur = _periodStats(
      bookings: bookings,
      payments: payments,
      expenses: expenses,
      cashTransactions: cashTransactions,
      totalRoomsArg: totalRooms,
      from: curStart,
      to: today,
    );
    final prev = _periodStats(
      bookings: bookings,
      payments: payments,
      expenses: expenses,
      cashTransactions: cashTransactions,
      totalRoomsArg: totalRooms,
      from: prevStart,
      to: prevEnd,
    );

    // الرصيد النقدي الحالي (كل التاريخ) — نفس منطق «الصندوق»
    var cashBalance = 0.0;
    for (final p in payments) {
      cashBalance += p.amount;
    }
    for (final e in expenses) {
      cashBalance -= e.amount;
    }

    // متوسط الخارج الأسبوعي (آخر 28 يوماً) — أساس التغطية والحد الأدنى
    var out28 = 0.0;
    final start28 = today.subtract(const Duration(days: 27));
    for (final e in expenses) {
      final d = tryParseDate(e.date);
      if (d != null && !d.isBefore(start28) && !d.isAfter(today)) {
        out28 += e.amount;
      }
    }
    final avgWeeklyOutflow = out28 / 4.0;
    final minLiquidity = avgWeeklyOutflow * coverageTargetWeeks;

    final rows = <KpiEntry>[
      // ── التشغيل ──────────────────────────────────────────────────
      _row(
        label: 'الإشغال',
        hint: 'الليالي المباعة ÷ الليالي المتاحة',
        current: '${_pct.format(cur.occupancy * 100)}%',
        previous: '${_pct.format(prev.occupancy * 100)}%',
        target: '≥ 60%',
        status: _bands(cur.occupancy * 100, 60, 40),
      ),
      _row(
        label: 'ADR (متوسط سعر الغرفة)',
        hint: 'إيراد الغرف ÷ الليالي المباعة',
        current: _num.format(cur.adr),
        previous: _num.format(prev.adr),
        target: 'ثبات أو ارتفاع',
        status: _trend(cur.adr, prev.adr, 0.90),
      ),
      _row(
        label: 'RevPAR',
        hint: 'إيراد الغرف ÷ الغرف المتاحة',
        current: _num.format(cur.revpar(totalRooms)),
        previous: _num.format(prev.revpar(totalRooms)),
        target: 'ثبات أو ارتفاع',
        status: _trend(cur.revpar(totalRooms), prev.revpar(totalRooms), 0.90),
      ),
      _row(
        label: 'إيراد الغرف',
        hint: 'مدفوعات revenueType = room',
        current: _num.format(cur.roomRevenue),
        previous: _num.format(prev.roomRevenue),
        target: 'ثبات أو ارتفاع',
        status: _trend(cur.roomRevenue, prev.roomRevenue, 0.90),
      ),

      // ── الإيراد والتحصيل ─────────────────────────────────────────
      _row(
        label: 'النقد المحصل',
        hint: 'إجمالي المدفوعات النشطة بالفترة',
        current: _num.format(cur.collected),
        previous: _num.format(prev.collected),
        target: 'ثبات أو ارتفاع',
        status: _trend(cur.collected, prev.collected, 0.90),
      ),
      _row(
        label: 'نسبة التحصيل',
        hint: 'المحصل ÷ المستحق للحجوزات المستحقة',
        current: '${_pct.format(cur.collectionRate * 100)}%',
        previous: '${_pct.format(prev.collectionRate * 100)}%',
        target: '≥ 95%',
        status: _bands(cur.collectionRate * 100, 95, 85),
      ),

      // ── التكلفة ──────────────────────────────────────────────────
      _row(
        label: 'إجمالي المصروفات',
        hint: 'مصروفات الفترة النشطة',
        current: _num.format(cur.expensesTotal),
        previous: _num.format(prev.expensesTotal),
        target: 'لا يرتفع أكثر من 10%',
        status: _inverseTrend(cur.expensesTotal, prev.expensesTotal, 1.10),
      ),
      _row(
        label: 'الرواتب ÷ الإيرادات',
        hint: 'تكلفة العمالة مقابل النقد المحصل',
        current: '${_pct.format(cur.salariesRatio * 100)}%',
        previous: '${_pct.format(prev.salariesRatio * 100)}%',
        target: '≤ 15% (مرجعي 11.8%)',
        status: _bands(cur.salariesRatio * 100, 15, 25, higherIsWorse: true),
      ),
      _row(
        label: 'الديزل ÷ الإيرادات',
        hint: 'كفاءة استهلاك الطاقة مقابل النقد المحصل',
        current: '${_pct.format(cur.dieselRatio * 100)}%',
        previous: '${_pct.format(prev.dieselRatio * 100)}%',
        target: '≤ 15% (مرجعي 12.2%)',
        status: _bands(cur.dieselRatio * 100, 15, 25, higherIsWorse: true),
      ),
      _row(
        label: '«أخرى» ÷ المصروفات',
        hint: 'مؤشر جودة التصنيف المحاسبي',
        current: '${_pct.format(cur.otherRatio * 100)}%',
        previous: '${_pct.format(prev.otherRatio * 100)}%',
        target: '< 5%',
        status: _bands(cur.otherRatio * 100, 5, 15, higherIsWorse: true),
      ),

      // ── السيولة ──────────────────────────────────────────────────
      _row(
        label: 'صافي التدفق الأسبوعي',
        hint: 'الداخل − الخارج',
        current: _num.format(cur.netFlow),
        previous: _num.format(prev.netFlow),
        target: 'موجب',
        status: cur.netFlow > 0
            ? AlertLevel.good
            : cur.netFlow == 0
                ? AlertLevel.warning
                : AlertLevel.danger,
      ),
      _row(
        label: 'الرصيد آخر الأسبوع',
        hint: 'رصيد الصندوق التراكمي',
        current: _num.format(cashBalance),
        previous: _num.format(cashBalance - prev.netFlow),
        target: 'فوق ${_num.format(minLiquidity)} (الحد الأدنى)',
        status: cashBalance >= minLiquidity
            ? AlertLevel.good
            : cashBalance >= 0
                ? AlertLevel.warning
                : AlertLevel.danger,
      ),
      _row(
        label: 'أسابيع التغطية',
        hint: 'الرصيد ÷ متوسط الخارج الأسبوعي',
        current:
            '${_pct.format(avgWeeklyOutflow <= 0 ? 99.0 : cashBalance / avgWeeklyOutflow)} أسبوع تقريباً',
        previous: '—',
        target: '≥ $coverageTargetWeeks أسابيع',
        status: _bands(
          avgWeeklyOutflow <= 0 ? 99 : cashBalance / avgWeeklyOutflow,
          coverageTargetWeeks.toDouble(),
          2,
        ),
      ),
      _row(
        label: 'فرق الصندوق',
        hint: 'حركات الصندوق − المدفوعات المسجلة (فحص تسجيل)',
        current: _num.format(cur.cashDiff),
        previous: _num.format(prev.cashDiff),
        target: 'صفر',
        status: _zeroTolerance(cur.cashDiff, cur.collected, 0.05),
      ),
      _row(
        label: 'فرق الإيرادات',
        hint: 'المستحق − المحصل (العربون المقدَّم قد يفسر الفرق)',
        current: _num.format(cur.revenueDiff),
        previous: _num.format(prev.revenueDiff),
        target: 'صفر أو مبرر',
        status: _zeroTolerance(
          cur.revenueDiff,
          cur.dueMatured > 0 ? cur.dueMatured : 1,
          0.10,
        ),
      ),
      _row(
        label: 'التدفق المؤكد ÷ الإجمالي',
        hint: 'جودة التوقع — الأسبوع الأول من نموذج الـ13 أسبوعاً',
        current: forecastWeek1ConfirmedRatio == null
            ? '—'
            : '${_pct.format(forecastWeek1ConfirmedRatio * 100)}%',
        previous: '—',
        target: '> 80%',
        status: forecastWeek1ConfirmedRatio == null
            ? AlertLevel.unknown
            : _bands(forecastWeek1ConfirmedRatio * 100, 80, 60),
      ),
    ];

    final fmt = (DateTime d) => '${d.day}/${d.month}';
    return KpiSnapshot(
      rows: rows,
      generatedAt: ref,
      currentPeriodText: '${fmt(curStart)} — ${fmt(today)}',
      previousPeriodText: '${fmt(prevStart)} — ${fmt(prevEnd)}',
    );
  }

  // ── إحصاءات فترة ───────────────────────────────────────────────────

  _PeriodStats _periodStats({
    required List<db.Booking> bookings,
    required List<db.Payment> payments,
    required List<db.Expense> expenses,
    required List<db.CashTransaction> cashTransactions,
    required int totalRoomsArg,
    required DateTime from,
    required DateTime to,
  }) {
    // الليالي المباعة: احتلال فعلي لكل يوم في الفترة
    var soldNights = 0;
    final activeBookings = bookings
        .where((b) => b.deletedAt == null && !_isCancelled(b.status))
        .toList();
    for (var d = 0; d <= daysBetween(from, to); d++) {
      final day = from.add(Duration(days: d));
      for (final b in activeBookings) {
        if (PaymentProfileAnalyzer.occupiesOnDay(b, day)) soldNights++;
      }
    }
    final daysCount = daysBetween(from, to) + 1;

    var collected = 0.0, roomRevenue = 0.0, cashIncome = 0.0;
    for (final p in payments) {
      final d = tryParseDate(p.paymentDate);
      if (d == null || d.isBefore(from) || d.isAfter(to)) continue;
      collected += p.amount;
      if (p.revenueType == 'room') roomRevenue += p.amount;
    }
    for (final t in cashTransactions) {
      if (t.transactionType == 'income') {
        final d = tryParseDate(t.transactionTime);
        if (d == null || d.isBefore(from) || d.isAfter(to)) continue;
        cashIncome += t.amount;
      }
    }

    var expensesTotal = 0.0, salaries = 0.0, diesel = 0.0, other = 0.0;
    for (final e in expenses) {
      final d = tryParseDate(e.date);
      if (d == null || d.isBefore(from) || d.isAfter(to)) continue;
      expensesTotal += e.amount;
      final t = e.expenseType.trim();
      if (t.contains('رواتب') || t.contains('راتب')) {
        salaries += e.amount;
      } else if (t.contains('ديزل')) {
        diesel += e.amount;
      } else if (t.contains('كهرباء') ||
          t.contains('مياه') ||
          t.contains('صيانة') ||
          t.contains('فاتورة')) {
        // فئات مصنفة — لا تدخل «أخرى»
      } else {
        other += e.amount;
      }
    }

    // المستحق: حجوزات انتهت إقامتها داخل الفترة (مستحقة التحصيل)
    var dueMatured = 0.0;
    for (final b in activeBookings) {
      final out = _effectiveCheckout(b);
      if (out == null) continue;
      if (!out.isBefore(from) && !out.isAfter(to)) {
        dueMatured += b.totalDueCached;
      }
    }

    return _PeriodStats(
      soldNights: soldNights,
      daysCount: daysCount,
      totalRooms: totalRoomsArg,
      collected: collected,
      roomRevenue: roomRevenue,
      cashIncome: cashIncome,
      expensesTotal: expensesTotal,
      salaries: salaries,
      diesel: diesel,
      other: other,
      dueMatured: dueMatured,
    );
  }

  static DateTime? _effectiveCheckout(db.Booking b) {
    final a = b.actualCheckout;
    if (a != null && a.trim().isNotEmpty) {
      final d = tryParseDate(a);
      if (d != null) return d;
    }
    final c = b.checkoutDate;
    if (c != null && c.trim().isNotEmpty) {
      final d = tryParseDate(c);
      if (d != null) return d;
    }
    final ci = tryParseDate(b.checkinDate);
    if (ci == null) return null;
    return ci.add(Duration(days: b.calculatedNights));
  }

  static bool _isCancelled(String status) {
    final s = status.trim().toLowerCase();
    return s == 'ملغي' || s == 'cancelled' || s == 'canceled';
  }

  // ── تصنيفات الحالة ─────────────────────────────────────────────────

  /// صف لوحة مؤشرات جاهز.
  static KpiEntry _row({
    required String label,
    required String hint,
    required String current,
    required String previous,
    required String target,
    required AlertLevel status,
  }) {
    return KpiEntry(
      label: label,
      hint: hint,
      currentText: current,
      previousText: previous,
      targetText: target,
      status: status,
    );
  }

  /// نطاقات مطلقة: [greenMax, yellowMax] — أو معكوسة للنسب السيئة.
  static AlertLevel _bands(
    double value,
    double greenMax,
    double yellowMax, {
    bool higherIsWorse = false,
  }) {
    if (higherIsWorse) {
      if (value <= greenMax) return AlertLevel.good;
      if (value <= yellowMax) return AlertLevel.warning;
      return AlertLevel.danger;
    }
    if (value >= greenMax) return AlertLevel.good;
    if (value >= yellowMax) return AlertLevel.warning;
    return AlertLevel.danger;
  }

  /// مقارنة اتجاهية: الجيد = ثبات أو ارتفاع (انخفاض > 10% يربّص).
  static AlertLevel _trend(double current, double previous, double floor) {
    if (previous <= 0) return AlertLevel.unknown;
    final ratio = current / previous;
    if (ratio >= floor) return AlertLevel.good;
    if (ratio >= floor - 0.10) return AlertLevel.warning;
    return AlertLevel.danger;
  }

  /// عكس الاتجاه: الجيد = ثبات أو انخفاض (ارتفاع > 10% يربّص).
  static AlertLevel _inverseTrend(
    double current,
    double previous,
    double ceil,
  ) {
    if (previous <= 0) return AlertLevel.unknown;
    final ratio = current / previous;
    if (ratio <= ceil) return AlertLevel.good;
    if (ratio <= ceil + 0.10) return AlertLevel.warning;
    return AlertLevel.danger;
  }

  /// فرق يجب أن يكون صفراً — تسامح نسبي من قيمة الأساس.
  static AlertLevel _zeroTolerance(double diff, double base, double tol) {
    final a = diff.abs();
    if (a <= 1) return AlertLevel.good;
    final rel = base > 0 ? a / base : a;
    if (rel <= tol) return AlertLevel.warning;
    return AlertLevel.danger;
  }
}

/// إحصاءات فترة واحدة (7 أيام).
class _PeriodStats {
  const _PeriodStats({
    required this.soldNights,
    required this.daysCount,
    required this.totalRooms,
    required this.collected,
    required this.roomRevenue,
    required this.cashIncome,
    required this.expensesTotal,
    required this.salaries,
    required this.diesel,
    required this.other,
    required this.dueMatured,
  });

  final int soldNights;
  final int daysCount;
  final int totalRooms;
  final double collected;
  final double roomRevenue;
  final double cashIncome;
  final double expensesTotal;
  final double salaries;
  final double diesel;
  final double other;
  final double dueMatured;

  /// الإشغال = الليالي المباعة ÷ (الغرف × أيام الفترة).
  double get occupancy {
    final available = totalRooms * daysCount;
    if (available <= 0) return 0;
    return (soldNights / available).clamp(0.0, 1.0);
  }

  double get adr => soldNights > 0 ? roomRevenue / soldNights : 0;

  double revpar(int rooms) =>
      rooms <= 0 ? 0 : roomRevenue / (rooms * daysCount);

  double get collectionRate =>
      dueMatured > 0 ? (collected / dueMatured).clamp(0.0, 10.0) : 0;

  double get netFlow => collected - expensesTotal;

  double get cashDiff => cashIncome - collected;

  double get revenueDiff => dueMatured - collected;

  /// الرواتب ÷ النقد المحصل (الإيراد المحقق فعلياً).
  double get salariesRatio => collected <= 0 ? 0 : salaries / collected;

  double get dieselRatio => collected <= 0 ? 0 : diesel / collected;

  double get otherRatio =>
      expensesTotal <= 0 ? 0 : other / expensesTotal;
}
