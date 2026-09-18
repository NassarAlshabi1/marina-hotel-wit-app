import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/utils/english_digits_input_formatter.dart';

void main() {
  const formatter = EnglishDigitsInputFormatter();

  test('يحوّل الأرقام العربية والفارسية إلى أرقام إنجليزية', () {
    final result = formatter.formatEditUpdate(
      const TextEditingValue(),
      const TextEditingValue(text: '١٢۳٤'),
    );

    expect(result.text, '1234');
  });

  test('يحذف الحروف والفواصل والكسور من حقول الأعداد الصحيحة', () {
    final result = formatter.formatEditUpdate(
      const TextEditingValue(),
      const TextEditingValue(text: '12.5 ريالabc,٣'),
    );

    expect(result.text, '1253');
  });

  test('يحافظ على الأرقام الإنجليزية الصالحة كما هي', () {
    final result = formatter.formatEditUpdate(
      const TextEditingValue(),
      const TextEditingValue(text: '42,900'),
    );

    expect(result.text, '42900');
  });
}
