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
///   2. تاريخ المغادرة التلقائي = تاريخ الدخول + عدد الليالي المغطاة بالمدفوع
///   3. لا يتم تغيير حالة الحجز أو تسجيل مغادرة تلقائياً أبداً
///   4. كل دفعة جديدة تُحدّث: الرصيد، التاريخ التلقائي، فترة التغطية فوراً
///   5. تعديلات الأسعار من booking_price_adjustments فقط
/// ─────────────────────────────────────────────────────────────────

class StayBalanceResult {
  const StayBalanceResult({
    required this.checkinDate,
    required this.manualCheckoutDate,
    required this.autoCheckoutDate,
    required this.totalPaid,
    required this.nightlyRate,
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

  /// سعر الليلة الواحدة الأساسي (من جدول الغرف أو مشتق)
  final double nightlyRate;

  /// متوسط سعر الليلة الفعلي بعد تطبيق تعديلات الأسعار
  final double effectiveNightlyRate;

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

  /// الفائض بعد تغطية جميع الليالي المدفوعة بالكامل
  final double surplusAfterAllNights;

  /// الرصيد المتبقي الخام من الحجز (من قاعدة البيانات)
  final double rawRemainingBalance;

  /// قائمة التواريخ المغطاة بالكامل من المدفوعات التراكمية
  final List<DateTime> coveredDates;

  // ─── computed properties ───

  /// هل يوجد مدفوعات فعلية؟
  bool get hasPayments => totalPaid > 0 && nightlyRate > 0;

  /// هل الرصيد زائد (مدفوع زيادة)؟
  bool get isOverpaid => rawRemainingBalance < 0;

  /// مبلغ الرصيد الزائد المطلق
  double get creditAmount => isOverpaid ? -rawRemainingBalance : 0;

  /// نسبة التغطية حتى التاريخ اليدوي (0.0 - 1.0)
  double get manualCoverageRatio {
    if (manualNightsRemaining <= 0) {
      return isAutoExtended ? 1.0 : (hasPayments ? 1.0 : 0.0);
    }
    final totalNeeded = actualNightsSpent + manualNightsRemaining;
    if (totalNeeded <= 0) {
      return 1.0;
    }
    return (totalPaidNights / totalNeeded).clamp(0.0, 1.0);
  }

  /// الأيام غير المغطاة حتى التاريخ اليدوي
  int get uncoveredDays {
    if (isAutoExtended || manualNightsRemaining <= 0) {
      return 0;
    }
    final coveredBeyondActual = totalPaidNights > actualNightsSpent ? totalPaidNights - actualNightsSpent : 0;
    return (manualNightsRemaining - coveredBeyondActual).clamp(0, manualNightsRemaining);
  }

  /// تكلفة الأيام غير المغطاة
  double get uncoveredCost => uncoveredDays * effectiveNightlyRate;

  /// تنسيق التاريخ
  String formatDate(DateTime? dt) {
    if (dt == null) {
      return '---';
    }
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  String toString() {
    return 'StayBalanceResult(autoCheckout=${formatDate(autoCheckoutDate)}, '
        'paidNights=$totalPaidNights, effectiveBalance=$effectiveBalance, '
        'isExtended=$isAutoExtended, effectiveRate=$effectiveNightlyRate)';
  }
}

class StayBalanceCalculator {
  const StayBalanceCalculator();

  /// ─── فلترة تعديلات الأسعار النشطة ───
  /// منطق موحد يضمن أن الشاشتين تستخدمان نفس معايير الفلترة
  /// (متوافق مع EnhancedBookingCalculationService._fetchActiveAdjustments)
  static List<BookingPriceAdjustment> filterActiveAdjustments(
    Booking booking,
    List<BookingPriceAdjustment> adjustments,
  ) {
    final bookingDiscount = booking.discount;

    return adjustments.where((adj) {
      // ① استبعاد سجلات legacy_discount دائماً
      if (adj.reason == 'legacy_discount') {
        return false;
      }

      // ② التحقق من roomNumber — تجنب تطبيق تخفيض من حجز آخر
      final adjRoom = adj.roomNumber?.trim();
      if (adjRoom == null || adjRoom.isEmpty) {
        return false;
      }
      final room = booking.roomNumber.trim();
      if (adjRoom != room) {
        return false;
      }

      // ③ حماية: إذا لم يكن هناك تخفيض على الحجز (discount = 0)
      //    فتجنب تطبيق أي تعديل بـ amount سلبي بدون سبب واضح
      if (bookingDiscount <= 0 && adj.adjustmentType == 0 && adj.reason == null) {
        return false;
      }

      return true;
    }).toList();
  }

  /// حساب شامل للرصيد وتاريخ المغادرة التلقائي
  ///
  /// [booking] - بيانات الحجز من قاعدة البيانات
  /// [roomRate] - سعر الليلة الفعلي (من جدول الغرف)
  /// [priceAdjustments] - تعديلات الأسعار النشطة (من booking_price_adjustments)
  /// [now] - الوقت الحالي (للاختبار، يُستخدم DateTime.now() تلقائياً)
  static StayBalanceResult calculate(
    Booking booking, {
    double? roomRate,
    List<BookingPriceAdjustment>? priceAdjustments,
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final checkin = DateTime.tryParse(booking.checkinDate) ?? moment;
    final checkinDateOnly = DateTime(checkin.year, checkin.month, checkin.day);

    // ✅ حماية: إذا كان checkinDate فارغ أو تالف بالكامل، نستخدم now
    // لمنع القيم السلبية أو الحلقات اللانهائية
    if (booking.checkinDate.isEmpty) {
      return _fallbackResult(booking, moment);
    }

    // تاريخ المغادرة اليدوي
    final DateTime? manualCheckout = (booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty)
        ? DateTime.tryParse(booking.checkoutDate!)
        : null;

    // سعر الليلة الأساسي: يُفضّل السعر المُمرّر، وإلا يُحسب من إجمالي العقد
    // ✅ حماية: التأكد من أن totalDueCached و calculatedNights ليسا صفراً
    // لتجنب القسمة على صفر أو قيم NaN
    final double baseRate;
    if (roomRate != null && roomRate > 0) {
      baseRate = roomRate;
    } else if (booking.calculatedNights > 0 && booking.totalDueCached > 0) {
      baseRate = booking.totalDueCached / booking.calculatedNights;
    } else {
      baseRate = 0;
    }

    // ✅ حماية: إذا كان سعر الليلة صفراً ولا توجد مدفوعات،
    // نُعيد نتيجة آمنة بدون محاكاة مكلفة
    if (baseRate <= 0 && booking.totalPaidCached <= 0) {
      return _fallbackResult(booking, moment);
    }

    // ─── بناء خريطة تعديلات الأسعار لكل ليلة ───
    final adjMap = _buildPerNightAdjustments(priceAdjustments, checkinDateOnly, manualCheckout);

    // ─── حساب بداية يوم الفندق الأول (قاعدة 14:00) ───
    DateTime firstHotelDay = DateTime(checkin.year, checkin.month, checkin.day, 14);
    if (checkin.isBefore(firstHotelDay)) {
      firstHotelDay = firstHotelDay.subtract(const Duration(days: 1));
    }

    // ─── محاكاة يوم بيوم لحساب الليالي المغطاة ───
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
      final effectiveRate = (baseRate + adjustment).clamp(0.0, baseRate > 0 ? baseRate * 3 : 0).toDouble();
      final effectiveRateMinor = toMinor(effectiveRate);

      if (effectiveRateMinor <= 0) {
        break;
      }

      if (remainingBalanceMinor >= effectiveRateMinor) {
        remainingBalanceMinor -= effectiveRateMinor;
        totalCoveredNights++;
        coveredDates.add(currentNight);
        currentNight = currentNight.add(const Duration(days: 1));
      } else {
        break;
      }
    }

    // ─── حساب تكلفة الأيام المقضية فعلياً ───
    final actualNightsSpent = Time.nightsWithCutoff(checkin, checkout: moment);

    int consumedCostMinor = 0;
    DateTime consumedNight = firstHotelDay;
    for (int i = 0; i < actualNightsSpent && i < 3650; i++) {
      final key = Time.dateToString(consumedNight);
      final adjustment = adjMap[key] ?? 0.0;
      final nightRate = (baseRate + adjustment).clamp(0.0, baseRate > 0 ? baseRate * 3 : 0).toDouble();
      consumedCostMinor += toMinor(nightRate);
      consumedNight = consumedNight.add(const Duration(days: 1));
    }

    final consumedCost = fromMinor(consumedCostMinor);

    // ─── الرصيد الفعلي = إجمالي المدفوع - تكلفة الأيام المقضية ───
    final effectiveBalance = fromMinor(totalPaidMinor - consumedCostMinor);

    // ─── تاريخ المغادرة التلقائي ───
    final autoCheckout = checkinDateOnly.add(Duration(days: totalCoveredNights));

    // ─── الأيام المتبقية حتى تاريخ المغادرة اليدوي ───
    final int manualNightsRemaining = (manualCheckout != null && manualCheckout.isAfter(moment))
        ? Time.nightsWithCutoff(moment, checkout: manualCheckout)
        : 0;

    // ─── هل التاريخ التلقائي يتجاوز التاريخ اليدوي؟ ───
    final bool isAutoExtended = manualCheckout != null && autoCheckout.isAfter(manualCheckout);

    // ─── عدد الأيام الإضافية وراء تاريخ المغادرة اليدوي ───
    final int extraNightsBeyondManual = isAutoExtended
        ? Time.nightsWithCutoff(manualCheckout, checkout: autoCheckout)
        : 0;

    // ─── الفائض المالي بعد تغطية جميع الليالي ───
    final surplusMinor = remainingBalanceMinor < 0 ? 0 : remainingBalanceMinor;
    final double surplusAfterAllNights = fromMinor(surplusMinor);

    // ─── متوسط السعر الفعلي بعد التعديلات ───
    double effectiveNightlyRate = baseRate;
    if (totalCoveredNights > 0 && priceAdjustments != null && priceAdjustments.isNotEmpty) {
      final totalCoveredCostMinor = totalPaidMinor - surplusMinor;
      if (totalCoveredCostMinor > 0) {
        effectiveNightlyRate = fromMinor(totalCoveredCostMinor) / totalCoveredNights;
      }
    }

    return StayBalanceResult(
      checkinDate: checkin,
      manualCheckoutDate: manualCheckout,
      autoCheckoutDate: autoCheckout,
      totalPaid: booking.totalPaidCached,
      nightlyRate: baseRate,
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
    );
  }

  /// حساب سريع فقط لتاريخ المغادرة التلقائي
  static DateTime calculateAutoCheckout(
    Booking booking, {
    double? nightlyRate,
    List<BookingPriceAdjustment>? priceAdjustments,
  }) {
    final result = calculate(booking, roomRate: nightlyRate, priceAdjustments: priceAdjustments);
    return result.autoCheckoutDate;
  }

  /// حساب سريع لعدد الليالي المدفوعة
  static int calculatePaidNights(
    Booking booking, {
    double? nightlyRate,
    List<BookingPriceAdjustment>? priceAdjustments,
  }) {
    final result = calculate(booking, roomRate: nightlyRate, priceAdjustments: priceAdjustments);
    return result.totalPaidNights;
  }

  /// ─── بناء خريطة التعديلات لكل ليلة ───
  /// يحوّل قائمة التعديلات إلى Map<dateString, adjustmentAmount>
  /// بحيث يمكن البlookup بسرعة أثناء المحاكاة اليومية
  ///
  /// يدعم وضعين:
  ///   - per_night: يُطبّق المبلغ كاملاً على كل ليلة في النطاق
  ///   - total: يُوزّع المبلغ بالتساوي على ليالي النطاق
  static Map<String, double> _buildPerNightAdjustments(
    List<BookingPriceAdjustment>? adjustments,
    DateTime checkinDateOnly,
    DateTime? manualCheckout,
  ) {
    if (adjustments == null || adjustments.isEmpty) {
      return const {};
    }

    final map = <String, double>{};
    // ✅ إصلاح: تقليص farFuture من 3650 إلى 365 يوم (سنة واحدة)
    // الحجوزات التي تمتد لأكثر من سنة بدون تاريخ مغادرة يدوي نادرة جداً
    // وغالباً تشير إلى بيانات تالفة
    final farFuture = manualCheckout ?? checkinDateOnly.add(const Duration(days: 365));

    for (final adj in adjustments) {
      final effectiveDate = DateTime.tryParse(adj.effectiveHotelDay);
      if (effectiveDate == null) {
        continue;
      }

      // تطبيع التواريخ إلى بداية اليوم فقط (تجنب مشاكل المنطقة الزمنية)
      final effDateOnly = DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day);

      final endDate = adj.endHotelDay != null ? DateTime.tryParse(adj.endHotelDay!) : null;
      final adjEnd = endDate != null ? DateTime(endDate.year, endDate.month, endDate.day) : farFuture;

      final isDiscount = adj.adjustmentType == 0;
      final rawAmount = adj.amount;

      if (adj.adjustmentMode == 'total') {
        // توزيع إجمالي المبلغ بالتساوي على ليالي النطاق
        int daysInRange = adjEnd.difference(effDateOnly).inDays + 1;
        if (daysInRange <= 0) {
          continue;
        }
        // ✅ إصلاح: حد أمان لمنع حلقات طويلة جداً (أقصى 365 يوم)
        // التعديلات التي تمتد لأكثر من سنة غير منطقية وغالباً بيانات تالفة
        if (daysInRange > 365) {
          daysInRange = 365;
        }

        final amountPerNight = rawAmount / daysInRange;

        for (int i = 0; i < daysInRange; i++) {
          final night = effDateOnly.add(Duration(days: i));
          final key = Time.dateToString(night);
          final signed = isDiscount ? -amountPerNight : amountPerNight;
          map[key] = (map[key] ?? 0.0) + signed;
        }
      } else {
        // per_night: يُطبّق المبلغ كاملاً على كل ليلة في النطاق
        DateTime night = effDateOnly;
        int safetyCounter = 0;
        // ✅ إصلاح: تقليص حد الأمان من 3650 إلى 365 (سنة واحدة)
        while (!night.isAfter(adjEnd) && safetyCounter < 365) {
          final key = Time.dateToString(night);
          final signed = isDiscount ? -rawAmount : rawAmount;
          map[key] = (map[key] ?? 0.0) + signed;
          night = night.add(const Duration(days: 1));
          safetyCounter++;
        }
      }
    }

    return map;
  }

  /// ✅ نتيجة احتياطية آمنة عند وجود بيانات تالفة أو ناقصة
  /// تُستخدم بدلاً من رمي استثناء يُنهي التطبيق
  static StayBalanceResult _fallbackResult(Booking booking, DateTime moment) {
    final checkin = DateTime.tryParse(booking.checkinDate) ?? moment;
    final checkout = (booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty)
        ? DateTime.tryParse(booking.checkoutDate!)
        : null;
    return StayBalanceResult(
      checkinDate: checkin,
      manualCheckoutDate: checkout,
      autoCheckoutDate: checkout ?? checkin.add(const Duration(days: 1)),
      totalPaid: booking.totalPaidCached,
      nightlyRate: 0,
      effectiveNightlyRate: 0,
      actualNightsSpent: 0,
      totalPaidNights: 0,
      consumedCost: 0,
      effectiveBalance: booking.remainingBalanceCached,
      manualNightsRemaining: 0,
      isAutoExtended: false,
      extraNightsBeyondManual: 0,
      surplusAfterAllNights: 0,
      rawRemainingBalance: booking.remainingBalanceCached,
      coveredDates: const [],
    );
  }
}
