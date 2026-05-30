import 'dart:async';
import 'package:flutter/foundation.dart';
import 'time.dart';

/// مساعد أيام الفندق — المصدر الوحيد لجميع الحسابات الفندقية
///
/// نظام احتساب الأيام الفندقية يعتمد على ساعة بداية اليوم (14:00).
/// اليوم الفندقي يمتد من 14:00 حتى 14:00 من اليوم التالي.
/// أي تجاوز لساعة 14:00 = يبدأ يوم فندقي جديد.
///
/// **مبدأ التصميم:**
/// - لا يخزن أي قيمة — يحسب فقط
/// - كل حسابات الليالي والمبالغ تمر من هنا
/// - يُستخدم مباشرة من UI والخدمات
/// - لا يعتمد على أي حقل محسوب في قاعدة البيانات
///
/// يحتوي أيضاً على قائمة الحقول المحسوبة التي يجب:
/// - عدم مزامنتها إلى Appwrite (مصدر حقيقة محلي فقط)
/// - إعادة حسابها محلياً بعد كل عملية سحب من السيرفر
class HotelDateHelper {
  HotelDateHelper._();

  // ═══════════════════════════════════════════════════════════════
  // ثوابت
  // ═══════════════════════════════════════════════════════════════

  /// ساعة بداية اليوم الفندقي (14:00)
  static const int hotelStartHour = 14;

  /// اسم بديل للتوافق مع HotelTimeEngine
  static const int boundaryHour = hotelStartHour;

  // ═══════════════════════════════════════════════════════════════
  // تحويل التاريخ إلى يوم فندقي
  // ═══════════════════════════════════════════════════════════════

  /// تحويل أي DateTime إلى "يوم فندقي" (Date فقط، بدون وقت).
  ///
  /// القاعدة:
  /// - إذا الوقت **بعد** 14:00:00 (بدقة الثانية) → اليوم = نفس اليوم
  /// - إذا الوقت **عند أو قبل** 14:00:00 → اليوم = اليوم السابق
  ///
  /// ملاحظة مهمة: نستخدم `isAfter` (أكبر من وليس أكبر أو يساوي)
  /// لأن الساعة 14:00:00 بالضبط هي **نهاية** اليوم الفندقي السابق
  /// وليس بداية اليوم الجديد.
  ///
  /// مثال 1: 01/01 14:01 → 02/01 14:00 = 1 يوم
  /// مثال 2: 01/01 14:01 → 02/01 14:01 = 2 يوم
  /// مثال 3: 2025-01-15 13:59 → 2025-01-14 (يوم فندقي سابق)
  /// مثال 4: 2025-01-15 14:00 → 2025-01-14 (نهاية اليوم الفندقي 14)
  /// مثال 5: 2025-01-15 14:01 → 2025-01-15 (بداية يوم فندقي جديد)
  static DateTime getHotelDay(DateTime dateTime) {
    final dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);
    if (isAfterCutoff(dateTime)) {
      return dateOnly;
    } else {
      return dateOnly.subtract(const Duration(days: 1));
    }
  }

  /// إرجاع مفتاح اليوم الفندقي كنص (YYYY-MM-DD).
  static String getHotelDayKey({DateTime? dateTime}) {
    final dt = dateTime ?? DateTime.now();
    return Time.dateToString(getHotelDay(dt));
  }

  /// تحويل ISO string إلى مفتاح يوم فندقي.
  static String getHotelDayKeyFromIso(String? isoString) {
    if (isoString == null || isoString.trim().isEmpty) {
      return getHotelDayKey();
    }
    try {
      final normalized = isoString.trim().contains('T')
          ? isoString.trim()
          : isoString.trim().replaceFirst(' ', 'T');
      final dt = DateTime.parse(normalized);
      return getHotelDayKey(dateTime: dt);
    } catch (_) {
      return getHotelDayKey();
    }
  }

  /// دالة لتحديد بداية ونهاية اليوم الفندقي لتاريخ معين.
  /// اليوم الفندقي يبدأ الساعة 14:00 وينتهي في اليوم التالي الساعة 13:59:59.
  static Map<String, DateTime> getHotelDayRange(DateTime date) {
    DateTime hotelDayStart;
    DateTime hotelDayEnd;

    if (date.hour < boundaryHour) {
      hotelDayStart = DateTime(date.year, date.month, date.day - 1, boundaryHour);
      hotelDayEnd = DateTime(date.year, date.month, date.day, boundaryHour - 1, 59, 59, 999);
    } else {
      hotelDayStart = DateTime(date.year, date.month, date.day, boundaryHour);
      hotelDayEnd = DateTime(date.year, date.month, date.day + 1, boundaryHour - 1, 59, 59, 999);
    }

    return {
      'start': hotelDayStart,
      'end': hotelDayEnd,
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // حساب عدد الليالي — المصدر الوحيد
  // ═══════════════════════════════════════════════════════════════

  /// حساب عدد الليالي الفندقية بين تاريخ الدخول والخروج.
  ///
  /// **هذه هي الدالة الوحيدة لحساب الليالي في التطبيق كله.**
  ///
  /// يستخدم نفس خوارزمية [Time.nightsWithCutoff] المُثبتة:
  /// - نفس اليوم = ليلة واحدة كحد أدنى
  /// - إذا وقت الخروج بعد 14:00:00 (حتى ثانية واحدة) = ليلة إضافية
  /// - عند 14:00:00 بالضبط = لا تُحتسب ليلة إضافية
  ///
  /// مثال:
  /// - 01/01 14:01 → 02/01 14:00 = 1 ليلة
  /// - 01/01 14:01 → 02/01 14:01 = 2 ليالٍ
  /// - 01/01 14:01 → (الآن بعد 3 أيام) = 3 ليالٍ
  static int calculateNights({
    required DateTime checkIn,
    DateTime? checkOut,
  }) {
    return Time.nightsWithCutoff(
      checkIn,
      checkout: checkOut,
    );
  }

  /// حساب عدد الأيام — واجهة توافقية مع HotelTimeEngine.calculateDays
  /// نفس calculateNights بالضبط لكن باسم مختلف.
  static int calculateDays(DateTime checkIn, {DateTime? checkOut}) {
    return calculateNights(checkIn: checkIn, checkOut: checkOut);
  }

  /// حساب عدد الليالي مع مراعاة تاريخ بداية الخصم.
  ///
  /// يُستخدم عند وجود خصم يبدأ في تاريخ محدد.
  static int calculateNightsWithDiscount({
    required DateTime checkIn,
    required DateTime checkOut,
    DateTime? discountStartDate,
  }) {
    if (discountStartDate == null) {
      return calculateNights(checkIn: checkIn, checkOut: checkOut);
    }

    final discountDayStart = DateTime(
      discountStartDate.year,
      discountStartDate.month,
      discountStartDate.day,
      hotelStartHour,
    );
    final effectiveStart =
        discountDayStart.isAfter(checkIn) ? discountDayStart : checkIn;
    if (!checkOut.isAfter(effectiveStart)) {
      return 0;
    }
    return calculateNights(checkIn: effectiveStart, checkOut: checkOut);
  }

  /// حساب الأيام مع خصم — واجهة توافقية مع HotelTimeEngine
  static int calculateDaysWithDiscount({
    required DateTime checkIn,
    required DateTime checkOut,
    DateTime? discountStartDate,
  }) {
    return calculateNightsWithDiscount(
      checkIn: checkIn,
      checkOut: checkOut,
      discountStartDate: discountStartDate,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // الحسابات المالية (الواجهة الموحدة)
  // ═══════════════════════════════════════════════════════════════

  /// حساب المبلغ الإجمالي = الليالي × سعر الغرفة.
  ///
  /// [roomPrice] يُؤخذ من جدول الغرف (rooms.price) عبر roomNumber.
  static double calculateTotal({
    required int days,
    required double roomPrice,
    double discount = 0,
    String discountType = 'per_night',
  }) {
    if (days <= 0 || roomPrice <= 0) {
      return 0;
    }

    double total = days * roomPrice;

    if (discount > 0) {
      if (discountType == 'total') {
        total -= discount;
      } else {
        // per_night: خصم لكل ليلة
        total -= discount * days;
      }
    }

    return total < 0 ? 0 : total;
  }

  /// حساب المبلغ الإجمالي (نسخة الأعداد الصحيحة).
  ///
  /// - [pricePerNight] – سعر الليلة (يجب أن يكون غير سالب).
  /// - [checkIn] – تاريخ الدخول.
  /// - [checkOut] – تاريخ المغادرة (افتراضي = الآن).
  /// - [discount] – مبلغ الخصم (افتراضي = 0).
  ///
  /// القيمة المرجعة لا تكون سالبة أبداً (أقل قيمة = 0).
  static int calculateTotalAmount(
    int pricePerNight,
    DateTime checkIn, {
    DateTime? checkOut,
    int discount = 0,
  }) {
    final days = calculateDays(checkIn, checkOut: checkOut);
    final total = (days * pricePerNight) - discount;
    return total < 0 ? 0 : total;
  }

  // ═══════════════════════════════════════════════════════════════
  // فحوصات الوقت
  // ═══════════════════════════════════════════════════════════════

  /// هل الوقت الحالي بعد ساعة بداية اليوم الفندقي؟
  /// true إذا الوقت > 14:00:00 (حتى ثانية واحدة إضافية).
  static bool isNowAfterCutoff() {
    final now = DateTime.now();
    return now.hour > hotelStartHour ||
        (now.hour == hotelStartHour &&
            (now.minute > 0 || now.second > 0));
  }

  /// هل الوقت المحدد بعد ساعة بداية اليوم الفندقي؟
  ///
  /// تتحقق بدقة الثانية (تتجاهل الجزء من الألف من الثانية).
  ///
  /// أمثلة:
  /// - `14:00:00` → `false`
  /// - `14:00:01` → `true`
  /// - `13:59:59` → `false`
  /// - `15:00:00` → `true`
  static bool isAfterCutoff(DateTime dateTime) {
    return dateTime.hour > hotelStartHour ||
        (dateTime.hour == hotelStartHour &&
            (dateTime.minute > 0 || dateTime.second > 0));
  }

  /// هل الحجز متأخر عن الخروج؟
  /// حجز نشط وتجاوز تاريخ الخروج المحدد.
  static bool isOverdue({
    required String status,
    required String? checkoutDate,
  }) {
    if (status != 'نشط') {
      return false;
    }
    if (checkoutDate == null || checkoutDate.isEmpty) {
      return false;
    }

    try {
      final checkout = DateTime.parse(
        checkoutDate.contains('T')
            ? checkoutDate
            : checkoutDate.replaceFirst(' ', 'T'),
      );
      return DateTime.now().isAfter(checkout);
    } catch (_) {
      return false;
    }
  }

  /// هل يحتاج مراجعة الخروج؟
  /// إما متأخر أو لديه رصيد متبقي.
  static bool needsCheckoutReview({
    required bool isOverdue,
    required double remainingBalance,
  }) {
    return isOverdue || remainingBalance > 0;
  }

  // ═══════════════════════════════════════════════════════════════
  // فترات اليوم الفندقي
  // ═══════════════════════════════════════════════════════════════

  /// إرجاع لحظة البداية (14:00:00) لليوم الفندقي الذي يقع فيه [value].
  static DateTime hotelDayStart(DateTime value) {
    final hotelDay = getHotelDay(value);
    return DateTime(hotelDay.year, hotelDay.month, hotelDay.day, boundaryHour);
  }

  /// إرجاع لحظة النهاية (14:00:00 من اليوم التالي) لليوم الفندقي الذي يقع فيه [value].
  static DateTime hotelDayEnd(DateTime value) {
    final hotelDay = getHotelDay(value);
    return DateTime(hotelDay.year, hotelDay.month, hotelDay.day + 1, boundaryHour);
  }

  // ═══════════════════════════════════════════════════════════════
  // تنسيق التواريخ
  // ═══════════════════════════════════════════════════════════════

  /// تنسيق تاريخ كنص yyyy-MM-dd مع حشو الأصفار.
  ///
  /// ```dart
  /// HotelDateHelper.formatHotelDay(DateTime(2022, 1, 5))
  /// // => '2022-01-05'
  /// ```
  static String formatHotelDay(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  // ═══════════════════════════════════════════════════════════════
  // تحديث تلقائي
  // ═══════════════════════════════════════════════════════════════

  /// الفترة المتبقية حتى بداية اليوم الفندقي التالي (14:00).
  static Duration timeUntilNextHotelDay() {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hotelStartHour);
    if (!now.isBefore(next)) {
      next = next.add(const Duration(days: 1));
    }
    return next.difference(now);
  }

  /// إنشاء Timer يُطلق setState عند عبور ساعة 14:00.
  ///
  /// الاستخدام في StatefulWidget:
  /// ```dart
  /// Timer? _hotelDayTimer;
  ///
  /// @override
  /// void initState() {
  ///   super.initState();
  ///   _hotelDayTimer = HotelDateHelper.createAutoRefreshTimer(() {
  ///     if (mounted) setState(() {});
  ///   });
  /// }
  ///
  /// @override
  /// void dispose() {
  ///   _hotelDayTimer?.cancel();
  ///   super.dispose();
  /// }
  /// ```
  static Timer createAutoRefreshTimer(VoidCallback onTick) {
    final until = timeUntilNextHotelDay();
    // نضيف ثانية واحدة للأمان لضمان تجاوز الساعة 14:00
    final delay = until + const Duration(seconds: 1);
    return Timer(delay, () {
      onTick();
      // إعادة ضبط المؤقت لليوم التالي
      createAutoRefreshTimer(onTick);
    });
  }

  /// إنشاء Timer دوري كل 30 ثانية (للشاشات التي تحتاج دقة أعلى).
  static Timer createPeriodicRefreshTimer(VoidCallback onTick) {
    return Timer.periodic(
      const Duration(seconds: 30),
      (_) => onTick(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // الحقول المحسوبة (لا تُزامن إلى Appwrite)
  // ═══════════════════════════════════════════════════════════════

  /// الحقول المحسوبة في جدول الحجوزات (bookings) — لا تُزامن إلى Appwrite.
  ///
  /// هذه الحقول تعتمد على الوقت الحالي وتختلف من جهاز لآخر،
  /// لذا لا تُدفع إلى Appwrite ويُعاد حسابها محلياً بعد كل سحب.
  ///
  /// ⚠️ تم إزالة الحقول التالية من هذه القائمة لأنها موجودة في Appwrite
  /// Cloud مع بيانات ويجب مزامنتها بين الأجهزة (موجودة في _bookingToRemote):
  /// - calculatedNights, totalNightsCached, totalDueCached, totalPaidCached,
  ///   remainingBalanceCached, isFullyPaid, hotelDayCheckin, hotelDayCheckout
  static const bookingComputedFields = <String>{
    // ── حقول ديناميكية تعتمد على الوقت الحالي — لا تُزامن ──
    'stayDurationIso',   // حساب مدة البقاء — يختلف حسب وقت الاستعلام
    'lastNightEpoch',    // حساب آخر ليلة — يختلف حسب وقت الاستعلام
    'isOverdue',         // يعتمد على الوقت الحالي
    'needsCheckoutReview', // يعتمد على الوقت الحالي
  };

  /// فحص هل حقل معين في الحجوزات هو حقل محسوب (لا يُزامن).
  static bool isBookingComputedField(String fieldName) {
    return bookingComputedFields.contains(fieldName);
  }

  /// تصفية بيانات الحجز من الحقول المحسوبة قبل الرفع إلى Appwrite.
  ///
  /// يُستدعى من `_sanitizePayload` في Delta Sync.
  static Map<String, dynamic> stripComputedFieldsForEntity(
    String entity,
    Map<String, dynamic> payload,
  ) {
    if (entity != 'bookings') {
      return payload;
    }

    final result = Map<String, dynamic>.from(payload);
    bookingComputedFields.forEach(result.remove);
    return result;
  }

  /// تصفية بيانات الحجز من الحقول المحسوبة — واجهة توافقية مع HotelTimeEngine
  static Map<String, dynamic> stripComputedFields(
    Map<String, dynamic> payload,
  ) {
    return stripComputedFieldsForEntity('bookings', payload);
  }
}
