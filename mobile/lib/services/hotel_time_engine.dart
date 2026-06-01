/// محرك الوقت الفندقي (نسخة الخدمات) — يفوض جميع الحسابات إلى HotelDateHelper
///
/// **هذه الفئة موجودة للتوافق مع الكود القائم فقط.**
/// المصدر الوحيد للحسابات هو [HotelDateHelper] في lib/utils/.
///
/// جميع الاستدعاءات تُحوّل مباشرة إلى HotelDateHelper
/// لضمان ثبات الحسابات في مكان واحد.
library;

import '../utils/hotel_date_helper.dart';

@Deprecated('استخدم HotelDateHelper بدلاً من HotelTimeEngine — المصدر الوحيد للحسابات')
class HotelTimeEngine {
  HotelTimeEngine._();

  /// ساعة بداية اليوم الفندقي (14:00)
  static const int boundaryHour = HotelDateHelper.boundaryHour;

  /// تحويل أي DateTime إلى "يوم فندقي".
  static DateTime getHotelDay(DateTime dt) =>
      HotelDateHelper.getHotelDay(dt);

  /// مفتاح اليوم الفندقي كنص YYYY-MM-DD.
  static String getHotelDayKey({DateTime? dateTime}) =>
      HotelDateHelper.getHotelDayKey(dateTime: dateTime);

  /// تحويل ISO string إلى مفتاح يوم فندقي.
  static String getHotelDayKeyFromIso(String? isoString) =>
      HotelDateHelper.getHotelDayKeyFromIso(isoString);

  /// تحويل تاريخ تقويمي (بدون وقت) إلى مفتاح يوم فندقي.
  /// للنصوص من منتقي التواريخ — يعامل التاريخ كـ 14:00:01 (بعد نقطة القطع).
  static String getHotelDayKeyFromDate(String? dateString) =>
      HotelDateHelper.getHotelDayKeyFromDate(dateString);

  /// تحديد بداية ونهاية اليوم الفندقي.
  static Map<String, DateTime> getHotelDayRange(DateTime date) =>
      HotelDateHelper.getHotelDayRange(date);

  /// حساب عدد الليالي الفندقية.
  static int calculateDays(DateTime checkIn, {DateTime? checkOut}) =>
      HotelDateHelper.calculateDays(checkIn, checkOut: checkOut);

  /// حساب الليالي مع خصم.
  static int calculateDaysWithDiscount({
    required DateTime checkIn,
    required DateTime checkOut,
    DateTime? discountStartDate,
  }) =>
      HotelDateHelper.calculateDaysWithDiscount(
        checkIn: checkIn,
        checkOut: checkOut,
        discountStartDate: discountStartDate,
      );

  /// حساب عدد الليالي.
  static int calculateNights({
    required DateTime checkIn,
    DateTime? checkOut,
  }) =>
      HotelDateHelper.calculateNights(checkIn: checkIn, checkOut: checkOut);

  /// حساب المبلغ الإجمالي = الليالي × سعر الغرفة.
  static double calculateTotal({
    required int days,
    required double roomPrice,
    double discount = 0,
    String discountType = 'per_night',
  }) =>
      HotelDateHelper.calculateTotal(
        days: days,
        roomPrice: roomPrice,
        discount: discount,
        discountType: discountType,
      );

  /// حساب المبلغ الإجمالي (نسخة الأعداد الصحيحة).
  static int calculateTotalAmount(
    int pricePerNight,
    DateTime checkIn, {
    DateTime? checkOut,
    int discount = 0,
  }) =>
      HotelDateHelper.calculateTotalAmount(
        pricePerNight,
        checkIn,
        checkOut: checkOut,
        discount: discount,
      );

  /// هل الوقت الحالي بعد ساعة بداية اليوم الفندقي؟
  static bool isNowAfterCutoff() => HotelDateHelper.isNowAfterCutoff();

  /// هل الوقت المحدد بعد ساعة بداية اليوم الفندقي؟
  static bool isAfterCutoff(DateTime dateTime) =>
      HotelDateHelper.isAfterCutoff(dateTime);

  /// هل الحجز متأخر عن الخروج؟
  static bool isOverdue({
    required String status,
    required String? checkoutDate,
  }) =>
      HotelDateHelper.isOverdue(status: status, checkoutDate: checkoutDate);

  /// هل يحتاج مراجعة الخروج؟
  static bool needsCheckoutReview({
    required bool isOverdue,
    required double remainingBalance,
  }) =>
      HotelDateHelper.needsCheckoutReview(
        isOverdue: isOverdue,
        remainingBalance: remainingBalance,
      );

  /// لحظة البداية (14:00:00) لليوم الفندقي.
  static DateTime hotelDayStart(DateTime value) =>
      HotelDateHelper.hotelDayStart(value);

  /// لحظة النهاية (14:00:00 من اليوم التالي) لليوم الفندقي.
  static DateTime hotelDayEnd(DateTime value) =>
      HotelDateHelper.hotelDayEnd(value);

  /// تنسيق تاريخ كنص yyyy-MM-dd.
  static String formatHotelDay(DateTime date) =>
      HotelDateHelper.formatHotelDay(date);

  /// الفترة المتبقية حتى بداية اليوم الفندقي التالي.
  static Duration timeUntilNextHotelDay() =>
      HotelDateHelper.timeUntilNextHotelDay();

  /// الحقول المحسوبة التي لا تُزامن.
  static const bookingComputedFields = HotelDateHelper.bookingComputedFields;

  /// فحص هل حقل معين هو حقل محسوب.
  static bool isBookingComputedField(String fieldName) =>
      HotelDateHelper.isBookingComputedField(fieldName);

  /// تصفية بيانات الحجز من الحقول المحسوبة.
  static Map<String, dynamic> stripComputedFields(
    Map<String, dynamic> payload,
  ) =>
      HotelDateHelper.stripComputedFields(payload);
}
