// utils/guest_info_search.dart
//
// ✅ (2026-10-06): منطق بحث «سجل المعلومية» في مكان عام قابل للاختبار
// (كان مدفوناً كأعضاء خاصة داخل `_InformationScreenState`). لا يعتمد على
// واجهة المستخدم إطلاقاً — دالتان نقيّتان.
import '../services/local_db.dart';

class GuestInfoSearch {
  const GuestInfoSearch._();

  /// تطبيع نص عربي للبحث: إزالة التشكيل والتطويل، وتوحيد الألف/الهمزة
  /// والتاء المربوطة/الهاء والياء/الألف المقصورة، وتوحيد الأرقام العربية.
  static String normalize(String input) {
    var text = input.trim().toLowerCase();
    // تشكيل وتطويل
    text = text.replaceAll(
      RegExp('[\\u064B-\\u065F\\u0670\\u06D6-\\u06ED\\u0640]'),
      '',
    );
    const unified = {
      'أ': 'ا',
      'إ': 'ا',
      'آ': 'ا',
      'ٱ': 'ا',
      'ى': 'ي',
      'ئ': 'ي',
      'ؤ': 'و',
      'ة': 'ه',
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
    };
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(unified[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// هل يطابق السجل عبارة البحث؟ (الاسم أولاً ثم الغرفة/الهوية/المحافظة).
  ///
  /// عبارة فارغة أو مسافات فقط = «بلا فلترة» ⇒ كل السجلات مطابقة.
  static bool matches(GuestInfo info, String query) {
    final q = normalize(query);
    if (q.isEmpty) return true;
    final haystack = [
      info.guestName,
      info.roomNumber,
      info.idNumber,
      info.governorate ?? '',
      info.issuePlace ?? '',
      info.nationality,
      info.notes ?? '',
    ].map(normalize).join('\u0001');
    return haystack.contains(q);
  }
}
