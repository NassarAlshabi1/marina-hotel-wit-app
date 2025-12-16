class Time {
  static int nowEpoch() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  static String nowIso() => DateTime.now().toIso8601String();
  static String nowDateString() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
  static String dateToString(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  static String hotelDayKey({DateTime? now, int cutoffHour = 14}) {
    final base = now ?? DateTime.now();
    final shifted = base.subtract(Duration(hours: cutoffHour));
    return dateToString(shifted);
  }

  static String hotelDayKeyFromIso(String? isoString, {int cutoffHour = 14}) {
    if (isoString == null || isoString.trim().isEmpty) {
      return hotelDayKey(cutoffHour: cutoffHour);
    }
    final raw = isoString.trim();
    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    try {
      return hotelDayKey(now: DateTime.parse(normalized), cutoffHour: cutoffHour);
    } catch (_) {
      return hotelDayKey(cutoffHour: cutoffHour);
    }
  }

  static String hotelDayStartIso(String hotelDay, {int cutoffHour = 14}) {
    final h = cutoffHour.toString().padLeft(2, '0');
    return '${hotelDay}T$h:00:00';
  }

  static String hotelDayEndIso(String hotelDay, {int cutoffHour = 14}) {
    final next = _nextDateString(hotelDay);
    final h = cutoffHour.toString().padLeft(2, '0');
    return '${next}T$h:00:00';
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
  /// حساب عدد الأيام مع قاعدة الساعة 14:00
  /// قاعدة احتساب اليوم: يُحتسب اليوم الواحد بدءاً من وقت تسجيل الدخول الفعلي 
  /// وحتى الساعة 14:00 من اليوم التالي.
  /// أي مغادرة بعد الساعة 14:00، حتى لو بدقيقة واحدة، تؤدي إلى احتساب يوم إضافي كامل.
  static int nightsWithCutoff(DateTime checkin, {DateTime? checkout, int cutoffHour = 14}) {
    final end = checkout ?? DateTime.now();
    
    // حساب عدد الأيام التي عبرها النزيل (وليس الأيام الكاملة)
    final checkinDate = DateTime(checkin.year, checkin.month, checkin.day);
    final checkoutDate = DateTime(end.year, end.month, end.day);
    int days = checkoutDate.difference(checkinDate).inDays;
    
    // إذا لم يعبر أي يوم (نفس التاريخ)، فهو يوم واحد على الأقل
    if (days == 0) {
      days = 1;
    }
    
    // إذا كان وقت المغادرة بعد ساعة القطع (14:00)، أضف يوماً إضافياً
    if (end.hour > cutoffHour || 
        (end.hour == cutoffHour && end.minute > 0) ||
        (end.hour == cutoffHour && end.minute == 0 && end.second > 0)) {
      days += 1;
    }
    
    return days;
  }
}
