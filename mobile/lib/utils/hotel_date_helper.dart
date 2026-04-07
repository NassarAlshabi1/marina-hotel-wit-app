import 'dart:async';
import 'time.dart';

/// مساعد أيام الفندق (Hotel Day Logic)
///
/// نظام احتساب الأيام الفندقية يعتمد على ساعة بداية اليوم (14:00).
/// اليوم الفندقي يمتد من 14:00 حتى 14:00 من اليوم التالي.
/// أي تجاوز لساعة 14:00 = يبدأ يوم فندقي جديد.
class HotelDateHelper {
  /// ساعة بداية اليوم الفندقي
  static const int hotelStartHour = 14;

  // ─── تحويل التاريخ إلى يوم فندقي ──────────────────────────────

  /// تحويل أي DateTime إلى "مفتاح اليوم الفندقي" (Hotel Day Key).
  ///
  /// القاعدة:
  /// - إذا الوقت **بعد** 14:00:00 (مش لازم يساوي) → اليوم = نفس اليوم
  /// - إذا الوقت **عند أو قبل** 14:00:00 → اليوم = اليوم السابق
  ///
  /// ملاحظة مهمة: نستخدم `isAfter` (أكبر من وليس أكبر أو يساوي)
  /// لأن الساعة 14:00:00 بالضبط هي **نهاية** اليوم الفندقي السابق
  /// وليس بداية اليوم الجديد. هذا يتطابق مع الأمثلة:
  ///
  /// مثال 1: 01/01 14:01 → 02/01 14:00 = 1 يوم ✅
  /// مثال 2: 01/01 14:01 → 02/01 14:01 = 2 يوم ✅
  static DateTime getHotelDay(DateTime dateTime) {
    final cutoff = DateTime(
      dateTime.year,
      dateTime.month,
      dateTime.day,
      hotelStartHour,
    );
    if (dateTime.isAfter(cutoff)) {
      return DateTime(dateTime.year, dateTime.month, dateTime.day);
    } else {
      return DateTime(dateTime.year, dateTime.month, dateTime.day)
          .subtract(const Duration(days: 1));
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

  // ─── حساب عدد الليالي ──────────────────────────────────────────

  /// حساب عدد الليالي الفندقية بين تاريخ الدخول والخروج.
  ///
  /// يستخدم نفس خوارزمية [Time.nightsWithCutoff] المُثبتة:
  /// - الفرق بالأيام بين تاريخ الدخول والخروج
  /// - نفس اليوم = ليلة واحدة كحد أدنى
  /// - إذا وقت الخروج بعد 14:00:00 (حتى ثانية واحدة) = ليلة إضافية
  /// - عند 14:00:00 بالضبط = لا تُحتسب ليلة إضافية
  static int calculateNights({
    required DateTime checkIn,
    DateTime? checkOut,
  }) {
    return Time.nightsWithCutoff(
      checkIn,
      checkout: checkOut,
      cutoffHour: hotelStartHour,
    );
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
    );
    final effectiveStart =
        discountDayStart.isAfter(checkIn) ? discountDayStart : checkIn;
    if (!checkOut.isAfter(effectiveStart)) {
      return 0;
    }
    return calculateNights(checkIn: effectiveStart, checkOut: checkOut);
  }

  // ─── فحوصات الوقت ──────────────────────────────────────────────

  /// هل الوقت الحالي بعد ساعة بداية اليوم الفندقي؟
  /// true إذا الوقت > 14:00:00 (حتى ثانية واحدة إضافية).
  static bool isNowAfterCutoff() {
    final now = DateTime.now();
    return now.hour > hotelStartHour ||
        (now.hour == hotelStartHour &&
            (now.minute > 0 || now.second > 0));
  }

  /// هل الوقت المحدد بعد ساعة بداية اليوم الفندقي؟
  static bool isAfterCutoff(DateTime dateTime) {
    return dateTime.hour > hotelStartHour ||
        (dateTime.hour == hotelStartHour &&
            (dateTime.minute > 0 || dateTime.second > 0));
  }

  // ─── تحديث تلقائي ──────────────────────────────────────────────

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
}
