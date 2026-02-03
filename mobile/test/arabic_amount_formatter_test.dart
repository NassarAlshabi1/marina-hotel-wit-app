import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/arabic_amount_formatter.dart';

void main() {
  group('formatYemeniAmount', () {
    group('الأرقام الأساسية', () {
      test('يجب تحويل صفر', () {
        expect(formatYemeniAmount(0), 'صفر ريال يمني فقط');
      });

      test('يجب تحويل الآحاد', () {
        expect(formatYemeniAmount(1), 'واحد ريال يمني فقط');
        expect(formatYemeniAmount(2), 'اثنان ريال يمني فقط');
        expect(formatYemeniAmount(5), 'خمسة ريال يمني فقط');
        expect(formatYemeniAmount(9), 'تسعة ريال يمني فقط');
      });

      test('يجب تحويل العشرات', () {
        expect(formatYemeniAmount(10), 'عشرة ريال يمني فقط');
        expect(formatYemeniAmount(20), 'عشرون ريال يمني فقط');
        expect(formatYemeniAmount(50), 'خمسون ريال يمني فقط');
        expect(formatYemeniAmount(90), 'تسعون ريال يمني فقط');
      });

      test('يجب تحويل الأعداد المركبة (11-19)', () {
        expect(formatYemeniAmount(11), 'أحد عشر ريال يمني فقط');
        expect(formatYemeniAmount(12), 'اثنا عشر ريال يمني فقط');
        expect(formatYemeniAmount(15), 'خمسة عشر ريال يمني فقط');
        expect(formatYemeniAmount(19), 'تسعة عشر ريال يمني فقط');
      });

      test('يجب تحويل العشرات مع الآحاد', () {
        expect(formatYemeniAmount(21), 'واحد وعشرون ريال يمني فقط');
        expect(formatYemeniAmount(35), 'خمسة وثلاثون ريال يمني فقط');
        expect(formatYemeniAmount(99), 'تسعة وتسعون ريال يمني فقط');
      });
    });

    group('المئات', () {
      test('يجب تحويل المئات الصحيحة', () {
        expect(formatYemeniAmount(100), 'مائة ريال يمني فقط');
        expect(formatYemeniAmount(200), 'مائتان ريال يمني فقط');
        expect(formatYemeniAmount(500), 'خمسمائة ريال يمني فقط');
        expect(formatYemeniAmount(900), 'تسعمائة ريال يمني فقط');
      });

      test('يجب تحويل المئات مع العشرات', () {
        expect(formatYemeniAmount(150), 'مائة و خمسون ريال يمني فقط');
        expect(formatYemeniAmount(350), 'ثلاثمائة و خمسون ريال يمني فقط');
      });

      test('يجب تحويل المئات مع الآحاد', () {
        expect(formatYemeniAmount(101), 'مائة و واحد ريال يمني فقط');
        expect(formatYemeniAmount(505), 'خمسمائة و خمسة ريال يمني فقط');
      });

      test('يجب تحويل المئات مع العشرات والآحاد', () {
        expect(formatYemeniAmount(123), 'مائة و ثلاثة وعشرون ريال يمني فقط');
        expect(formatYemeniAmount(999), 'تسعمائة و تسعة وتسعون ريال يمني فقط');
      });
    });

    group('الآلاف', () {
      test('يجب تحويل الألف', () {
        expect(formatYemeniAmount(1000), 'ألف ريال يمني فقط');
      });

      test('يجب تحويل الألفين', () {
        expect(formatYemeniAmount(2000), 'ألفان ريال يمني فقط');
      });

      test('يجب تحويل الآلاف (3-10)', () {
        expect(formatYemeniAmount(3000), 'ثلاثة آلاف ريال يمني فقط');
        expect(formatYemeniAmount(5000), 'خمسة آلاف ريال يمني فقط');
        expect(formatYemeniAmount(10000), 'عشرة آلاف ريال يمني فقط');
      });

      test('يجب تحويل الآلاف الكبيرة', () {
        expect(formatYemeniAmount(15000), 'خمسة عشر ألف ريال يمني فقط');
        expect(
          formatYemeniAmount(42900),
          'اثنان وأربعون ألف و تسعمائة ريال يمني فقط',
        );
        expect(formatYemeniAmount(100000), 'مائة ألف ريال يمني فقط');
      });
    });

    group('الملايين', () {
      test('يجب تحويل المليون', () {
        expect(formatYemeniAmount(1000000), 'مليون ريال يمني فقط');
      });

      test('يجب تحويل المليونين', () {
        expect(formatYemeniAmount(2000000), 'مليونان ريال يمني فقط');
      });

      test('يجب تحويل الملايين (3-10)', () {
        expect(formatYemeniAmount(5000000), 'خمسة ملايين ريال يمني فقط');
      });
    });

    group('حالات واقعية من الفندق', () {
      test('أسعار الغرف الشائعة', () {
        expect(
          formatYemeniAmount(14300),
          'أربعة عشر ألف و ثلاثمائة ريال يمني فقط',
        );
        expect(
          formatYemeniAmount(42900),
          'اثنان وأربعون ألف و تسعمائة ريال يمني فقط',
        );
        expect(formatYemeniAmount(85000), 'خمسة وثمانون ألف ريال يمني فقط');
      });

      test('مبالغ متنوعة', () {
        expect(
          formatYemeniAmount(25500),
          'خمسة وعشرون ألف و خمسمائة ريال يمني فقط',
        );
        expect(formatYemeniAmount(150000), 'مائة و خمسون ألف ريال يمني فقط');
      });
    });

    group('الكسور العشرية', () {
      test('يجب تقريب الكسور', () {
        expect(formatYemeniAmount(1000.4), 'ألف ريال يمني فقط');
        expect(formatYemeniAmount(1000.5), 'ألف ريال يمني فقط');
        expect(formatYemeniAmount(1000.6), 'ألف و واحد ريال يمني فقط');
      });
    });
  });
}
