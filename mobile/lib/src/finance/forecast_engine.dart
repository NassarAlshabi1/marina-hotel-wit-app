/// محرك نموذج التدفقات النقدية لـ13 أسبوعاً.
///
/// يبني توقعاً أسبوعياً (أسبوع فندقي خميس → أربعاء) من البيانات الحية
/// المتزامنة من Appwrite:
///
/// **الداخل** بثلاث طبقات يقين (مؤكد / مرجّح / تقديري):
/// - مؤكد: بقايا مستحقة على نزلاء داخل الفندق أو حجوزات دفعت عربوناً —
///   تُحصّل عند المغادرة أو الدخول ولا تنخفض بمعاملات السيناريو.
/// - مرجّح: بقايا حجوزات مستقبلية مؤكدة لم تُدفع بعد.
/// - تقديري: ليالي غير محجوزة × الإشغال التاريخي × ADR، موزعة على وسائل
///   الدفع الفعلية مع أيام تأخر التحصيل المقاسة من السجل.
///
/// **الخارج** التزامات أسبوعية ثابتة:
/// - الرواتب: مجموع رواتب الموظفين النشطين ÷ 4.33 (حصة أسبوعية من الشهر).
/// - ديزل / مرافق / صيانة / أخرى: متوسط الإنفاق الأسبوعي التاريخي.
///
/// **السيولة**: رصيد متدحرج أسبوعياً، حد أدنى ديناميكي = متوسط الخارج
/// الأسبوعي × أسابيع التغطية المستهدفة، والتمويل المطلوب = أكبر عجز.
library;

import '../../services/local_db.dart' as db;
import '../../services/sync/payload_mapper.dart';
import 'finance_date_utils.dart';
import 'finance_models.dart';

class ForecastEngine {
  const ForecastEngine();

  /// يبني نموذج الـ13 أسبوعاً لسيناريو واحد.
  ///
  /// [bookings] الحجوزات النشطة فقط (غير المحذوفة/الملغاة).
  /// [payments] / [expenses] السجلات النشطة كاملة التاريخ.
  /// [employees] جميع الموظفين (يُفلتر النشطون داخلياً).
  ForecastResult build({
    required List<db.Booking> bookings,
    required List<db.Payment> payments,
    required List<db.Expense> expenses,
    required List<db.Employee> employees,
    required int totalRooms,
    required ScenarioParams scenario,
    required PaymentProfile profile,
    DateTime? forecastStart,
    int weeksCount = 13,
    int coverageTargetWeeks = 4,
    int expenseLookbackDays = 60,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final start =
        forecastStart ?? _defaultForecastStart(ref); // بداية الشهر القادم

    // ── 1) الأسابيع ──────────────────────────────────────────────────
    final weeks = <(DateTime, DateTime)>[];
    for (var i = 0; i < weeksCount; i++) {
      final wStart = start.add(Duration(days: 7 * i));
      final wEnd = start.add(Duration(days: 7 * i + 6));
      weeks.add((dayStart(wStart), dayStart(wEnd)));
    }

    // ── 2) رصيد البداية: المدفوعات − المصروفات قبل بداية النموذج ─────
    // (نفس منطق «الصندوق» المعتمد في شاشة الصندوق والمالية)
    var openingBalance = 0.0;
    for (final p in payments) {
      final d = tryParseDate(p.paymentDate);
      if (d != null && d.isBefore(start)) openingBalance += p.amount;
    }
    for (final e in expenses) {
      final d = tryParseDate(e.date);
      if (d != null && d.isBefore(start)) openingBalance -= e.amount;
    }

    // ── 3) الخارج الأسبوعي الثابت ────────────────────────────────────
    final outflow = _weeklyOutflow(
      expenses: expenses,
      employees: employees,
      forecastStart: start,
      lookbackDays: expenseLookbackDays,
    );

    // ── 4) حاويات الداخل ─────────────────────────────────────────────
    final confirmedByWeek = List<double>.filled(weeksCount, 0);
    final probableByWeek = List<double>.filled(weeksCount, 0);
    final estimatedByWeek = List<double>.filled(weeksCount, 0);

    // لكل يوم: عدد الغرف المحجوزة فعلياً (لتقدير الليالي غير المحجوزة)
    final bookedNightsByDay = List<int>.filled(7 * weeksCount, 0);

    for (final b in bookings) {
      final checkin = tryParseDate(b.checkinDate);
      if (checkin == null) continue;
      final checkout = _effectiveCheckout(b, checkin);
      final rawRemaining = b.totalDueCached - b.totalPaidCached;
      final remaining = rawRemaining < 0 ? 0.0 : rawRemaining;

      // ليالي الإشغال داخل نافذة النموذج
      for (var d = 0; d < 7 * weeksCount; d++) {
        final day = start.add(Duration(days: d));
        final occupies = !day.isBefore(dayStart(checkin)) &&
            dayStart(checkout).isAfter(day);
        if (occupies) bookedNightsByDay[d]++;
      }

      if (remaining <= 0) continue;
      if (!dayStart(checkout).isAfter(start)) continue; // انتهى قبل النموذج

      // توقيت التحصيل: نزيل حالي → أسبوع المغادرة؛ حجز قادم → أسبوع الدخول
      final isCurrentGuest = dayStart(checkin).isBefore(start);
      final anchor = isCurrentGuest ? checkout : checkin;
      final weekIdx = _weekIndexOf(anchor, start, weeksCount);
      if (weekIdx < 0) continue;

      if (isCurrentGuest || b.totalPaidCached > 0) {
        confirmedByWeek[weekIdx] += remaining;
      } else {
        probableByWeek[weekIdx] += remaining;
      }
    }

    // معاملات السيناريو: المؤكد لا يُخفض — المرجّح والتقديري يتأثران.
    final probableFactor = scenario.revenueFactor * scenario.collectionFactor;
    for (var i = 0; i < weeksCount; i++) {
      probableByWeek[i] *= probableFactor;
    }

    // ── 5) التدفق التقديري: الليالي غير المحجوزة ─────────────────────
    final availableRooms = totalRooms > 0 ? totalRooms : 0;
    if (availableRooms > 0 && profile.historicalAdr > 0) {
      final expectedSoldPerDay = availableRooms * profile.historicalOccupancy;
      for (var d = 0; d < 7 * weeksCount; d++) {
        final incrementalNights =
            (expectedSoldPerDay - bookedNightsByDay[d]).clamp(0.0, availableRooms.toDouble());
        if (incrementalNights <= 0) continue;
        final dayRevenue = incrementalNights * profile.historicalAdr;
        final day = start.add(Duration(days: d));

        // توزيع إيراد اليوم على وسائل الدفع مع أيام تأخر التحصيل الفعلية
        for (final m in profile.methods) {
          final cashDate = day.add(Duration(days: m.lagDays));
          final wIdx = _weekIndexOf(cashDate, start, weeksCount);
          if (wIdx < 0) continue;
          estimatedByWeek[wIdx] += dayRevenue * m.share;
        }
      }
      for (var i = 0; i < weeksCount; i++) {
        estimatedByWeek[i] *= probableFactor;
      }
    }

    // ── 6) بناء الأسابيع بالرصيد المتدحرج ────────────────────────────
    final avgWeeklyOutflow = outflow.total;
    final threshold = avgWeeklyOutflow * coverageTargetWeeks;
    final resultWeeks = <WeeklyForecast>[];
    var rolling = openingBalance;

    for (var i = 0; i < weeksCount; i++) {
      final inflow = WeeklyInflow(
        confirmed: confirmedByWeek[i],
        probable: probableByWeek[i],
        estimated: estimatedByWeek[i],
      );
      final opening = rolling;
      rolling = opening + inflow.total - outflow.total;
      resultWeeks.add(
        WeeklyForecast(
          index: i + 1,
          start: weeks[i].$1,
          end: weeks[i].$2,
          inflow: inflow,
          outflow: outflow,
          openingBalance: opening,
          closingBalance: rolling,
          avgWeeklyOutflow: avgWeeklyOutflow,
          liquidityThreshold: threshold,
        ),
      );
    }

    return ForecastResult(
      scenario: scenario,
      start: start,
      openingBalance: openingBalance,
      avgWeeklyOutflow: avgWeeklyOutflow,
      liquidityThreshold: threshold,
      coverageTargetWeeks: coverageTargetWeeks,
      weeks: resultWeeks,
      paymentProfile: profile,
      generatedAt: ref,
    );
  }

  // ── مساعدات ───────────────────────────────────────────────────────

  /// بداية النموذج الافتراضية: أول يوم في الشهر القادم.
  static DateTime _defaultForecastStart(DateTime now) {
    final y = now.month == 12 ? now.year + 1 : now.year;
    final m = now.month == 12 ? 1 : now.month + 1;
    return DateTime(y, m);
  }

  /// فهرس الأسبوع الذي يقع فيه التاريخ، أو -1 إن كان خارج النافذة.
  static int _weekIndexOf(DateTime date, DateTime start, int weeksCount) {
    final idx = daysBetween(start, date) ~/ 7;
    if (idx < 0 || idx >= weeksCount) return -1;
    return idx;
  }

  /// تاريخ المغادرة الفعلي المتوقع مع بدائل منطقية.
  static DateTime _effectiveCheckout(db.Booking b, DateTime checkin) {
    final actual = _nonEmpty(b.actualCheckout);
    if (actual != null) {
      final d = tryParseDate(actual);
      if (d != null) return d;
    }
    final planned = _nonEmpty(b.checkoutDate);
    if (planned != null) {
      final d = tryParseDate(planned);
      if (d != null) return d;
    }
    return checkin.add(Duration(days: b.calculatedNights));
  }

  /// الخارج الأسبوعي الثابت من تاريخ المصروفات ورواتب الموظفين.
  WeeklyOutflow _weeklyOutflow({
    required List<db.Expense> expenses,
    required List<db.Employee> employees,
    required DateTime forecastStart,
    required int lookbackDays,
  }) {
    // الرواتب: مجموع رواتب النشطين ÷ 4.33 أسبوع في الشهر
    var monthlySalaries = 0.0;
    for (final e in employees) {
      if (e.status.trim().toLowerCase() == 'active' ||
          e.status.trim() == 'نشط') {
        monthlySalaries += e.basicSalary;
      }
    }
    final salariesWeekly = monthlySalaries / 4.33;

    // فئات المصروفات من التاريخ الحديث (بعد استبعاد مصروفات الرواتب
    // لتجنب الاحتساب المزدوج مع رواتب الموظفين)
    final historyStart =
        dayStart(forecastStart).subtract(Duration(days: lookbackDays));
    var diesel = 0.0, utilities = 0.0, maintenance = 0.0, other = 0.0;

    for (final e in expenses) {
      if (PayloadMapper.isSalaryExpenseType(e.expenseType)) continue;
      final d = tryParseDate(e.date);
      if (d == null || d.isBefore(historyStart) || !d.isBefore(forecastStart)) {
        continue;
      }
      final t = e.expenseType.trim();
      if (t.contains('ديزل')) {
        diesel += e.amount;
      } else if (t.contains('كهرباء') || t.contains('مياه') || t.contains('فاتورة')) {
        utilities += e.amount;
      } else if (t.contains('صيانة')) {
        maintenance += e.amount;
      } else {
        other += e.amount;
      }
    }

    final weeksFactor = lookbackDays / 7;
    return WeeklyOutflow(
      salaries: salariesWeekly,
      diesel: diesel / weeksFactor,
      utilities: utilities / weeksFactor,
      maintenance: maintenance / weeksFactor,
      other: other / weeksFactor,
    );
  }

  static String? _nonEmpty(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s;
}
