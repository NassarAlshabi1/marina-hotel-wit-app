import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/date_parser.dart';

void main() {
  group('DateParser.parse', () {
    group('يجب إرجاع null للقيم الفارغة', () {
      test('null يجب أن يرجع null', () {
        expect(DateParser.parse(null), isNull);
      });

      test('النص الفارغ يجب أن يرجع null', () {
        expect(DateParser.parse(''), isNull);
      });

      test('النص المسافات فقط يجب أن يرجع null', () {
        expect(DateParser.parse('   '), isNull);
      });
    });

    group('يجب تحليل صيغة ISO كاملة', () {
      test('صيغة ISO مع ثوانٍ', () {
        final result = DateParser.parse('2025-01-15T14:30:00');
        expect(result, isNotNull);
        expect(result!.year, 2025);
        expect(result.month, 1);
        expect(result.day, 15);
        expect(result.hour, 14);
        expect(result.minute, 30);
        expect(result.second, 0);
      });

      test('صيغة ISO بدون ثوانٍ', () {
        final result = DateParser.parse('2025-06-20T08:15');
        expect(result, isNotNull);
        expect(result!.year, 2025);
        expect(result.month, 6);
        expect(result.day, 20);
        expect(result.hour, 8);
        expect(result.minute, 15);
        expect(result.second, 0);
      });

      test('صيغة ISO مع ميلي ثانية', () {
        final result = DateParser.parse('2025-01-15T14:30:00.123');
        expect(result, isNotNull);
        expect(result!.year, 2025);
        expect(result.month, 1);
        expect(result.day, 15);
      });
    });

    group('يجب تحليل صيغة بمسافة بدل T', () {
      test('صيغة بمسافة مع ثوانٍ', () {
        final result = DateParser.parse('2025-03-10 12:45:30');
        expect(result, isNotNull);
        expect(result!.year, 2025);
        expect(result.month, 3);
        expect(result.day, 10);
        expect(result.hour, 12);
        expect(result.minute, 45);
        expect(result.second, 30);
      });

      test('صيغة بمسافة بدون ثوانٍ', () {
        final result = DateParser.parse('2025-03-10 12:45');
        expect(result, isNotNull);
        expect(result!.year, 2025);
        expect(result.month, 3);
        expect(result.day, 10);
        expect(result.hour, 12);
        expect(result.minute, 45);
        expect(result.second, 0);
      });
    });

    group('يجب تجاهل المسافات الزائدة', () {
      test('نص مع مسافات زائدة في البداية والنهاية', () {
        final result = DateParser.parse('  2025-01-15T14:30  ');
        expect(result, isNotNull);
        expect(result!.year, 2025);
        expect(result.month, 1);
        expect(result.day, 15);
      });
    });

    group('يجب إرجاع null للتواريخ غير الصالحة', () {
      test('صيغة غير صالحة', () {
        expect(DateParser.parse('not-a-date'), isNull);
      });

      test('صيغة تاريخ غير موجودة', () {
        expect(DateParser.parse('2025-13-45T14:30'), isNull);
      });

      test('نص عشوائي', () {
        expect(DateParser.parse('abc123xyz'), isNull);
      });
    });

    group('يجب التعامل مع تواريخ نهاية اليوم', () {
      test('توقيت منتصف الليل', () {
        final result = DateParser.parse('2025-12-31T23:59:59');
        expect(result, isNotNull);
        expect(result!.year, 2025);
        expect(result.month, 12);
        expect(result.day, 31);
      });
    });
  });
}