class Time {
  static const int earlyCheckinGraceHour = 8;

  static int nowEpoch() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  static String nowIso() => DateTime.now().toIso8601String();
  static String nowDateString() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String dateToString(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  static String hotelDayKey({DateTime? now, int cutoffHour = 14, int cutoffMinute = 1}) {
    final base = now ?? DateTime.now();
    final shifted = base.subtract(Duration(hours: cutoffHour, minutes: cutoffMinute));
    return dateToString(shifted);
  }

  static String hotelDayKeyFromIso(String? isoString, {int cutoffHour = 14, int cutoffMinute = 1}) {
    if (isoString == null || isoString.trim().isEmpty) {
      return hotelDayKey(cutoffHour: cutoffHour, cutoffMinute: cutoffMinute);
    }
    final raw = isoString.trim();
    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    try {
      return hotelDayKey(now: DateTime.parse(normalized), cutoffHour: cutoffHour, cutoffMinute: cutoffMinute);
    } catch (_) {
      return hotelDayKey(cutoffHour: cutoffHour, cutoffMinute: cutoffMinute);
    }
  }

  static DateTime hotelDayStart(DateTime value, {int cutoffHour = 14, int cutoffMinute = 1}) {
    final start = DateTime(value.year, value.month, value.day, cutoffHour, cutoffMinute);
    if (value.isBefore(start)) {
      final previous = start.subtract(const Duration(days: 1));
      return DateTime(previous.year, previous.month, previous.day, cutoffHour, cutoffMinute);
    }
    return start;
  }

  static DateTime hotelDayStartForNewBooking(DateTime checkin, {int cutoffHour = 14, int cutoffMinute = 1}) {
    if (checkin.hour < cutoffHour || (checkin.hour == cutoffHour && checkin.minute < cutoffMinute)) {
      return DateTime(checkin.year, checkin.month, checkin.day, cutoffHour, cutoffMinute);
    }
    return hotelDayStart(checkin, cutoffHour: cutoffHour, cutoffMinute: cutoffMinute);
  }

  static String hotelDayStartIso(String hotelDay, {int cutoffHour = 14, int cutoffMinute = 1}) {
    final h = cutoffHour.toString().padLeft(2, '0');
    final m = cutoffMinute.toString().padLeft(2, '0');
    return '${hotelDay}T$h:$m:00';
  }

  static String hotelDayEndIso(String hotelDay, {int cutoffHour = 14, int cutoffMinute = 1}) {
    final next = _nextDateString(hotelDay);
    final h = cutoffHour.toString().padLeft(2, '0');
    final m = (cutoffMinute - 1).toString().padLeft(2, '0');
    return '${next}T$h:$m:59';
  }

  /// Returns the ISO string for the next day (used for date range queries)
  static String nextDayIso(String dateIso) {
    final d = DateTime.parse(dateIso.substring(0, 10));
    return d.add(const Duration(days: 1)).toIso8601String();
  }

  static String _nextDateString(String date) {
    try {
      final dt = DateTime.parse('${date}T00:00:00');
      final next = dt.add(const Duration(days: 1));
      return dateToString(next);
    } catch (_) {
      return nowDateString();
    }
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

  /// حساب عدد الأيام مع قاعدة الساعة 14:01
  /// قاعدة احتساب اليوم: يُحتسب اليوم الواحد بدءاً من وقت تسجيل الدخول الفعلي
  /// وحتى الساعة 14:01 من اليوم التالي.
  /// أي مغادرة عند أو بعد الساعة 14:01، حتى لو بدقيقة واحدة، تؤدي إلى احتساب يوم إضافي كامل.
  static int nightsWithCutoff(DateTime checkin, {DateTime? checkout, int cutoffHour = 14, int cutoffMinute = 1}) {
    final end = checkout ?? DateTime.now();

    // تحديد بداية "يوم الفندق" لعملية تسجيل الدخول
    DateTime startOfCheckinHotelDay = DateTime(checkin.year, checkin.month, checkin.day, cutoffHour, cutoffMinute);
    if (checkin.isBefore(startOfCheckinHotelDay)) {
      startOfCheckinHotelDay = startOfCheckinHotelDay.subtract(const Duration(days: 1));
    }

    // حساب الفرق الزمني بين الوقت الحالي (أو وقت المغادرة) وبداية يوم الفندق للحجز
    final duration = end.difference(startOfCheckinHotelDay);
    final totalSeconds = duration.inSeconds;

    if (totalSeconds <= 0) {
      return 1;
    }

    const int secondsInDay = 24 * 3600;

    // عدد الليالي هو ناتج قسمة الثواني الكلية على ثواني اليوم الواحد + 1
    // إذا كان الوقت بالضبط 14:00 (أي مضاعفات 24 ساعة)، لا يتم احتساب يوم جديد
    int nights = (totalSeconds ~/ secondsInDay) + 1;

    if (totalSeconds > 0 && totalSeconds % secondsInDay == 0) {
      nights -= 1;
    }

    return nights > 0 ? nights : 1;
  }
}
