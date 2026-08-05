import 'time.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// محرك الوقت الفندقي — المصدر الوحيد للحسابات
///
/// **مبدأ التصميم:**
/// - لا يخزن أي قيمة — يحسب فقط
/// - كل حسابات الليالي والمبالغ تمر من هنا
/// - يُستخدم مباشرة من UI عبر BookingComputedStreamService
/// - لا يعتمد على أي حقل محسوب في قاعدة البيانات
///
/// **قاعدة 14:01:**
/// - اليوم الفندقي يمتد من 14:01 حتى 14:00 من اليوم التالي
/// - check-in قبل 14:01 = يوم فندقي سابق
/// - check-in في 14:01 أو بعد = يوم فندقي جديد
/// - checkout بعد 14:01 = ليلة إضافية
class HotelTimeEngine {
  HotelTimeEngine._();

  // ═══════════════════════════════════════════════════════════════
  // ثوابت
  // ═══════════════════════════════════════════════════════════════

  /// ساعة بداية اليوم الفندقي (14)
  static const int boundaryHour = 14;

  /// دقيقة بداية اليوم الفندقي (01)
  /// اليوم الفندقي يبدأ الساعة 14:01 وليس 14:00
  static const int boundaryMinute = 1;

  /// دالة لتحديد بداية ونهاية اليوم الفندقي لتاريخ معين.
  /// اليوم الفندقي يبدأ الساعة 14:01 وينتهي في اليوم التالي الساعة 14:00:59.
  static Map<String, DateTime> getHotelDayRange(DateTime date) {
    DateTime hotelDayStart;
    DateTime hotelDayEnd;

    // إذا كان الوقت الحالي قبل الساعة 14:01
    if (date.hour < boundaryHour ||
        (date.hour == boundaryHour && date.minute < boundaryMinute)) {
      // اليوم الفندقي بدأ أمس الساعة 14:01
      hotelDayStart = DateTime(
        date.year,
        date.month,
        date.day - 1,
        boundaryHour,
        boundaryMinute,
      );
      // وينتهي اليوم الساعة 14:00:59
      hotelDayEnd = DateTime(
        date.year,
        date.month,
        date.day,
        boundaryHour,
        0,
        59,
        999,
      );
    } else {
      // إذا كان الوقت الحالي بعد أو يساوي الساعة 14:01
      // اليوم الفندقي بدأ اليوم الساعة 14:01
      hotelDayStart = DateTime(
        date.year,
        date.month,
        date.day,
        boundaryHour,
        boundaryMinute,
      );
      // وينتهي غداً الساعة 14:00:59
      hotelDayEnd = DateTime(
        date.year,
        date.month,
        date.day + 1,
        boundaryHour,
        0,
        59,
        999,
      );
    }

    return {'start': hotelDayStart, 'end': hotelDayEnd};
  }

  // ═══════════════════════════════════════════════════════════════
  // تحويل التاريخ إلى يوم فندقي
  // ═══════════════════════════════════════════════════════════════

  /// تحويل أي DateTime إلى "يوم فندقي" (Date فقط، بدون وقت).
  ///
  /// القاعدة:
  /// - الوقت >= 14:01:00 → نفس اليوم (يوم فندقي جديد)
  /// - الوقت < 14:01:00 → اليوم السابق
  ///
  /// 14:00:59 بالضبط = نهاية اليوم الفندقي الحالي (يعود لليوم السابق).
  /// 14:01:00 = بداية اليوم الفندقي الجديد.
  ///
  /// مثال:
  /// - 2025-01-15 13:59 → 2025-01-14 (يوم فندقي سابق)
  /// - 2025-01-15 14:00 → 2025-01-14 (نهاية اليوم الفندقي 14)
  /// - 2025-01-15 14:01 → 2025-01-15 (بداية يوم فندقي جديد)
  static DateTime getHotelDay(DateTime dt) {
    final isAfterBoundary =
        dt.hour > boundaryHour ||
        (dt.hour == boundaryHour && dt.minute >= boundaryMinute);
    if (isAfterBoundary) {
      return DateTime(dt.year, dt.month, dt.day);
    } else {
      final prev = dt.subtract(const Duration(days: 1));
      return DateTime(prev.year, prev.month, prev.day);
    }
  }

  /// مفتاح اليوم الفندقي كنص YYYY-MM-DD.
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
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in hotel_time_engine.dart: ');
      return getHotelDayKey();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // حساب الليالي (المصدر الوحيد)
  // ═══════════════════════════════════════════════════════════════

  /// حساب عدد الليالي الفندقية بين تاريخ الدخول والخروج.
  ///
  /// **هذه هي الدالة الوحيدة لحساب الليالي في التطبيق كله.**
  ///
  /// القواعد:
  /// - نفس اليوم = ليلة واحدة كحد أدنى
  /// - checkout بعد 14:01 (حتى دقيقة واحدة) = ليلة إضافية
  /// - checkout عند 14:00:59 بالضبط = لا تُحتسب ليلة إضافية
  ///
  /// مثال:
  /// - 01/01 14:01 → 02/01 14:01 = 2 ليالي
  /// - 01/01 14:01 → 02/01 14:00 = 1 ليلة
  /// - 01/01 14:01 → (الآن بعد 3 أيام) = 3 ليالي
  static int calculateDays(DateTime checkIn, {DateTime? checkOut}) {
    return Time.nightsWithCutoff(checkIn, checkout: checkOut);
  }

  /// حساب الليالي مع مراعاة تاريخ بداية الخصم.
  ///
  /// يُستخدم عند وجود خصم يبدأ في تاريخ محدد.
  static int calculateDaysWithDiscount({
    required DateTime checkIn,
    required DateTime checkOut,
    DateTime? discountStartDate,
  }) {
    if (discountStartDate == null) {
      return calculateDays(checkIn, checkOut: checkOut);
    }

    final discountDayStart = DateTime(
      discountStartDate.year,
      discountStartDate.month,
      discountStartDate.day,
      boundaryHour,
      boundaryMinute,
    );
    final effectiveStart = discountDayStart.isAfter(checkIn)
        ? discountDayStart
        : checkIn;
    if (!checkOut.isAfter(effectiveStart)) {
      return 0;
    }
    return calculateDays(effectiveStart, checkOut: checkOut);
  }

  // ═══════════════════════════════════════════════════════════════
  // فحوصات الوقت
  // ═══════════════════════════════════════════════════════════════

  /// هل الوقت الحالي بعد ساعة بداية اليوم الفندقي؟
  /// true إذا الوقت >= 14:01:00.
  static bool isNowAfterCutoff() {
    final now = DateTime.now();
    return now.hour > boundaryHour ||
        (now.hour == boundaryHour && now.minute >= boundaryMinute);
  }

  /// هل الوقت المحدد بعد ساعة بداية اليوم الفندقي؟
  static bool isAfterCutoff(DateTime dateTime) {
    return dateTime.hour > boundaryHour ||
        (dateTime.hour == boundaryHour && dateTime.minute >= boundaryMinute);
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

  // ═══════════════════════════════════════════════════════════════
  // فحص الحالة
  // ═══════════════════════════════════════════════════════════════

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
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in hotel_time_engine.dart: ');
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
  // التوافق مع HotelDateHelper (لا يكسر الكود القديم)
  // ═══════════════════════════════════════════════════════════════

  /// حساب عدد الليالي (واجهة توافقية مع HotelDateHelper).
  static int calculateNights({required DateTime checkIn, DateTime? checkOut}) {
    return calculateDays(checkIn, checkOut: checkOut);
  }

  /// الفترة المتبقية حتى بداية اليوم الفندقي التالي (14:01).
  static Duration timeUntilNextHotelDay() {
    final now = DateTime.now();
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      boundaryHour,
      boundaryMinute,
    );
    if (!now.isBefore(next)) {
      next = next.add(const Duration(days: 1));
    }
    return next.difference(now);
  }

  // ═══════════════════════════════════════════════════════════════
  // حقول لا تُزامن (مصدر حقيقة محلي فقط)
  // ═══════════════════════════════════════════════════════════════

  /// الحقول المحسوبة التي يجب عدم مزامنتها إلى Appwrite.
  ///
  /// تُستخدم في:
  /// - Appwrite Delta Sync: حذفها قبل الدفع (push)
  /// - BookingComputedStreamService: تجاهلها عند القراءة
  static const bookingComputedFields = <String>{
    'calculatedNights',
    'totalNightsCached',
    'stayDurationIso',
    'lastNightEpoch',
    'isOverdue',
    'needsCheckoutReview',
    'totalDueCached',
    'totalPaidCached',
    'remainingBalanceCached',
    'isFullyPaid',
    'hotelDayCheckin',
    'hotelDayCheckout',
  };

  /// فحص هل حقل معين هو حقل محسوب.
  static bool isBookingComputedField(String fieldName) {
    return bookingComputedFields.contains(fieldName);
  }

  /// تصفية بيانات الحجز من الحقول المحسوبة قبل الرفع.
  static Map<String, dynamic> stripComputedFields(
    Map<String, dynamic> payload,
  ) {
    final result = Map<String, dynamic>.from(payload);
    bookingComputedFields.forEach(result.remove);
    return result;
  }
}
