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

  static DateTime hotelDayStart(DateTime value, {int cutoffHour = 14}) {
    final start = DateTime(value.year, value.month, value.day, cutoffHour);
    if (value.isBefore(start)) {
      final previous = start.subtract(const Duration(days: 1));
      return DateTime(previous.year, previous.month, previous.day, cutoffHour);
    }
    return start;
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

  static int nightsWithCutoff(DateTime checkin, {DateTime? checkout, int cutoffHour = 14}) {
    final end = checkout ?? DateTime.now();

    var effectiveEnd = end;
    if (!effectiveEnd.isAfter(checkin)) {
      effectiveEnd = checkin.add(const Duration(minutes: 1));
    }

    int count = 0;
    var cursor = checkin;
    while (cursor.isBefore(effectiveEnd)) {
      final dayStart = hotelDayStart(cursor, cutoffHour: cutoffHour);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final segmentEnd = effectiveEnd.isBefore(dayEnd) ? effectiveEnd : dayEnd;
      if (!segmentEnd.isAfter(cursor)) {
        break;
      }
      count += 1;
      cursor = segmentEnd;
    }

    return count == 0 ? 1 : count;
  }
}
