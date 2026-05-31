import '../utils/hotel_date_helper.dart';
import '../utils/time.dart';
import 'local_db.dart';

/// ─────────────────────────────────────────────────────────────────
/// محرك حساب الرصيد المحسّن مع دقة هندسية احترافية
/// يوفر حسابات دقيقة للأيام والليالي والتمديد التلقائي والمتبقي
/// ─────────────────────────────────────────────────────────────────

class EnhancedStayBalanceResult {
  const EnhancedStayBalanceResult({
    required this.checkinDate,
    required this.manualCheckoutDate,
    required this.autoCheckoutDate,
    required this.totalPaid,
    required this.baseNightlyRate,
    required this.effectiveNightlyRate,
    required this.actualNightsSpent,
    required this.totalPaidNights,
    required this.consumedCost,
    required this.effectiveBalance,
    required this.manualNightsRemaining,
    required this.isAutoExtended,
    required this.extraNightsBeyondManual,
    required this.surplusAfterAllNights,
    required this.rawRemainingBalance,
    required this.coveredDates,
    required this.detailedBreakdown,
    required this.calculationMetadata,
  });

  // ─── التواريخ ───
  final DateTime checkinDate;
  final DateTime? manualCheckoutDate;
  final DateTime autoCheckoutDate;

  // ─── المبالغ ───
  final double totalPaid;
  final double baseNightlyRate;
  final double effectiveNightlyRate;
  final double consumedCost;
  final double effectiveBalance;
  final double surplusAfterAllNights;
  final double rawRemainingBalance;

  // ─── الأيام ───
  final int actualNightsSpent;
  final int totalPaidNights;
  final int manualNightsRemaining;

  // ─── التمديد ───
  final bool isAutoExtended;
  final int extraNightsBeyondManual;

  // ─── البيانات الإضافية ───
  final List<DateTime> coveredDates;
  final DetailedBreakdown detailedBreakdown;
  final CalculationMetadata calculationMetadata;

  // ─── computed properties ───
  bool get hasPayments => totalPaid > 0 && baseNightlyRate > 0;
  bool get isOverpaid => rawRemainingBalance < 0;
  double get creditAmount => isOverpaid ? -rawRemainingBalance : 0;

  double get manualCoverageRatio {
    if (manualNightsRemaining <= 0) {
      return isAutoExtended ? 1.0 : (hasPayments ? 1.0 : 0.0);
    }
    final totalNeeded = actualNightsSpent + manualNightsRemaining;
    if (totalNeeded <= 0) return 1.0;
    return (totalPaidNights / totalNeeded).clamp(0.0, 1.0);
  }

  int get uncoveredDays {
    if (isAutoExtended || manualNightsRemaining <= 0) return 0;
    final coveredBeyondActual = totalPaidNights > actualNightsSpent
        ? totalPaidNights - actualNightsSpent
        : 0;
    return (manualNightsRemaining - coveredBeyondActual).clamp(0, manualNightsRemaining);
  }

  double get uncoveredCost => uncoveredDays * effectiveNightlyRate;

  String formatDate(DateTime? dt) {
    if (dt == null) return '---';
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  String toString() {
    return 'EnhancedStayBalanceResult('
        'autoCheckout=${formatDate(autoCheckoutDate)}, '
        'paidNights=$totalPaidNights, '
        'effectiveBalance=$effectiveBalance, '
        'isExtended=$isAutoExtended, '
        'effectiveRate=$effectiveNightlyRate)';
  }
}

/// تفاصيل شاملة عن توزيع التكاليف والدفعات
class DetailedBreakdown {
  const DetailedBreakdown({
    required this.nightsBreakdown,
    required this.adjustmentsApplied,
    required this.paymentDistribution,
  });

  final List<NightBreakdownItem> nightsBreakdown;
  final List<AdjustmentItem> adjustmentsApplied;
  final List<PaymentDistributionItem> paymentDistribution;

  double get totalNightsCost =>
      nightsBreakdown.fold(0.0, (sum, item) => sum + item.finalCost);

  double get totalAdjustments =>
      adjustmentsApplied.fold(0.0, (sum, item) => sum + item.amount);
}

/// بيان تفصيلي لكل ليلة
class NightBreakdownItem {
  const NightBreakdownItem({
    required this.hotelDayKey,
    required this.baseRate,
    required this.adjustmentAmount,
    required this.finalCost,
    required this.isPaid,
    required this.appliedAdjustments,
  });

  final String hotelDayKey;
  final double baseRate;
  final double adjustmentAmount;
  final double finalCost;
  final bool isPaid;
  final List<String> appliedAdjustments;
}

/// بيان التعديلات المطبقة
class AdjustmentItem {
  const AdjustmentItem({
    required this.type,
    required this.reason,
    required this.amount,
    required this.appliedNights,
    required this.totalImpact,
  });

  final String type; // 'discount', 'surcharge', 'legacy_discount'
  final String? reason;
  final double amount;
  final int appliedNights;
  final double totalImpact;
}

/// توزيع الدفعات على الليالي
class PaymentDistributionItem {
  const PaymentDistributionItem({
    required this.paymentDate,
    required this.amount,
    required this.method,
    required this.nightsCovered,
    required this.fromNightIndex,
    required this.toNightIndex,
  });

  final DateTime paymentDate;
  final double amount;
  final String method;
  final int nightsCovered;
  final int fromNightIndex;
  final int toNightIndex;
}

/// بيانات وصفية عن الحساب
class CalculationMetadata {
  const CalculationMetadata({
    required this.calculatedAt,
    required this.calculationMethod,
    required this.precision,
    required this.notes,
  });

  final DateTime calculatedAt;
  final String calculationMethod; // 'day_by_day', 'formula_based'
  final String precision; // 'high', 'medium', 'low'
  final List<String> notes;
}

class EnhancedStayBalanceCalculator {
  const EnhancedStayBalanceCalculator();

  /// حساب شامل مع تفاصيل دقيقة
  static EnhancedStayBalanceResult calculate(
    Booking booking, {
    double? roomRate,
    List<BookingPriceAdjustment>? priceAdjustments,
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final checkin = DateTime.tryParse(booking.checkinDate) ?? moment;
    final checkinDateOnly = DateTime(checkin.year, checkin.month, checkin.day);

    final DateTime? manualCheckout =
        (booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty)
            ? DateTime.tryParse(booking.checkoutDate!)
            : null;

    final double baseRate = (roomRate != null && roomRate > 0)
        ? roomRate
        : (booking.calculatedNights > 0
            ? booking.totalDueCached / booking.calculatedNights
            : 0);

    // بناء خريطة التعديلات
    final adjMap = _buildPerNightAdjustments(
      priceAdjustments,
      checkinDateOnly,
      manualCheckout,
    );

    // حساب بداية يوم الفندق الأول (قاعدة 14:00) — عبر المصدر الوحيد HotelDateHelper
    final firstHotelDay = HotelDateHelper.getHotelDay(checkin);

    // محاكاة يوم بيوم مع جمع التفاصيل
    final nightsBreakdown = <NightBreakdownItem>[];
    final coveredDates = <DateTime>[];
    int toMinor(double amount) => amount.round();
    double fromMinor(int amount) => amount.toDouble();

    final totalPaidMinor = toMinor(booking.totalPaidCached);
    int remainingBalanceMinor = totalPaidMinor;
    int totalCoveredNights = 0;

    DateTime currentNight = firstHotelDay;
    for (int i = 0; i < 3650; i++) {
      final key = Time.dateToString(currentNight);
      final adjustment = adjMap[key] ?? 0.0;
      final effectiveRate =
          (baseRate + adjustment).clamp(0.0, baseRate > 0 ? baseRate * 3 : 0).toDouble();
      final effectiveRateMinor = toMinor(effectiveRate);

      if (effectiveRateMinor <= 0) break;

      final isPaid = remainingBalanceMinor >= effectiveRateMinor;
      if (isPaid) {
        remainingBalanceMinor -= effectiveRateMinor;
        totalCoveredNights++;
        coveredDates.add(currentNight);
      }

      nightsBreakdown.add(
        NightBreakdownItem(
          hotelDayKey: key,
          baseRate: baseRate,
          adjustmentAmount: adjustment,
          finalCost: effectiveRate,
          isPaid: isPaid,
          appliedAdjustments: adjustment != 0 ? [key] : [],
        ),
      );

      if (!isPaid) break;
      currentNight = currentNight.add(const Duration(days: 1));
    }

    // حساب تكلفة الأيام المقضية فعلياً
    final actualNightsSpent =
        HotelDateHelper.calculateNights(checkIn: checkin, checkOut: moment);

    int consumedCostMinor = 0;
    DateTime consumedNight = firstHotelDay;
    for (int i = 0; i < actualNightsSpent && i < 3650; i++) {
      final key = Time.dateToString(consumedNight);
      final adjustment = adjMap[key] ?? 0.0;
      final nightRate = (baseRate + adjustment).clamp(
        0.0,
        baseRate > 0 ? baseRate * 3 : 0,
      ).toDouble();
      consumedCostMinor += toMinor(nightRate);
      consumedNight = consumedNight.add(const Duration(days: 1));
    }

    final consumedCost = fromMinor(consumedCostMinor);
    final effectiveBalance = fromMinor(totalPaidMinor - consumedCostMinor);

    // تاريخ المغادرة التلقائي
    final autoCheckout = checkinDateOnly.add(Duration(days: totalCoveredNights));

    // الأيام المتبقية
    final int manualNightsRemaining =
        (manualCheckout != null && manualCheckout.isAfter(moment))
            ? HotelDateHelper.calculateNights(checkIn: moment, checkOut: manualCheckout)
            : 0;

    // هل التاريخ التلقائي يتجاوز التاريخ اليدوي؟
    final bool isAutoExtended =
        manualCheckout != null && autoCheckout.isAfter(manualCheckout);

    // عدد الأيام الإضافية
    final int extraNightsBeyondManual = isAutoExtended
        ? HotelDateHelper.calculateNights(checkIn: manualCheckout, checkOut: autoCheckout)
        : 0;

    // الفائض المالي
    final surplusMinor = remainingBalanceMinor < 0 ? 0 : remainingBalanceMinor;
    final double surplusAfterAllNights = fromMinor(surplusMinor);

    // متوسط السعر الفعلي
    double effectiveNightlyRate = baseRate;
    if (totalCoveredNights > 0 &&
        priceAdjustments != null &&
        priceAdjustments.isNotEmpty) {
      final totalCoveredCostMinor = totalPaidMinor - surplusMinor;
      if (totalCoveredCostMinor > 0) {
        effectiveNightlyRate =
            fromMinor(totalCoveredCostMinor) / totalCoveredNights;
      }
    }

    // بناء التفاصيل
    final adjustmentsApplied = _buildAdjustmentsList(priceAdjustments);
    final paymentDistribution = _buildPaymentDistribution(
      booking,
      nightsBreakdown,
      firstHotelDay,
    );

    final metadata = CalculationMetadata(
      calculatedAt: moment,
      calculationMethod: 'day_by_day',
      precision: 'high',
      notes: [
        'تم حساب الأيام بناءً على قاعدة 14:00',
        'تم تطبيق جميع التعديلات المسجلة',
        'الرصيد الفعلي = المدفوع - المستهلك',
      ],
    );

    final breakdown = DetailedBreakdown(
      nightsBreakdown: nightsBreakdown,
      adjustmentsApplied: adjustmentsApplied,
      paymentDistribution: paymentDistribution,
    );

    return EnhancedStayBalanceResult(
      checkinDate: checkin,
      manualCheckoutDate: manualCheckout,
      autoCheckoutDate: autoCheckout,
      totalPaid: booking.totalPaidCached,
      baseNightlyRate: baseRate,
      effectiveNightlyRate: effectiveNightlyRate,
      actualNightsSpent: actualNightsSpent,
      totalPaidNights: totalCoveredNights,
      consumedCost: consumedCost,
      effectiveBalance: effectiveBalance,
      manualNightsRemaining: manualNightsRemaining,
      isAutoExtended: isAutoExtended,
      extraNightsBeyondManual: extraNightsBeyondManual,
      surplusAfterAllNights: surplusAfterAllNights,
      rawRemainingBalance: booking.remainingBalanceCached,
      coveredDates: coveredDates,
      detailedBreakdown: breakdown,
      calculationMetadata: metadata,
    );
  }

  /// بناء خريطة التعديلات لكل ليلة
  static Map<String, double> _buildPerNightAdjustments(
    List<BookingPriceAdjustment>? adjustments,
    DateTime checkinDateOnly,
    DateTime? manualCheckout,
  ) {
    final map = <String, double>{};
    if (adjustments == null || adjustments.isEmpty) return map;

    for (final adj in adjustments) {
      if (adj.isActive != true || adj.deletedAt != null) continue;

      final effectiveDate = DateTime.tryParse(adj.effectiveHotelDay);
      if (effectiveDate == null) continue;

      final endDate = adj.endHotelDay != null
          ? DateTime.tryParse(adj.endHotelDay!)
          : null;

      DateTime current = effectiveDate;
      while (current.isBefore(manualCheckout ?? DateTime(2099))) {
        if (endDate != null && current.isAfter(endDate)) break;

        final key = Time.dateToString(current);
        map[key] = (map[key] ?? 0) + adj.amount;

        current = current.add(const Duration(days: 1));
      }
    }

    return map;
  }

  /// بناء قائمة التعديلات المطبقة
  static List<AdjustmentItem> _buildAdjustmentsList(
    List<BookingPriceAdjustment>? adjustments,
  ) {
    final list = <AdjustmentItem>[];
    if (adjustments == null || adjustments.isEmpty) return list;

    for (final adj in adjustments) {
      if (adj.isActive != true || adj.deletedAt != null) continue;

      final effectiveDate = DateTime.tryParse(adj.effectiveHotelDay);
      final endDate = adj.endHotelDay != null
          ? DateTime.tryParse(adj.endHotelDay!)
          : null;

      if (effectiveDate == null) continue;

      int nightsCount = 0;
      DateTime current = effectiveDate;
      while (endDate == null || current.isBefore(endDate) || current.isAtSameMomentAs(endDate)) {
        nightsCount++;
        current = current.add(const Duration(days: 1));
        if (nightsCount > 3650) break;
      }

      list.add(
        AdjustmentItem(
          type: adj.adjustmentType == 0 ? 'discount' : 'surcharge',
          reason: adj.reason,
          amount: adj.amount,
          appliedNights: nightsCount,
          totalImpact: adj.amount * nightsCount,
        ),
      );
    }

    return list;
  }

  /// بناء توزيع الدفعات
  static List<PaymentDistributionItem> _buildPaymentDistribution(
    Booking booking,
    List<NightBreakdownItem> nights,
    DateTime firstHotelDay,
  ) {
    final list = <PaymentDistributionItem>[];
    // يمكن توسيع هذا لاحقاً لإضافة تفاصيل الدفعات الفعلية
    return list;
  }

  /// فلترة التعديلات النشطة
  static List<BookingPriceAdjustment> filterActiveAdjustments(
    Booking booking,
    List<BookingPriceAdjustment> adjustments,
  ) {
    final bookingDiscount = booking.discount;

    return adjustments.where((adj) {
      if (adj.reason == 'legacy_discount') return false;

      final adjRoom = adj.roomNumber?.trim();
      if (adjRoom == null || adjRoom.isEmpty) return false;

      final room = booking.roomNumber.trim();
      if (adjRoom != room) return false;

      if (bookingDiscount <= 0 &&
          adj.adjustmentType == 0 &&
          adj.reason == null) {
        return false;
      }

      return true;
    }).toList();
  }
}
