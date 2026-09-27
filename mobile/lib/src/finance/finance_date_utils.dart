/// أدوات تحليل التواريخ لمحركات المالية — تتعامل مع صيغ التواريخ
/// الموجودة فعلياً في قاعدة البيانات المحلية:
/// - ISO كامل: `2026-09-27T14:01:00.000`
/// - SQL: `2026-09-27 14:01:00`
/// - تاريخ فقط: `2026-09-27`
library;

/// يحاول تحويل أي صيغة تاريخ معروفة إلى [DateTime]، وإلا null.
DateTime? tryParseDate(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
  final dt = DateTime.tryParse(normalized);
  if (dt != null) return dt;
  // آخر محاولة: أول 10 أحرف بصيغة yyyy-MM-dd
  if (s.length >= 10) {
    return DateTime.tryParse(s.substring(0, 10));
  }
  return null;
}

/// يحوّل التاريخ إلى مفتاح يوم `yyyy-MM-dd` (نفس نمط Time.dateToString).
String toDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// بداية اليوم (00:00) لتاريخ مفتاح يوم.
DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// عدد الأيام الكاملة بين تاريخين (b − a).
int daysBetween(DateTime a, DateTime b) =>
    dayStart(b).difference(dayStart(a)).inDays;
