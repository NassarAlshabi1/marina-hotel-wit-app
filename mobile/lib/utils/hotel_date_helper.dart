import 'dart:async';
import 'package:flutter/foundation.dart';
import 'time.dart';

/// مساعد أيام الفندق (Hotel Day Logic)
///
/// نظام احتساب الأيام الفندقية يعتمد على ساعة بداية اليوم (14:01).
/// اليوم الفندقي يمتد من 14:01 حتى 14:00 من اليوم التالي.
/// أي تجاوز لساعة 14:01 = يبدأ يوم فندقي جديد.
///
/// يحتوي أيضاً على قائمة الحقول المحسوبة التي يجب:
/// - عدم مزامنتها إلى Appwrite (مصدر حقيقة محلي فقط)
/// - إعادة حسابها محلياً بعد كل عملية سحب من السيرفر
class HotelDateHelper {
  /// ساعة بداية اليوم الفندقي
  static const int hotelStartHour = 14;

  /// دقيقة بداية اليوم الفندقي
  static const int hotelStartMinute = 1;

  // ─── تحويل التاريخ إلى يوم فندقي ──────────────────────────────

  /// تحويل أي DateTime إلى "مفتاح اليوم الفندقي" (Hotel Day Key).
  ///
  /// القاعدة:
  /// - إذا الوقت **عند أو بعد** 14:01:00 → اليوم = نفس اليوم
  /// - إذا الوقت **قبل** 14:01:00 → اليوم = اليوم السابق
  ///
  /// ملاحظة مهمة: نستخدم `>=` (أكبر أو يساوي)
  /// لأن الساعة 14:01:00 بالضبط هي **بداية** اليوم الفندقي الجديد.
  /// الساعة 14:00:59 هي **نهاية** اليوم الفندقي السابق.
  ///
  /// مثال 1: 01/01 14:01 → 02/01 14:00 = 1 يوم ✅
  /// مثال 2: 01/01 14:01 → 02/01 14:01 = 2 يوم ✅
  static DateTime getHotelDay(DateTime dateTime) {
    final cutoff = DateTime(dateTime.year, dateTime.month, dateTime.day, hotelStartHour, hotelStartMinute);
    if (!dateTime.isBefore(cutoff)) {
      return DateTime(dateTime.year, dateTime.month, dateTime.day);
    } else {
      return DateTime(dateTime.year, dateTime.month, dateTime.day).subtract(const Duration(days: 1));
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
      final normalized = isoString.trim().contains('T') ? isoString.trim() : isoString.trim().replaceFirst(' ', 'T');
      final dt = DateTime.parse(normalized);
      return getHotelDayKey(dateTime: dt);
    } catch (_) {
      return getHotelDayKey();
    }
  }

  // ─── حساب عدد الليالي ──────────────────────────────────────────

  /// حساب عدد الليالي الفندقية بين تاريخ الدخول والخروج.
  ///
  /// يستخدم نفس خوارزمية [Time.nightsWithCutoff] المُثبتة:
  /// - الفرق بالأيام بين تاريخ الدخول والخروج
  /// - نفس اليوم = ليلة واحدة كحد أدنى
  /// - إذا وقت الخروج بعد 14:00:00 (حتى ثانية واحدة) = ليلة إضافية
  /// - عند 14:00:00 بالضبط = لا تُحتسب ليلة إضافية
  static int calculateNights({required DateTime checkIn, DateTime? checkOut}) {
    return Time.nightsWithCutoff(checkIn, checkout: checkOut);
  }

  /// حساب عدد الليالي مع مراعاة تاريخ بداية الخصم.
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
      hotelStartMinute,
    );
    final effectiveStart = discountDayStart.isAfter(checkIn) ? discountDayStart : checkIn;
    if (!checkOut.isAfter(effectiveStart)) {
      return 0;
    }
    return calculateNights(checkIn: effectiveStart, checkOut: checkOut);
  }

  // ─── فحوصات الوقت ──────────────────────────────────────────────

  /// هل الوقت الحالي بعد ساعة بداية اليوم الفندقي؟
  /// true إذا الوقت >= 14:01:00.
  static bool isNowAfterCutoff() {
    final now = DateTime.now();
    return now.hour > hotelStartHour || (now.hour == hotelStartHour && now.minute >= hotelStartMinute);
  }

  /// هل الوقت المحدد بعد ساعة بداية اليوم الفندقي؟
  static bool isAfterCutoff(DateTime dateTime) {
    return dateTime.hour > hotelStartHour || (dateTime.hour == hotelStartHour && dateTime.minute >= hotelStartMinute);
  }

  // ─── تحديث تلقائي ──────────────────────────────────────────────

  /// الفترة المتبقية حتى بداية اليوم الفندقي التالي (14:01).
  static Duration timeUntilNextHotelDay() {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hotelStartHour, hotelStartMinute);
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
    // نضيف ثانية واحدة للأمان لضمان تجاوز الساعة 14:01
    final delay = until + const Duration(seconds: 1);
    return Timer(delay, () {
      onTick();
      // إعادة ضبط المؤقت لليوم التالي
      createAutoRefreshTimer(onTick);
    });
  }

  /// إنشاء Timer دوري كل 30 ثانية (للشاشات التي تحتاج دقة أعلى).
  static Timer createPeriodicRefreshTimer(VoidCallback onTick) {
    return Timer.periodic(const Duration(seconds: 30), (_) => onTick());
  }

  // ─── الحقول المحسوبة (لا تُزامن إلى Appwrite) ───────────────

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
    'stayDurationIso', // حساب مدة البقاء — يختلف حسب وقت الاستعلام
    'lastNightEpoch', // حساب آخر ليلة — يختلف حسب وقت الاستعلام
    'isOverdue', // يعتمد على الوقت الحالي
    'needsCheckoutReview', // يعتمد على الوقت الحالي
  };

  /// فحص هل حقل معين في الحجوزات هو حقل محسوب (لا يُزامن).
  static bool isBookingComputedField(String fieldName) {
    return bookingComputedFields.contains(fieldName);
  }

  /// تصفية بيانات الحجز من الحقول المحسوبة قبل الرفع إلى Appwrite.
  ///
  /// يُستدعى من `_sanitizePayload` في Delta Sync.
  static Map<String, dynamic> stripComputedFieldsForEntity(String entity, Map<String, dynamic> payload) {
    if (entity != 'bookings') {
      return payload;
    }

    final result = Map<String, dynamic>.from(payload);
    bookingComputedFields.forEach(result.remove);
    return result;
  }
}
