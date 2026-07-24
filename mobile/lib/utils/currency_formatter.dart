import 'package:intl/intl.dart';

/// دوال تنسيق الأرقام المالية (بدون رموز عملة)
class CurrencyFormatter {
  static final NumberFormat _intFormatter = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _decimalFormatter = NumberFormat('#,##0.00', 'en_US');

  /// معالجة المبلغ المالي: **اقتطاع الكسور (بدون تقريب)**.
  ///
  /// سياسة الفندق: لا نتعامل بالكسور العشرية إطلاقاً، ولا نُقرّب لأعلى.
  /// نُقتطع الكسور نحو الصفر (truncation towards zero):
  ///   - الموجب: floor  →  1000.99 → 1000، 1000.5 → 1000
  ///   - السالب: ceil   →  -500.5  → -500
  /// هذا يضمن عدم إضافة أي مبلغ على فاتورة النزيل نتيجة التقريب.
  static int _roundAmount(double amount) {
    if (amount >= 0) {
      return amount.floor();
    }
    return amount.ceil();
  }

  /// تنسيق المبلغ بالفواصل فقط (5,000)
  static String formatCurrency(double amount, {bool showDecimals = false}) {
    if (showDecimals) {
      return _decimalFormatter.format(amount);
    }
    return _intFormatter.format(_roundAmount(amount));
  }

  /// تنسيق المبلغ بالفواصل — مرادف لـ formatCurrency (للحفاظ على التوافق)
  static String formatAmount(double amount, {bool showDecimals = false}) =>
      formatCurrency(amount, showDecimals: showDecimals);

  /// تنسيق المبلغ بالفواصل — مرادف لـ formatCurrency (للحفاظ على التوافق)
  static String formatCurrencyEnglish(double amount, {bool showDecimals = false}) =>
      formatCurrency(amount, showDecimals: showDecimals);

  /// تنسيق المبلغ للعرض — مرادف لـ formatCurrency
  static String formatForDisplay(double amount, {bool showDecimals = false}) =>
      formatCurrency(amount, showDecimals: showDecimals);

  /// تنسيق المبلغ للرسائل — مرادف لـ formatCurrency
  static String formatForMessage(double amount, {bool showDecimals = false}) =>
      formatCurrency(amount, showDecimals: showDecimals);

  /// تحويل المبلغ من النص إلى رقم.
  ///
  /// نُطبِّق نفس سياسة الاقتطاع للمبالغ المالية (بدون كسور عشرية):
  /// `parseAmount('1000.5')` يُرجع 1000 و `parseAmount('1999.99')` يُرجع 1999.
  /// هذا يضمن تطابق القيمة المُدخلة مع القيمة المعروضة في [formatAmount].
  static double? parseAmount(String text) {
    var cleanText = text.trim();

    cleanText = cleanText.replaceAll('٬', '').replaceAll('،', '').replaceAll(',', '').replaceAll('٫', '.');

    const digitMap = {
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
      '۰': '0',
      '۱': '1',
      '۲': '2',
      '۳': '3',
      '۴': '4',
      '۵': '5',
      '۶': '6',
      '۷': '7',
      '۸': '8',
      '۹': '9',
    };

    cleanText = cleanText.split('').map((ch) => digitMap[ch] ?? ch).join();

    final parsed = double.tryParse(cleanText);
    if (parsed == null) {
      return null;
    }
    // اقتطاع الكسور — لا نتعامل بالكسور العشرية (مثال: 1000.5 → 1000، 1999.99 → 1999).
    return _roundAmount(parsed).toDouble();
  }

  /// إنشاء NumberFormat للاستخدام المتكرر
  static NumberFormat get defaultFormatter => _intFormatter;
  static NumberFormat get decimalFormatter => _decimalFormatter;
}
