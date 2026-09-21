/// ✅ (2026-09-22) أدوات البحث العربي — مشتقّة من منطق القائمة السوداء
/// (blacklist_repository.dart) ومرفَّعة لطبقة مشتركة لخدمة البحث الشامل.
///
/// مشكلة SQLite LIKE: مطابقة بايتية لا تعرف التطبيع — «احمد» لا تجد
/// «أحمد». الحل هنا توسيع نمط البحث إلى متغيرات الحروف المتغيرة
/// (عائلة الألف، الياء/الألف المقصورة، الواو/الهمزة) دون أي تغيير
/// في مخطط قاعدة البيانات.
library;

/// إزالة التشكيل والتطويل وتوحيد الحروف المتغيرة — للمقارنات في Dart.
///
/// تطابق نفس عقد `_normalizeArabic` في blacklist_repository (مصدر الحقيقة
/// التاريخي) مع فروق مقصودة:
/// - لا نحذف الأحرف اللاتينية (البحث يشمل نصوصاً لاتينية وإنجليزية).
/// - نوحّد ة→ه (تغاير إملائي شائع جداً في الأسماء) — عقد بحث لا عقد
///   مطابقة قائمة سوداء.
/// - لا نطبّع الأرقام — لها معالجة خاصة في [tryParseAmount].
String normalizeArabicForSearch(String input) {
  var s = input.trim();
  // التشكيل وعلامات القرآن
  s = s.replaceAll(
    RegExp('[\u0617-\u061A\u064B-\u0652\u0670\u0653-\u065F\u06D6-\u06ED]'),
    '',
  );
  // التطويل ــــ
  s = s.replaceAll('\u0640', '');
  // توحيد عائلة الألف والهمزات على الألف
  s = s.replaceAll(RegExp('[إأٱآ]'), 'ا');
  s = s.replaceAll('ؤ', 'و');
  s = s.replaceAll('ئ', 'ي');
  s = s.replaceAll('ى', 'ي');
  s = s.replaceAll('ة', 'ه');
  // دمج الفراغات المتعددة
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.toLowerCase();
}

/// عائلات الحروف المتغيرة: الاستبدال بأي عضو يغطي التهجئات المخزنة
/// الفعلية — الطبقات الثلاث عالية القيمة في البحث العربي:
/// - عائلة الألف (تشمل الألف المقصورة النهائية: يحيى/يحيا)
/// - عائلة الياء (ي/ى/ئ)
/// - عائلة الهاء (ه/ة: جميله/جميلة)
/// - عائلة الواو (و/ؤ)
const Map<String, List<String>> _variantFamilies = {
  'ا': ['ا', 'أ', 'إ', 'آ', 'ٱ', 'ى'],
  'ي': ['ي', 'ى', 'ئ'],
  'و': ['و', 'ؤ'],
  'ه': ['ه', 'ة'],
};

/// توليد متغيرات كلمة واحدة لتغطية فروق التهجئة في LIKE.
///
/// مثال: «احمد» → {احمد, أحمد, إحمد, آحمد, ٱحمد, ىحمد}
/// و«يحيي» → يشمل «يحيى» و«يحئي» و«ىحيي»…
///
/// الخوارزمية: الكلمة المطبَّعة أساساً + كل استبدال أحادي الموضع
/// (كل موضع حرف متغيّر يُستبدل بكل أفراد عائلته). هذا يغطي واقعياً
/// كل الاختلافات الفردية — والاختلاف الواحد هو الحالة الساحقة في
/// الأسماء (المستخدم يعرف الاسم تقريباً) — مع حد أقصى مضمون
/// (طول × حجم عائلة) بلا انفجار توافقي ولا تجميد يفوّت المتغيرات.
Set<String> expandArabicVariants(String token, {int maxVariants = 16}) {
  final normalized = normalizeArabicForSearch(token);
  if (normalized.isEmpty) {
    return const {};
  }
  final variants = <String>{normalized};
  for (var i = 0; i < normalized.length; i++) {
    final family = _variantFamilies[normalized[i]];
    if (family == null) {
      continue;
    }
    for (final replacement in family) {
      if (replacement == normalized[i]) {
        continue;
      }
      variants.add(normalized.replaceRange(i, i + 1, replacement));
      if (variants.length >= maxVariants) {
        return variants;
      }
    }
  }
  return variants;
}

/// تقسيم استعلام متعدد الكلمات إلى كلمات مطبَّعة (بحد أقصى [maxWords]).
List<String> tokenizeQuery(String input, {int maxWords = 3}) =>
    normalizeArabicForSearch(
      input,
    ).split(' ').where((w) => w.isNotEmpty).take(maxWords).toList();

/// تهريب محارف LIKE الخاصة داخل نمط (بعقد ESCAPE '\').
///
/// تمريرة واحدة على وحدات الشيفرة — تسلسل ثابت وقابل للقراءة بلا
/// حرفية backslash نصية (سلسلة خام لا يمكن أن تحمل شرطة خلفية مفردة).
String escapeLike(String raw) {
  const backslash = 0x5C;
  const percent = 0x25;
  const underscore = 0x5F;
  final buffer = StringBuffer();
  for (final code in raw.codeUnits) {
    if (code == backslash || code == percent || code == underscore) {
      buffer.writeCharCode(backslash);
    }
    buffer.writeCharCode(code);
  }
  return buffer.toString();
}

/// أنماط LIKE الجاهزة لكلمة واحدة: %متغير% لكل متغير همزي.
///
/// النتيجة مرتبة ليكون أداء المحرك ثابتاً وقابلاً للاختبار.
List<String> likePatternsForWord(String token, {int maxVariants = 12}) =>
    expandArabicVariants(
      token,
      maxVariants: maxVariants,
    ).map((v) => '%${escapeLike(v)}%').toList()..sort();

/// محاولة قراءة المدخل كرقم مبلغ — يدعم الأرقام العربية والفواصل.
///
/// «40,000» و«٤٠٠٠٠» تُقرأ رقمياً؛ «أحمد» و«123abc» تُرجعان null
/// (المدخل المختلط ليس مبلغاً).
double? tryParseAmount(String input) {
  var s = input.trim();
  // أرقام عربية-هندية → لاتينية
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const latinDigits = '0123456789';
  final buf = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final idx = arabicDigits.indexOf(c);
    buf.write(idx >= 0 ? latinDigits[idx] : c);
  }
  s = buf
      .toString()
      .replaceAll(',', '')
      .replaceAll('،', '')
      .replaceAll(' ', '');
  if (s.isEmpty) {
    return null;
  }
  return double.tryParse(s);
}
