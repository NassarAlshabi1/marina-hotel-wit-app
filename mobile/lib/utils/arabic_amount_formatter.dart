String formatYemeniAmount(double amount) {
  final intAmount = amount.round();
  final words = _convertNumberToArabicWords(intAmount);
  return '$words ريال يمني فقط';
}

String _convertNumberToArabicWords(int number) {
  if (number == 0) {
    return 'صفر';
  }
  final segments = <String>[];
  var remainder = number;
  final million = remainder ~/ 1000000;
  if (million > 0) {
    segments.add(_formatWithScale(million, 'مليون', 'مليونان', 'ملايين'));
    remainder %= 1000000;
  }
  final thousand = remainder ~/ 1000;
  if (thousand > 0) {
    segments.add(_formatWithScale(thousand, 'ألف', 'ألفان', 'آلاف'));
    remainder %= 1000;
  }
  if (remainder > 0) {
    segments.add(_convertBelowThousand(remainder));
  }
  return segments.join(' و ');
}

String _formatWithScale(int value, String singular, String dual, String plural) {
  if (value == 1) {
    return singular;
  }
  if (value == 2) {
    return dual;
  }
  final words = _convertBelowThousand(value);
  if (value >= 3 && value <= 10) {
    return '$words $plural';
  }
  return '$words $singular';
}

String _convertBelowThousand(int number) {
  final hundreds = number ~/ 100;
  final remainder = number % 100;
  final parts = <String>[];
  if (hundreds > 0) {
    parts.add(_hundredsMap[hundreds]!);
  }
  if (remainder > 0) {
    final remainderWords = _convertBelowHundred(remainder);
    if (remainderWords.isNotEmpty) {
      parts.add(remainderWords);
    }
  }
  return parts.join(' و ');
}

String _convertBelowHundred(int number) {
  if (number == 0) {
    return '';
  }
  if (number < 10) {
    return _units[number];
  }
  if (number == 10) {
    return 'عشرة';
  }
  if (number < 20) {
    return _teens[number - 11];
  }
  final tens = number ~/ 10;
  final units = number % 10;
  final tensWord = _tens[tens];
  if (units == 0) {
    return tensWord;
  }
  final unitWord = _units[units];
  return '$unitWord و$tensWord';
}

const _units = <String>[
  '',
  'واحد',
  'اثنان',
  'ثلاثة',
  'أربعة',
  'خمسة',
  'ستة',
  'سبعة',
  'ثمانية',
  'تسعة',
];

const _teens = <String>[
  'أحد عشر',
  'اثنا عشر',
  'ثلاثة عشر',
  'أربعة عشر',
  'خمسة عشر',
  'ستة عشر',
  'سبعة عشر',
  'ثمانية عشر',
  'تسعة عشر',
];

const _tens = <String>[
  '',
  '',
  'عشرون',
  'ثلاثون',
  'أربعون',
  'خمسون',
  'ستون',
  'سبعون',
  'ثمانون',
  'تسعون',
];

const _hundredsMap = <int, String>{
  1: 'مائة',
  2: 'مائتان',
  3: 'ثلاثمائة',
  4: 'أربعمائة',
  5: 'خمسمائة',
  6: 'ستمائة',
  7: 'سبعمائة',
  8: 'ثمانمائة',
  9: 'تسعمائة',
};
