class Time {
  static int nowEpoch() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  static String nowIso() => DateTime.now().toIso8601String();
  
  /// Safe method to get date in YYYY-MM-DD format
  static String nowDateString() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
  
  /// Safe method to convert DateTime to date string
  static String dateToString(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }
  
  /// Safe method to get date string from ISO string, with fallback
  static String safeIsoToDateString(String? isoString) {
    if (isoString == null || isoString.isEmpty) {
      return nowDateString();
    }
    
    try {
      if (isoString.length >= 10 && isoString.contains('-')) {
        // Already in YYYY-MM-DD format
        if (isoString.length >= 10) {
          return isoString.substring(0, 10);
        }
      }
      
      // Try to parse as DateTime and format
      final dateTime = DateTime.parse(isoString);
      return dateToString(dateTime);
    } catch (e) {
      // If all fails, return current date
      return nowDateString();
    }
  }
}
