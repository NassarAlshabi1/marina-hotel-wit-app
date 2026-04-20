import 'package:flutter/foundation.dart';

import '../utils/currency_formatter.dart';
import '../utils/time.dart';
import 'local_db.dart';

/// ─────────────────────────────────────────────────────────────────
/// محرك حساب الرصيد الفعلي وتاريخ المغادرة التلقائي
/// محرك حساب موحد (Single Source of Truth) يُستخدم في:
///   - شاشة التقرير التفصيلي (Detailed Report)
///   - شاشة معالجة المدفوعات (Payment Processing)
///
/// القواعد الأساسية:
///   1. الرصيد التراكمي = إجمالي المدفوعات - تكلفة الأيام المقضية فعلياً
///   2. تاريخ المغادرة التلقائي = تاريخ الدخول + (إجمالي المدفوع / سعر الليلة)
///   3. لا يتم تغيير حالة الحجز أو تسجيل مغادرة تلقائياً أبداً
///   4. كل دفعة جديدة تُحدّث: الرصيد، التاريخ التلقائي، فترة التغطية فوراً
/// ─────────────────────────────────────────────────────────────────

class StayBalanceResult {
  const StayBalanceResult({
    required this.checkinDate,
    required this.manualCheckoutDate,
    required this.autoCheckoutDate,
    required this.totalPaid,
    required this.nightlyRate,
    required this.actualNightsSpent,
    required this.totalPaidNights,
    required this.consumedCost,
    required this.effectiveBalance,
    required this.manualNightsRemaining,
    required this.isAutoExtended,
    required this.extraNightsBeyondManual,
    required this.surplusAfterAllNights,
    required this.rawRemainingBalance,
  });

  // ─── التواريخ ───

  /// تاريخ تسجيل الدخول
  final DateTime checkinDate;

  /// تاريخ المغادرة المُحدد يدوياً (nullable)
  final DateTime? manualCheckoutDate;

  /// تاريخ المغادرة المحسوب تلقائياً = checkinDate + totalPaidNights
  final DateTime autoCheckoutDate;

  // ─── المبالغ ───

  /// إجمالي المدفوعات التراكمية
  final double totalPaid;

  /// سعر الليلة الواحدة
  final double nightlyRate;

  /// تكلفة الأيام المقضية فعلياً حتى الآن
  final double consumedCost;

  /// الرصيد الفعلي الفعّال = totalPaid - consumedCost
  /// هذا هو الرصيد الحقيقي بعد خصم تكلفة الإقامة المستهلكة
  final double effectiveBalance;

  // ─── الأيام ───

  /// الأيام المقضية فعلياً حتى الآن (بناءً على قاعدة 14:00)
  final int actualNightsSpent;

  /// إجمالي الليالي التي يغطيها المدفوع التراكمي
  final int totalPaidNights;

  /// الأيام المتبقية حتى تاريخ المغادرة اليدوي
  final int manualNightsRemaining;

  // ─── التمديد ───

  /// هل التاريخ التلقائي يتجاوز التاريخ اليدوي؟
  final bool isAutoExtended;

  /// عدد الأيام الإضافية وراء تاريخ المغادرة اليدوي
  final int extraNightsBeyondManual;

  /// الفائض بعد تغطية جميع الليالي المدفوعة
  final double surplusAfterAllNights;

  /// الرصيد المتبقي الخام من الحجز (من قاعدة البيانات)
  final double rawRemainingBalance;

  // ─── computed properties ───

  /// هل يوجد مدفوعات فعلية؟
  bool get hasPayments => totalPaid > 0 && nightlyRate > 0;

  /// هل الرصيد زائد (مدفوع زيادة)؟
  bool get isOverpaid => rawRemainingBalance < 0;

  /// مبلغ الرصيد الزائد المطلق
  double get creditAmount => isOverpaid ? -rawRemainingBalance : 0;

  /// نسبة التغطية حتى التاريخ اليدوي (0.0 - 1.0)
  double get manualCoverageRatio {
    if (manualNightsRemaining <= 0) return isAutoExtended ? 1.0 : (hasPayments ? 1.0 : 0.0);
    final totalNeeded = actualNightsSpent + manualNightsRemaining;
    if (totalNeeded <= 0) return 1.0;
    return (totalPaidNights / totalNeeded).clamp(0.0, 1.0);
  }

  /// الأيام غير المغطاة حتى التاريخ اليدوي
  int get uncoveredDays {
    if (isAutoExtended || manualNightsRemaining <= 0) return 0;
    final coveredBeyondActual = totalPaidNights > actualNightsSpent
        ? totalPaidNights - actualNightsSpent
        : 0;
    return (manualNightsRemaining - coveredBeyondActual).clamp(0, manualNightsRemaining);
  }

  /// تكلفة الأيام غير المغطاة
  double get uncoveredCost => uncoveredDays * nightlyRate;

  /// تنسيق التاريخ
  String formatDate(DateTime? dt) {
    if (dt == null) return '---';
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  String toString() {
    return 'StayBalanceResult(autoCheckout=${formatDate(autoCheckoutDate)}, '
        'paidNights=$totalPaidNights, effectiveBalance=$effectiveBalance, '
        'isExtended=$isAutoExtended)';
  }
}

class StayBalanceCalculator {
  const StayBalanceCalculator();

  /// حساب شامل للرصيد وتاريخ المغادرة التلقائي
  ///
  /// [booking] - بيانات الحجز من قاعدة البيانات
  /// [roomRate] - سعر الليلة الفعلي (من جدول الغرف)
  /// [now] - الوقت الحالي (للاختبار، يُستخدم DateTime.now() تلقائياً)
  static StayBalanceResult calculate(
    Booking booking, {
    double? roomRate,
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final checkin = DateTime.tryParse(booking.checkinDate) ?? moment;
    final checkinDateOnly = DateTime(checkin.year, checkin.month, checkin.day);

    // تاريخ المغادرة اليدوي
    final DateTime? manualCheckout = (booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty)
        ? DateTime.tryParse(booking.checkoutDate!)
        : null;

    // سعر الليلة: يُفضّل السعر المُمرّر، وإلا يُحسب من إجمالي العقد
    final double nightlyRate = (roomRate != null && roomRate > 0)
        ? roomRate
        : (booking.calculatedNights > 0 ? booking.totalDueCached / booking.calculatedNights : 0);

    // الأيام المقضية فعلياً حتى الآن
    final actualNightsSpent = Time.nightsWithCutoff(checkin, checkout: moment);

    // تكلفة الأيام المقضية فعلياً
    final consumedCost = actualNightsSpent * nightlyRate;

    // إجمالي المدفوعات التراكمية
    final totalPaid = booking.totalPaidCached;

    // الرصيد الفعلي الفعّال = المدفوع - تكلفة ما استُهلك
    final effectiveBalance = totalPaid - consumedCost;

    // إجمالي الليالي التي يغطيها المدفوع التراكمي
    final int totalPaidNights = (nightlyRate > 0 && totalPaid > 0)
        ? (totalPaid / nightlyRate).floor()
        : 0;

    // تاريخ المغادرة التلقائي = تاريخ الدخول + الليالي المدفوعة
    final autoCheckout = DateTime(
      checkinDateOnly.year,
      checkinDateOnly.month,
      checkinDateOnly.day,
    ).add(Duration(days: totalPaidNights));

    // الأيام المتبقية حتى تاريخ المغادرة اليدوي
    final int manualNightsRemaining = (manualCheckout != null && manualCheckout.isAfter(moment))
        ? Time.nightsWithCutoff(moment, checkout: manualCheckout)
        : 0;

    // هل التاريخ التلقائي يتجاوز التاريخ اليدوي؟
    final bool isAutoExtended = manualCheckout != null && autoCheckout.isAfter(manualCheckout);

    // الأيام الإضافية وراء تاريخ المغادرة اليدوي
    final int extraNightsBeyondManual = isAutoExtended
        ? Time.nightsWithCutoff(manualCheckout, checkout: autoCheckout)
        : 0;

    // الفائض المالي بعد تغطية جميع الليالي
    final double surplusAfterAllNights = (nightlyRate > 0 && totalPaid > 0)
        ? totalPaid - (totalPaidNights * nightlyRate)
        : 0;

    return StayBalanceResult(
      checkinDate: checkin,
      manualCheckoutDate: manualCheckout,
      autoCheckoutDate: autoCheckout,
      totalPaid: totalPaid,
      nightlyRate: nightlyRate,
      actualNightsSpent: actualNightsSpent,
      totalPaidNights: totalPaidNights,
      consumedCost: consumedCost,
      effectiveBalance: effectiveBalance,
      manualNightsRemaining: manualNightsRemaining,
      isAutoExtended: isAutoExtended,
      extraNightsBeyondManual: extraNightsBeyondManual,
      surplusAfterAllNights: surplusAfterAllNights,
      rawRemainingBalance: booking.remainingBalanceCached,
    );
  }

  /// حساب سريع فقط لتاريخ المغادرة التلقائي
  static DateTime calculateAutoCheckout(Booking booking, {double? nightlyRate}) {
    final result = calculate(booking, roomRate: nightlyRate);
    return result.autoCheckoutDate;
  }

  /// حساب سريع لعدد الليالي المدفوعة
  static int calculatePaidNights(Booking booking, {double? nightlyRate}) {
    final result = calculate(booking, roomRate: nightlyRate);
    return result.totalPaidNights;
  }
}
