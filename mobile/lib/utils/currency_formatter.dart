import 'package:intl/intl.dart';

/// دوال تنسيق الأرقام المالية (بدون رموز عملة)
class CurrencyFormatter {
  static final NumberFormat _intFormatter = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _decimalFormatter = NumberFormat('#,##0.00', 'en_US');

  /// تقريب المبلغ بشكل صحيح للمبالغ المالية.
  ///
  /// نستخدم `floor` للقيم الموجبة و `ceil` للقيم السالبة — وهذا ما يُسمى
  /// "rounding towards zero" (اقتطاع الكسور). هذا السلوك مطلوب للمبالغ
  /// المالية في الفندق:
  ///   - لا نُضيف على فاتورة النزيل (1000.99 → 1000، لا 1001)
  ///   - لا نُقلِّل من رصيد الدين السالب (-500.5 → -500، لا -501)
  ///
  /// الاختبار test/currency_formatter_test.dart يُوثّق هذا السلوك.
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
  /// نُطبِّق نفس سياسة التقريب للمبالغ المالية (rounding towards zero)
  /// المُستخدمة في [_roundAmount] — اقتطاع الكسور لا تقريبها. هذا يضمن
  /// أن `parseAmount('1000.5')` يُعيد 1000 (لا 1000.5 أو 1001) بحيث
  /// تطابق قيمة العرض في [formatAmount].
  ///
  /// الاختبار test/currency_formatter_test.dart يُوثّق هذا السلوك.
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
    // ✅ اقتطاع الكسور للمبالغ المالية (rounding towards zero)
    // مثال: 1000.5 → 1000.0، -500.5 → -500.0
    return _roundAmount(parsed).toDouble();
  }

  /// إنشاء NumberFormat للاستخدام المتكرر
  static NumberFormat get defaultFormatter => _intFormatter;
  static NumberFormat get decimalFormatter => _decimalFormatter;
}
