import 'package:intl/intl.dart';

/// دوال تنسيق الأرقام المالية (بدون رموز عملة)
class CurrencyFormatter {
  static final NumberFormat _intFormatter = NumberFormat('#,##0', 'en_US');

  /// تنسيق المبلغ بالفواصل فقط (5,000)
  static String formatCurrency(double amount, {bool showDecimals = false}) {
    return _intFormatter.format(amount.truncate());
  }

  /// تنسيق المبلغ بالفواصل فقط (5,000)
  static String formatAmount(double amount, {bool showDecimals = false}) {
    return _intFormatter.format(amount.truncate());
  }

  /// تنسيق المبلغ بالفواصل الإنجليزية (للأنظمة التي لا تدعم الفواصل العربية)
  static String formatCurrencyEnglish(double amount, {bool showDecimals = false}) {
    return _intFormatter.format(amount.truncate());
  }

  /// تنسيق المبلغ للعرض في واجهة المستخدم (أرقام فقط)
  static String formatForDisplay(double amount, {bool showDecimals = false}) {
    return formatAmount(amount);
  }

  /// تنسيق المبلغ للرسائل النصية (أرقام فقط)
  static String formatForMessage(double amount, {bool showDecimals = false}) {
    return formatAmount(amount);
  }

  /// تحويل المبلغ من النص إلى رقم
  static double? parseAmount(String text) {
    var cleanText = text.trim();

    cleanText = cleanText
        .replaceAll('٬', '')
        .replaceAll('،', '')
        .replaceAll(',', '')
        .replaceAll('٫', '.');

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
    if (parsed == null) return null;
    return parsed.truncateToDouble();
  }

  /// إنشاء NumberFormat للاستخدام المتكرر
  static NumberFormat get defaultFormatter => _intFormatter;
  static NumberFormat get decimalFormatter => _intFormatter;
}
