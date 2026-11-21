import 'hotel_timezone.dart';

class Time {
  static const int earlyCheckinGraceHour = 11;

  /// حد اليوم الفندقي الموحد: يبدأ اليوم الجديد عند 14:01 بالضبط.
  static const int hotelDayBoundaryHour = 14;
  static const int hotelDayBoundaryMinute = 1;

  static int nowEpoch() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  static String nowIso() => DateTime.now().toIso8601String();
  static String nowPaymentIso() => HotelTimezone.nowPaymentTimestamp();

  static String paymentIsoFromInstant(DateTime instant) =>
      HotelTimezone.paymentTimestampFromInstant(instant);

  static String nowDateString() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String dateToString(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  static String hotelDayKey({
    DateTime? now,
    int cutoffHour = hotelDayBoundaryHour,
    int cutoffMinute = hotelDayBoundaryMinute,
  }) {
    final base = now == null
        ? HotelTimezone.now()
        : HotelTimezone.toHotelDateTime(now);
    final shifted = base.subtract(
      Duration(hours: cutoffHour, minutes: cutoffMinute),
    );
    return dateToString(shifted);
  }

  static String hotelDayKeyFromIso(
    String? isoString, {
    int cutoffHour = hotelDayBoundaryHour,
    int cutoffMinute = hotelDayBoundaryMinute,
  }) {
    if (isoString == null || isoString.trim().isEmpty) {
      return hotelDayKey(cutoffHour: cutoffHour, cutoffMinute: cutoffMinute);
    }
    final raw = isoString.trim();
    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    try {
      return hotelDayKey(
        now: DateTime.parse(normalized),
        cutoffHour: cutoffHour,
        cutoffMinute: cutoffMinute,
      );
    } catch (_) {
      return hotelDayKey(cutoffHour: cutoffHour, cutoffMinute: cutoffMinute);
    }
  }

  static DateTime hotelDayStart(
    DateTime value, {
    int cutoffHour = hotelDayBoundaryHour,
    int cutoffMinute = hotelDayBoundaryMinute,
  }) {
    final start = DateTime(
      value.year,
      value.month,
      value.day,
      cutoffHour,
      cutoffMinute,
    );
    if (value.isBefore(start)) {
      final previous = start.subtract(const Duration(days: 1));
      return DateTime(
        previous.year,
        previous.month,
        previous.day,
        cutoffHour,
        cutoffMinute,
      );
    }
    return start;
  }

  /// First billed hotel-day boundary for a new stay.
  /// Check-ins from 11:00 until immediately before 14:01 receive the
  /// early-arrival grace and start on that calendar day's 14:01 boundary;
  /// earlier arrivals belong to the previous hotel day.
  static DateTime hotelDayStartForNewBooking(
    DateTime checkin, {
    int cutoffHour = hotelDayBoundaryHour,
    int cutoffMinute = hotelDayBoundaryMinute,
  }) {
    final hotelCheckin = HotelTimezone.toHotelDateTime(checkin);
    final todayBoundary = HotelTimezone.atHotelTime(
      hotelCheckin.year,
      hotelCheckin.month,
      hotelCheckin.day,
      cutoffHour,
      cutoffMinute,
    );
    if (hotelCheckin.isBefore(todayBoundary) &&
        hotelCheckin.hour < earlyCheckinGraceHour) {
      return todayBoundary.subtract(const Duration(days: 1));
    }
    return todayBoundary;
  }

  static String hotelDayStartIso(
    String hotelDay, {
    int cutoffHour = hotelDayBoundaryHour,
    int cutoffMinute = hotelDayBoundaryMinute,
  }) {
    final h = cutoffHour.toString().padLeft(2, '0');
    final m = cutoffMinute.toString().padLeft(2, '0');
    return '${hotelDay}T$h:$m:00';
  }

  /// نهاية يوم الفندق = بداية يوم الفندق التالي (حدّ حصري exclusive).
  /// ملاحظة: الحساب السابق `(cutoffMinute - 1)` كان يُنتج توقيتاً فاسداً مثل
  /// `14:-1:59` عندما cutoffMinute = 0، لأن `padLeft` لا يعالج القيم السالبة.
  static String hotelDayEndIso(
    String hotelDay, {
    int cutoffHour = hotelDayBoundaryHour,
    int cutoffMinute = hotelDayBoundaryMinute,
  }) {
    final next = _nextDateString(hotelDay);
    return hotelDayStartIso(
      next,
      cutoffHour: cutoffHour,
      cutoffMinute: cutoffMinute,
    );
  }

  /// Returns the ISO string for the next day (used for date range queries)
  static String nextDayIso(String dateIso) {
    final d = DateTime.parse(dateIso.substring(0, 10));
    return d.add(const Duration(days: 1)).toIso8601String();
  }

  /// ✅ OCR Review (2026-08-06): يحسب تاريخ اليوم التالي.
  ///
  /// [date] يجب أن يكون بصيغة `yyyy-MM-dd` أو ISO كامل.
  ///
  /// Returns: تاريخ اليوم التالي بصيغة `yyyy-MM-dd`.
  ///
  /// Throws: `FormatException` لو كان [date] غير صالح.
  /// سابقاً، كان يُرجع `nowDateString()` عند الفشل، مما يُخفي أخطاء الـ parse.
  /// الآن يرمي استثناء ليكتشفها المطور.
  ///
  /// ملاحظة حول leap year / month transitions:
  /// `DateTime.add(Duration(days: 1))` في Dart يستخدم calendar arithmetic
  /// صحيحاً — يتعامل مع السنة الكبيسة وانتقالات الشهور بشكل سليم.
  static String _nextDateString(String date) {
    final dt = DateTime.parse('${date}T00:00:00');
    final next = dt.add(const Duration(days: 1));
    return dateToString(next);
  }

  static String safeIsoToDateString(String? isoString) {
    if (isoString == null || isoString.isEmpty) {
      return nowDateString();
    }
    try {
      if (isoString.length >= 10 && isoString.contains('-')) {
        if (isoString.length >= 10) {
          return isoString.substring(0, 10);
        }
      }
      final dateTime = DateTime.parse(isoString);
      return dateToString(dateTime);
    } catch (e) {
      return nowDateString();
    }
  }

  /// حساب عدد الليالي وفق حدّ اليوم الفندقي 14:01 وفترة سماح الوصول 11:00.
  /// الوصول من 11:00 وحتى ما قبل 14:01 يبدأ يومه الفندقي في نفس التاريخ؛
  /// الوصول قبل 11:00 ينتمي إلى اليوم الفندقي السابق.
  /// المغادرة عند أو بعد 14:01 تبدأ يوماً فندقياً جديداً وتضيف ليلة.
  static int nightsWithCutoff(
    DateTime checkin, {
    DateTime? checkout,
    int cutoffHour = hotelDayBoundaryHour,
    int cutoffMinute = hotelDayBoundaryMinute,
    bool applyEarlyCheckinGrace = true,
  }) {
    final hotelCheckin = HotelTimezone.toHotelDateTime(checkin);
    final end = checkout == null
        ? HotelTimezone.now()
        : HotelTimezone.toHotelDateTime(checkout);

    // السماح خاص بوقت وصول النزيل الجديد، وليس بالفترات الاصطناعية
    // مثل «من الآن إلى المغادرة» أو «من المغادرة إلى الآن».
    final DateTime startOfCheckinHotelDay;
    if (applyEarlyCheckinGrace) {
      startOfCheckinHotelDay = hotelDayStartForNewBooking(
        hotelCheckin,
        cutoffHour: cutoffHour,
        cutoffMinute: cutoffMinute,
      );
    } else {
      final todayHotelDayStart = HotelTimezone.atHotelTime(
        hotelCheckin.year,
        hotelCheckin.month,
        hotelCheckin.day,
        cutoffHour,
        cutoffMinute,
      );
      startOfCheckinHotelDay = hotelCheckin.isBefore(todayHotelDayStart)
          ? todayHotelDayStart.subtract(const Duration(days: 1))
          : todayHotelDayStart;
    }

    // حساب الفرق الزمني بين الوقت الحالي (أو وقت المغادرة) وبداية يوم الفندق للحجز
    final duration = end.difference(startOfCheckinHotelDay);
    final totalSeconds = duration.inSeconds;

    if (totalSeconds <= 0) {
      return 1;
    }

    const int secondsInDay = 24 * 3600;

    // عدد الليالي هو ناتج قسمة الثواني الكلية على ثواني اليوم الواحد + 1.
    // لا نخصم عند مضاعف 24 ساعة: الوصول إلى حد 14:01 بالضبط يبدأ
    // يوماً فندقياً جديداً ويجب أن يضيف ليلة كاملة.
    final nights = (totalSeconds ~/ secondsInDay) + 1;
    return nights > 0 ? nights : 1;
  }
}
