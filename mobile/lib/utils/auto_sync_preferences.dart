import 'package:shared_preferences/shared_preferences.dart';

/// ترحيل قيمة تفضيل (preference) من مفتاح قديم (legacy) إلى مفتاح جديد.
///
/// ✅ OCR FIX (2026-08-06): توثيق أوضح للأنواع المدعومة + رسالة خطأ أوضح.
///
/// هذه الدالة تدعم فقط الأنواع:
///   - `int` — الأعداد الصحيحة (مثل intervals، thresholds)
///   - `bool` — القيم المنطقية (مثل enabled/disabled flags)
///
/// الأنواع الأخرى (`String`، `List<String>`، `double`، إلخ) غير مدعومة لأن
/// الـ SharedPreferences API يستخدم methods منفصلة لكل نوع (`getInt`،
/// `getBool`، `getString`، إلخ) ولا يمكن التعامل معها بشكل generic بدون
/// تحديد النوع صراحةً.
///
/// [prefs] - نسخة SharedPreferences للقراءة/الكتابة
/// [newKey] - المفتاح الجديد (الهدف)
/// [legacyKey] - المفتاح القديم (المصدر)
/// [defaultValue] - القيمة الافتراضية إذا لم تُوجد في أي مفتاح
/// [apply] - دالة async تُطبّق القيمة على النظام (مثلاً تحديث Riverpod state)
///
/// Returns: القيمة المُرحّلة (من newKey أو legacyKey أو default)
///
/// Throws: `ArgumentError` إذا كان النوع `T` غير مدعوم.
Future<T> migrateAutoSyncPreference<T>({
  required SharedPreferences prefs,
  required String newKey,
  required String legacyKey,
  required T defaultValue,
  required Future<void> Function(T value) apply,
}) async {
  // ✅ OCR FIX: التحقق من النوع المدعوم في وقت التشغيل.
  // ملاحظة: `T == int` يعمل في Dart لأن الـ type parameter يُحل في وقت التشغيل
  // للـ reified generics. إذا فشل التحقق، نرمي ArgumentError مع رسالة واضحة
  // بدلاً من الصمت (كان سابقاً UnsupportedError — ArgumentError أوضح للـ caller).
  if (T != int && T != bool) {
    throw ArgumentError(
      'Unsupported preference type: $T. '
      'migrateAutoSyncPreference only supports int and bool. '
      'For String or List<String>, use SharedPreferences directly '
      '(getString/getStringList).',
      'T',
    );
  }

  T value;
  if (T == int) {
    final resolved =
        prefs.getInt(newKey) ?? prefs.getInt(legacyKey) ?? defaultValue as int;
    await prefs.setInt(newKey, resolved);
    value = resolved as T;
  } else {
    // T == bool (تم التحقق أعلاه)
    final resolved =
        prefs.getBool(newKey) ??
        prefs.getBool(legacyKey) ??
        defaultValue as bool;
    await prefs.setBool(newKey, resolved);
    value = resolved as T;
  }

  await apply(value);
  return value;
}
