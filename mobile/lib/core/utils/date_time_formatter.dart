import 'package:intl/intl.dart';

/// Date and Time Formatting Utilities
///
/// مركز موحد لجميع عمليات تنسيق التاريخ والوقت في التطبيق
class DateTimeFormatter {
  DateTimeFormatter._();

  // Date formats
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _timeFormat = DateFormat('HH:mm');
  static final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _dateTimeFullFormat = DateFormat(
    'yyyy-MM-dd HH:mm:ss',
  );
  static final DateFormat _arabicDateFormat = DateFormat('d MMMM yyyy', 'ar');
  static final DateFormat _arabicDateTimeFormat = DateFormat(
    'd MMMM yyyy - h:mm a',
    'ar',
  );

  /// Format ISO string to date and time (2024-01-29 18:30)
  static String formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'لا يوجد';

    try {
      final date = DateTime.parse(isoString);
      return _dateTimeFormat.format(date);
    } catch (Object) {
      return 'تاريخ غير صالح';
    }
  }

  /// Format ISO string to date only (2024-01-29)
  static String formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'لا يوجد';

    try {
      final date = DateTime.parse(isoString);
      return _dateFormat.format(date);
    } catch (Object) {
      return 'تاريخ غير صالح';
    }
  }

  /// Format ISO string to time only (18:30)
  static String formatTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'لا يوجد';

    try {
      final date = DateTime.parse(isoString);
      return _timeFormat.format(date);
    } catch (Object) {
      return 'وقت غير صالح';
    }
  }

  /// Format ISO string to full date and time with seconds
  static String formatDateTimeFull(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'لا يوجد';

    try {
      final date = DateTime.parse(isoString);
      return _dateTimeFullFormat.format(date);
    } catch (Object) {
      return 'تاريخ غير صالح';
    }
  }

  /// Format ISO string to Arabic date (29 يناير 2024)
  static String formatArabicDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'لا يوجد';

    try {
      final date = DateTime.parse(isoString);
      return _arabicDateFormat.format(date);
    } catch (Object) {
      return 'تاريخ غير صالح';
    }
  }

  /// Format ISO string to Arabic date and time (29 يناير 2024 - 6:30 م)
  static String formatArabicDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'لا يوجد';

    try {
      final date = DateTime.parse(isoString);
      return _arabicDateTimeFormat.format(date);
    } catch (Object) {
      return 'تاريخ غير صالح';
    }
  }

  /// Format DateTime to ISO string
  static String toIsoString(DateTime? dateTime) {
    return dateTime?.toIso8601String() ?? '';
  }

  /// Get relative time (منذ 5 دقائق، منذ ساعة، إلخ)
  static String getRelativeTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'لا يوجد';

    try {
      final date = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inSeconds < 60) {
        return 'منذ لحظات';
      } else if (difference.inMinutes < 60) {
        final minutes = difference.inMinutes;
        return 'منذ $minutes ${minutes == 1 ? 'دقيقة' : 'دقائق'}';
      } else if (difference.inHours < 24) {
        final hours = difference.inHours;
        return 'منذ $hours ${hours == 1 ? 'ساعة' : 'ساعات'}';
      } else if (difference.inDays < 7) {
        final days = difference.inDays;
        return 'منذ $days ${days == 1 ? 'يوم' : 'أيام'}';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return 'منذ $weeks ${weeks == 1 ? 'أسبوع' : 'أسابيع'}';
      } else if (difference.inDays < 365) {
        final months = (difference.inDays / 30).floor();
        return 'منذ $months ${months == 1 ? 'شهر' : 'أشهر'}';
      } else {
        final years = (difference.inDays / 365).floor();
        return 'منذ $years ${years == 1 ? 'سنة' : 'سنوات'}';
      }
    } catch (Object) {
      return 'تاريخ غير صالح';
    }
  }

  /// Get time ago in short format (5د، 2س، 3ي)
  static String getTimeAgoShort(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '-';

    try {
      final date = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inSeconds < 60) {
        return 'الآن';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}د';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}س';
      } else if (difference.inDays < 365) {
        return '${difference.inDays}ي';
      } else {
        return '${(difference.inDays / 365).floor()}سنة';
      }
    } catch (Object) {
      return '-';
    }
  }

  /// Check if date is today
  static bool isToday(String? isoString) {
    if (isoString == null || isoString.isEmpty) return false;

    try {
      final date = DateTime.parse(isoString);
      final now = DateTime.now();
      return date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    } catch (Object) {
      return false;
    }
  }

  /// Check if date is yesterday
  static bool isYesterday(String? isoString) {
    if (isoString == null || isoString.isEmpty) return false;

    try {
      final date = DateTime.parse(isoString);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      return date.year == yesterday.year &&
          date.month == yesterday.month &&
          date.day == yesterday.day;
    } catch (Object) {
      return false;
    }
  }

  /// Format duration (e.g., 1:30:45)
  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  /// Format duration in Arabic (ساعة و30 دقيقة)
  static String formatDurationArabic(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final parts = <String>[];
    if (hours > 0) {
      parts.add('$hours ${hours == 1 ? 'ساعة' : 'ساعات'}');
    }
    if (minutes > 0) {
      parts.add('$minutes ${minutes == 1 ? 'دقيقة' : 'دقائق'}');
    }
    if (seconds > 0 && hours == 0) {
      parts.add('$seconds ${seconds == 1 ? 'ثانية' : 'ثوان'}');
    }

    return parts.isEmpty ? '0 ثانية' : parts.join(' و ');
  }
}
