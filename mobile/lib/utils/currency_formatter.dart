import 'package:intl/intl.dart';

/// ثوابت العملة الموحدة
class CurrencyConstants {
  static const String currencySymbol = 'ر.س';
  static const String currencyName = 'الريال السعودي';
}

/// دوال تنسيق العملة الموحدة
class CurrencyFormatter {
  /// تنسيق المبلغ برمز العملة (5,000 ر.س)
  static String formatCurrency(double amount, {bool showDecimals = false}) {
    final formatter = NumberFormat('#,###${showDecimals ? '.##' : ''}', 'ar');
    return '${formatter.format(amount)} ${CurrencyConstants.currencySymbol}';
  }

  /// تنسيق المبلغ بدون رمز العملة (5,000)
  static String formatAmount(double amount, {bool showDecimals = false}) {
    final formatter = NumberFormat('#,###${showDecimals ? '.##' : ''}', 'ar');
    return formatter.format(amount);
  }

  /// تنسيق المبلغ بالفواصل الإنجليزية (للأنظمة التي لا تدعم الفواصل العربية)
  static String formatCurrencyEnglish(double amount, {bool showDecimals = false}) {
    final formatter = NumberFormat('#,###${showDecimals ? '.##' : ''}', 'en');
    return '${formatter.format(amount)} ${CurrencyConstants.currencySymbol}';
  }

  /// تنسيق المبلغ للعرض في واجهة المستخدم
  static String formatForDisplay(double amount, {bool showDecimals = false}) {
    return formatCurrency(amount, showDecimals: showDecimals);
  }

  /// تنسيق المبلغ للرسائل النصية (الواتساب)
  static String formatForMessage(double amount, {bool showDecimals = false}) {
    return formatCurrency(amount, showDecimals: showDecimals);
  }

  /// تحويل المبلغ من النص إلى رقم
  static double? parseAmount(String text) {
    // إزالة رمز العملة والفواصل
    String cleanText = text
        .replaceAll(CurrencyConstants.currencySymbol, '')
        .replaceAll('،', '')
        .replaceAll(',', '')
        .trim();
    
    return double.tryParse(cleanText);
  }

  /// إنشاء NumberFormat للاستخدام المتكرر
  static NumberFormat get defaultFormatter => NumberFormat('#,###', 'ar');
  static NumberFormat get decimalFormatter => NumberFormat('#,###.##', 'ar');
}