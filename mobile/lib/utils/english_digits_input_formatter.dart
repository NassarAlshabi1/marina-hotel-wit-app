import 'package:flutter/services.dart';

/// سياسة إدخال الأرقام في التطبيق.
///
/// كل ما يصل إلى الواجهة من لوحة المفاتيح يُحفظ بصيغة ASCII (`0-9`).
/// إذا أرسل نظام الإدخال أرقاماً عربية أو فارسية، تُحوّل إلى ASCII بدلاً
/// من تركها مختلطة داخل الحقل.
class EnglishDigitsInputFormatter extends TextInputFormatter {
  const EnglishDigitsInputFormatter({this.allowDecimal = false});

  /// حقول المبالغ في الفندق أعداد صحيحة، لذلك القيمة الافتراضية false.
  final bool allowDecimal;

  static const _arabicDigits = <String, String>{
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

  static String normalize(String value) {
    return value.split('').map((character) {
      return _arabicDigits[character] ?? character;
    }).join();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = normalize(newValue.text);
    final allowed = allowDecimal ? RegExp('[^0-9.]') : RegExp('[^0-9]');
    var filtered = normalized.replaceAll(allowed, '');

    if (allowDecimal) {
      final firstDot = filtered.indexOf('.');
      if (firstDot >= 0) {
        filtered =
            filtered.substring(0, firstDot + 1) +
            filtered.substring(firstDot + 1).replaceAll('.', '');
      }
    }

    final selectionOffset = newValue.selection.baseOffset
        .clamp(0, filtered.length)
        ;
    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: selectionOffset),
    );
  }
}

/// منسق الحقول التي تمثل أعداداً صحيحة، مثل المبالغ والعدادات والمعرّفات.
const englishIntegerInputFormatter = EnglishDigitsInputFormatter();
