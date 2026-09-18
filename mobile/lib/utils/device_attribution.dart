/// ✅ (2026-09-14) أدوات إسناد سجلات الرواتب لمسجّلها وجهازها.
///
/// الخلفية: تقرير سحوبات الرواتب كان يعرض سجلات بلا أي إسناد (من سجّل؟
/// أي جهاز؟) — وأظهر وقتاً وهمياً 00:00 لأنه يحلل تاريخ السحب النصي
/// (بلا وقت) كمنتصف الليل. سجل 19,000 للأورمو محمد يوم 2026-09-13
/// أُنشئ فعلياً 22:59 مساءً من جهاز BRC-NX1 ولا أحد يستطيع معرفته من
/// التقرير — هذه الأدوات تكشف الجهاز من الساعة الاتجاهية (vectorClock).
library;

import 'dart:convert';

/// استخراج تلميح الجهاز من مفتاح الساعة الاتجاهية.
///
/// مفاتيح الساعة الاتجاهية بصيغة `marina_<model>_<shortId>` مثل:
/// `marina_HNBRC-M1_be06acca` → تُعرض `HNBRC-M1 (be06acca)`.
///
/// يُرجع null إن كان السجل بلا ساعة اتجاهية مفيدة ({} أو فاسد).
String? deviceHintFromVectorClock(String? vectorClock) {
  final raw = (vectorClock ?? '').trim();
  if (raw.isEmpty || raw == '{}') return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.isEmpty) return null;
    final key = decoded.keys.first.toString();
    var id = key;
    if (id.startsWith('marina_')) id = id.substring(7);
    if (id.isEmpty) return null;
    final lastUnderscore = id.lastIndexOf('_');
    if (lastUnderscore <= 0 || lastUnderscore == id.length - 1) {
      return id;
    }
    final model = id.substring(0, lastUnderscore);
    final short = id.substring(lastUnderscore + 1);
    return '$model ($short)';
  } catch (_) {
    return null;
  }
}
