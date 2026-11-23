import '../utils/hotel_time_engine.dart';
import '../utils/hotel_timezone.dart';
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
///   2. نهاية التغطية = بداية يوم الفندق الأول + الليالي المدفوعة، عند 14:01
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
    this.anomalyNights = const [],
    this.anomalyReason,
  });

  // ─── التواريخ ───

  /// تاريخ تسجيل الدخول
  final DateTime checkinDate;

  /// تاريخ المغادرة المُحدد يدوياً (nullable)
  final DateTime? manualCheckoutDate;

  /// حدّ بداية يوم الفندق التالي لعدد الليالي المدفوعة، بتوقيت Asia/Aden.
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

  /// الأيام المقضية فعلياً حتى الآن (بناءً على حدّ اليوم الفندقي 14:01)
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

  // ─── شذوذ قاعدة «لا ليالٍ مجانية» (تأكيد المالك 2026-11-23) ───

  /// ليالٍ وُجد سعرها الفعلي ≤ 0 أثناء المحاكاة/الاستهلاك — لا توجد
  /// ليالٍ مجانية في عمل الفندق ولا يُراد لها وجود، فأي سعر صفري شذوذ
  /// بيانات (خصم ≥ السعر، أو توزيع total يلغي الليلة، أو baseRate صفري
  /// مع مدفوعات) يُعلن هنا بدل كسر العدّ بصمت.
  final List<DateTime> anomalyNights;

  /// شرح نصي لأول شذوذ مكتشف (للعرض في الواجهة والسجلات).
  final String? anomalyReason;

  /// هل كُشف شذوذ سعر صفري؟ — المستهلكون يجب أن يعرضوا إنذاراً صريحاً.
  bool get hasAnomaly => anomalyNights.isNotEmpty || anomalyReason != null;

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
    final coveredBeyondActual = totalPaidNights > actualNightsSpent
        ? totalPaidNights - actualNightsSpent
        : 0;
    return (manualNightsRemaining - coveredBeyondActual).clamp(
      0,
      manualNightsRemaining,
    );
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
      if (bookingDiscount <= 0 &&
          adj.adjustmentType == 0 &&
          adj.reason == null) {
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
    final recordedCheckout =
        (booking.actualCheckout != null && booking.actualCheckout!.isNotEmpty)
        ? DateTime.tryParse(booking.actualCheckout!)
        : null;

    // ✅ حماية: إذا كان checkinDate فارغ أو تالف بالكامل، نستخدم now
    // لمنع القيم السلبية أو الحلقات اللانهائية
    if (booking.checkinDate.isEmpty) {
      return _fallbackResult(booking, moment);
    }

    // تاريخ المغادرة اليدوي
    final DateTime? manualCheckout =
        (booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty)
        ? DateTime.tryParse(booking.checkoutDate!)
        : null;

    // سعر الليلة الأساسي: يُفضّل السعر المُمرّر، وإلا يُحسب من إجمالي العقد
    // ✅ حماية: التأكد من أن totalDueCached و calculatedNights ليسا صفراً
    // لتجنب القسمة على صفر أو قيم NaN
    //
    // ✅ منع الاشتقاق المزدوج (بند 3.2): المتوسط totalDueCached/calculatedNights
    // محسوب من مستحق يشمل أثر التعديلات أصلاً — إعادة تطبيق adjMap فوقه
    // تعني احتساباً مزدوجاً. نعلّم المصدر ونمنع التطبيق الثاني أدناه.
    final double baseRate;
    final bool baseRateIncludesAdjustments;
    if (roomRate != null && roomRate > 0) {
      baseRate = roomRate;
      baseRateIncludesAdjustments = false;
    } else if (booking.calculatedNights > 0 && booking.totalDueCached > 0) {
      baseRate = booking.totalDueCached / booking.calculatedNights;
      baseRateIncludesAdjustments = true;
    } else {
      baseRate = 0;
      baseRateIncludesAdjustments = false;
    }

    // ✅ حماية: إذا كان سعر الليلة صفراً ولا توجد مدفوعات،
    // نُعيد نتيجة آمنة بدون محاكاة مكلفة
    if (baseRate <= 0 && booking.totalPaidCached <= 0) {
      return _fallbackResult(booking, moment);
    }

    // ✅ قاعدة «لا ليالٍ مجانية» (تأكيد المالك 2026-11-23): سعر أساسي صفري
    // مع وجود مدفوعات = شذوذ بيانات يُعلن ولا يُحاكى بصمت (السلوك القديم:
    // كسر فوري صامت عند أول ليلة بعدّ تغطية 0 — بند 3.2).
    if (baseRate <= 0) {
      return _fallbackResult(
        booking,
        moment,
        anomalyReason:
            'سعر الليلة الأساسي صفر/غير قابل للاشتقاق مع مدفوعات '
            '(${booking.totalPaidCached.toStringAsFixed(0)}) — '
            'قاعدة الفندق: لا ليالٍ مجانية؛ يلزم مراجعة بيانات الحجز/الغرفة',
      );
    }

    // ─── بناء خريطة تعديلات الأسعار لكل ليلة ───
    // ✅ توحيد توزيع تعديل total بمنطق المحرك الموحد (بند 3.1): التوزيع
    // على ليالي الإقامة الفعلية داخل النطاق — حتى نهاية الإقامة القانونية
    // (المغادرة الفعلية الماضية أو الآن للحجز النشط) — لا على أيام النطاق
    // التقويمي للتعديل نفسه الذي كان يمتد التغطية زوراً حتى +365 يوماً.
    DateTime hotelDayDate(DateTime instant) => DateTime.parse(
          HotelTimeEngine.getHotelDayKey(dateTime: instant),
        );
    final distributionEnd = recordedCheckout != null &&
            !recordedCheckout.isAfter(moment)
        ? hotelDayDate(recordedCheckout)
        : hotelDayDate(moment);
    // ✅ منع الاشتقاق المزدوج: إذا اشتُق baseRate من متوسط المستحق المخبأ
    // (الذي يشمل أثر التعديلات أصلاً) فلا تُطبّق التعديلات مرة أخرى.
    final adjMap = baseRateIncludesAdjustments
        ? const <String, double>{}
        : buildPerNightAdjustments(
            priceAdjustments,
            checkinDateOnly,
            manualCheckout,
            distributionEnd: distributionEnd,
          );

    // ─── حساب بداية يوم الفندق الأول (قاعدة 14:01) ───
    final hotelDay = HotelTimeEngine.getHotelDay(checkin);
    final firstHotelDay = HotelTimezone.atHotelTime(
      hotelDay.year,
      hotelDay.month,
      hotelDay.day,
      HotelTimeEngine.boundaryHour,
      HotelTimeEngine.boundaryMinute,
    );

    // ─── محاكاة يوم بيوم لحساب الليالي المغطاة ───
    final coveredDates = <DateTime>[];
    int toMinor(double amount) => amount.round();
    double fromMinor(int amount) => amount.toDouble();

    final totalPaidMinor = toMinor(booking.totalPaidCached);
    int remainingBalanceMinor = totalPaidMinor;
    int totalCoveredNights = 0;

    DateTime currentNight = firstHotelDay;
    final anomalyNights = <DateTime>[];
    String? anomalyReason;
    for (int i = 0; i < 3650; i++) {
      final key = Time.dateToString(currentNight);
      final adjustment = adjMap[key] ?? 0.0;
      final effectiveRate = (baseRate + adjustment)
          .clamp(0.0, baseRate > 0 ? baseRate * 3 : 0)
          .toDouble();
      final effectiveRateMinor = toMinor(effectiveRate);

      if (effectiveRateMinor <= 0) {
        // ✅ قاعدة «لا ليالٍ مجانية» (تأكيد المالك 2026-11-23): لا توجد
        // ليالٍ مجانية ولا يُراد لها وجود — السعر الفعلي الصفري شذوذ بيانات
        // (خصم ≥ السعر أو توزيع total يلغي الليلة). السلوك الصحيح ليس عبور
        // الليلة (منح مجانية صامتاً) ولا الإيقاف الصامت (السلوك القديم):
        // بل تسجيل شذوذ صريح + إيقاف معلن مسبب — والمستهلكون يعرضون
        // hasAnomaly في الواجهة والتقارير.
        anomalyNights.add(currentNight);
        anomalyReason ??=
            'ليلة ${Time.dateToString(currentNight)} بسعر فعلي صفر — '
            'قاعدة الفندق: لا ليالٍ مجانية؛ راجع الخصومات/السعر';
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
    // موعد المغادرة المخطط لا يوقف التراكم؛ وحده actualCheckout المسجل
    // يحدد نهاية الإقامة. وإذا كان وقت الخروج مسجلاً في المستقبل نستخدم الآن.
    final effectiveStayEnd =
        recordedCheckout != null && !recordedCheckout.isAfter(moment)
        ? recordedCheckout
        : moment;
    final actualNightsSpent = Time.nightsWithCutoff(
      checkin,
      checkout: effectiveStayEnd,
    );

    int consumedCostMinor = 0;
    DateTime consumedNight = firstHotelDay;
    for (int i = 0; i < actualNightsSpent && i < 3650; i++) {
      final key = Time.dateToString(consumedNight);
      final adjustment = adjMap[key] ?? 0.0;
      final nightRate = (baseRate + adjustment)
          .clamp(0.0, baseRate > 0 ? baseRate * 3 : 0)
          .toDouble();
      // ✅ قاعدة «لا ليالٍ مجانية»: ليلة مقضية فعلياً بسعر صفري تُضاف
      // بتكلفة صادقة (مجموع الأسعار = 0) لكنها تُعلن كشذوذ ولا تمر بصمت.
      if (toMinor(nightRate) <= 0) {
        final alreadyFlagged = anomalyNights.any(
          (n) => n.year == consumedNight.year && n.month == consumedNight.month && n.day == consumedNight.day,
        );
        if (!alreadyFlagged) {
          anomalyNights.add(consumedNight);
        }
        anomalyReason ??=
            'ليلة مقضية فعلياً ${Time.dateToString(consumedNight)} بسعر صفري — '
            'قاعدة الفندق: لا ليالٍ مجانية؛ راجع الخصومات/السعر';
      }
      consumedCostMinor += toMinor(nightRate);
      consumedNight = consumedNight.add(const Duration(days: 1));
    }

    final consumedCost = fromMinor(consumedCostMinor);

    // ─── الرصيد الفعلي = إجمالي المدفوع - تكلفة الأيام المقضية ───
    final effectiveBalance = fromMinor(totalPaidMinor - consumedCostMinor);

    // ─── تاريخ المغادرة التلقائي ───
    // currentNight يتقدم بعد كل ليلة مغطاة؛ لذلك يمثّل حدّ التغطية الحصري
    // التالي عند 14:01 بتوقيت الفندق، لا منتصف الليل التقويمي.
    final autoCheckout = currentNight;

    // ─── الأيام المتبقية حتى تاريخ المغادرة اليدوي ───
    final int manualNightsRemaining =
        (manualCheckout != null && manualCheckout.isAfter(moment))
        ? Time.nightsWithCutoff(moment, checkout: manualCheckout)
        : 0;

    // قارن عدد الليالي على نفس مرجع اليوم الفندقي من الدخول. مقارنة حدّ
    // التغطية (14:01) بوقت المغادرة الخام قد تحتسب جزءاً من اليوم كليلة
    // إضافية؛ والاحتساب من المغادرة إلى الحدّ يضيف ليلة شاملة زائفة.
    final plannedNights =
        manualCheckout != null && manualCheckout.isAfter(checkin)
        ? Time.nightsWithCutoff(checkin, checkout: manualCheckout)
        : 0;
    final int extraNightsBeyondManual = manualCheckout == null
        ? 0
        : (totalCoveredNights - plannedNights)
              .clamp(0, totalCoveredNights)
              .toInt();
    final bool isAutoExtended = extraNightsBeyondManual > 0;

    // ─── الفائض المالي بعد تغطية جميع الليالي ───
    // remainingBalanceMinor هو المبلغ غير المطبق بعد تغطية الليالي.
    // لا نحوله إلى صفر حتى يظهر الفائض/الرصيد الدائن في المصالحة.
    final surplusMinor = remainingBalanceMinor;
    final surplusAfterAllNights = fromMinor(surplusMinor);

    // ─── متوسط السعر الفعلي بعد التعديلات ───
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
      anomalyNights: List.unmodifiable(anomalyNights),
      anomalyReason: anomalyReason,
    );
  }

  /// حساب سريع فقط لتاريخ المغادرة التلقائي
  static DateTime calculateAutoCheckout(
    Booking booking, {
    double? nightlyRate,
    List<BookingPriceAdjustment>? priceAdjustments,
  }) {
    final result = calculate(
      booking,
      roomRate: nightlyRate,
      priceAdjustments: priceAdjustments,
    );
    return result.autoCheckoutDate;
  }

  /// حساب سريع لعدد الليالي المدفوعة
  static int calculatePaidNights(
    Booking booking, {
    double? nightlyRate,
    List<BookingPriceAdjustment>? priceAdjustments,
  }) {
    final result = calculate(
      booking,
      roomRate: nightlyRate,
      priceAdjustments: priceAdjustments,
    );
    return result.totalPaidNights;
  }

  /// ─── بناء خريطة التعديلات لكل ليلة ───
  /// يحوّل قائمة التعديلات إلى Map<dateString, adjustmentAmount>
  /// بحيث يمكن البlookup بسرعة أثناء المحاكاة اليومية.
  /// عامة ليستهلكها أيضاً تحقق «لا ليالٍ مجانية» عند إدخال التعديلات
  /// (BookingPriceAdjustmentService) بنفس منطق التوزيع — مصدر واحد.
  ///
  /// يدعم وضعين:
  ///   - per_night: يُطبّق المبلغ كاملاً على كل ليلة في النطاق (يشمل
  ///     الليالي المستقبلية — المحاكاة تحتاجها لتغطية صحيحة)
  ///   - total: ✅ موحد بمنطق المحرك (EnhancedBookingCalculationService.
  ///     _adjustmentsForNight): يُوزّع على ليالي الإقامة الفعلية داخل
  ///     النطاق فقط — من max(بداية التعديل، بداية الإقامة) إلى
  ///     min(نهاية التعديل، [distributionEnd]) بقسامة صحيحة دقيقة مع
  ///     توزيع الباقي على أول الليالي — لا امتداداً زوراً على أيام
  ///     النطاق التقويمي خارج الإقامة (بند 3.1).
  static Map<String, double> buildPerNightAdjustments(
    List<BookingPriceAdjustment>? adjustments,
    DateTime checkinDateOnly,
    DateTime? manualCheckout, {
    required DateTime distributionEnd,
  }) {
    if (adjustments == null || adjustments.isEmpty) {
      return const {};
    }

    final map = <String, double>{};

    for (final adj in adjustments) {
      final effectiveDate = DateTime.tryParse(adj.effectiveHotelDay);
      if (effectiveDate == null) {
        continue;
      }

      // تطبيع التواريخ إلى بداية اليوم فقط (تجنب مشاكل المنطقة الزمنية)
      final effDateOnly = DateTime(
        effectiveDate.year,
        effectiveDate.month,
        effectiveDate.day,
      );

      final endDate = adj.endHotelDay != null
          ? DateTime.tryParse(adj.endHotelDay!)
          : null;
      final adjEnd = endDate != null
          ? DateTime(endDate.year, endDate.month, endDate.day)
          : null;

      final isDiscount = adj.adjustmentType == 0;
      final rawAmount = adj.amount;

      if (adj.adjustmentMode == 'total') {
        // ✅ توزيع بمنطق المحرك: ليالي الإقامة الفعلية داخل النطاق فقط.
        final rangeStart = effDateOnly.isBefore(checkinDateOnly)
            ? checkinDateOnly
            : effDateOnly;
        final rangeEnd = (adjEnd != null && adjEnd.isBefore(distributionEnd))
            ? adjEnd
            : distributionEnd;
        int nightsInRange = rangeEnd.difference(rangeStart).inDays + 1;
        if (nightsInRange <= 0) {
          // التعديل خارج نطاق الإقامة — لا ليلة واحدة من الإقامة يتأثر به
          // (السلوك القديم كان يوزعه على أيام تقويمية خارج الإقامة).
          continue;
        }
        // ✅ حد أمان لمنع حلقات طويلة جداً (أقصى 365 يوم)
        if (nightsInRange > 365) {
          nightsInRange = 365;
        }

        // قسامة صحيحة دقيقة + الباقي لأول الليالي — نفس _adjustmentsForNight
        final int amountInt = rawAmount.round();
        final int basePart = amountInt ~/ nightsInRange;
        final int remainder = amountInt % nightsInRange;

        for (int i = 0; i < nightsInRange; i++) {
          final night = rangeStart.add(Duration(days: i));
          final key = Time.dateToString(night);
          final part = (basePart + (i < remainder ? 1 : 0)).toDouble();
          final signed = isDiscount ? -part : part;
          map[key] = (map[key] ?? 0.0) + signed;
        }
      } else {
        // per_night: يُطبّق المبلغ كاملاً على كل ليلة في نطاق التقويم
        // (يشمل المستقبلي) — بحد أمان سنة واحدة.
        final perNightEnd =
            adjEnd ?? manualCheckout ?? checkinDateOnly.add(const Duration(days: 365));
        DateTime night = effDateOnly;
        int safetyCounter = 0;
        while (!night.isAfter(perNightEnd) && safetyCounter < 365) {
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
  static StayBalanceResult _fallbackResult(
    Booking booking,
    DateTime moment, {
    List<DateTime> anomalyNights = const [],
    String? anomalyReason,
  }) {
    final checkin = DateTime.tryParse(booking.checkinDate) ?? moment;
    final checkout =
        (booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty)
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
      anomalyNights: anomalyNights,
      anomalyReason: anomalyReason,
    );
  }
}
