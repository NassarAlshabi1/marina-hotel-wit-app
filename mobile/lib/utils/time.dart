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
  static int nightsWithCutoff(DateTime checkin, {DateTime? checkout, int cutoffHour = 13}) {
    final end = checkout ?? DateTime.now();
    final startAdj = checkin.subtract(Duration(hours: cutoffHour));
    final endAdj = end.subtract(Duration(hours: cutoffHour));
    int nights = endAdj.difference(startAdj).inDays;
    if (nights < 1) nights = 1;
    return nights;
  }
}
