import 'package:flutter/foundation.dart' show debugPrint;
/// أداة مشتركة لتحليل التواريخ النصية.
///
/// تُستخدم في عدة شاشات وخدمات لتحويل سلاسل التاريخ إلى [DateTime].
/// تتعامل مع صيغ ISO المتعددة (مع/بدون T، مع/بدون ثوانٍ).
class DateParser {
  DateParser._();

  /// تحويل سلسلة تاريخ نصية اختيارية إلى [DateTime].
  ///
  /// يدعم الصيغ التالية:
  /// - `2025-01-15T14:30:00` (ISO كامل)
  /// - `2025-01-15 14:30` (بمسافة بدلاً من T، بدون ثوانٍ)
  /// - `2025-01-15T14:30` (بدون ثوانٍ)
  ///
  /// يُرجع `null` إذا كانت القيمة فارغة أو غير صالحة.
  static DateTime? parse(String? value) {
    if (value == null) {
      return null;
    }
    final v = value.trim();
    if (v.isEmpty) {
      return null;
    }
    final normalized = v.contains('T') ? v : v.replaceFirst(' ', 'T');
    final withSeconds = normalized.length == 16 ? '$normalized:00' : normalized;
    try {
      return DateTime.parse(withSeconds);
    } catch (e, st) {
      debugPrint('⚠️ Swallowed error in date_parser.dart: ');
      return null;
    }
  }
}
