// ============================================================================
//  DateParser — Unit Tests
//  ============================================================================
//  اختبارات أداة DateParser:
//    - تحويل صيغ ISO المختلفة إلى DateTime
//    - التعامل مع القيم الفارغة وغير الصالحة
//    - التطابق مع صيغ الإدخال المختلفة (T أو مسافة، مع/بدون ثوانٍ)
// ============================================================================

library marina_hotel_mobile.test.date_parser_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/date_parser.dart';

void main() {
  group('DateParser.parse', () {
    test('يُرجع null للقيم null', () {
      expect(DateParser.parse(null), isNull);
    });

    test('يُرجع null للقيم الفارغة', () {
      expect(DateParser.parse(''), isNull);
      expect(DateParser.parse('   '), isNull);
    });

    test('يُرجع null للقيم غير الصالحة', () {
      expect(DateParser.parse('not-a-date'), isNull);
      expect(DateParser.parse('xyz'), isNull);
    });

    test('يُحلّ صيغة ISO الكاملة مع T', () {
      final result = DateParser.parse('2026-08-06T14:30:00');
      expect(result, isNotNull);
      expect(result!.year, 2026);
      expect(result.month, 8);
      expect(result.day, 6);
      expect(result.hour, 14);
      expect(result.minute, 30);
      expect(result.second, 0);
    });

    test('يُحلّ صيغة التاريخ مع مسافة بدلاً من T', () {
      final result = DateParser.parse('2026-08-06 14:30');
      expect(result, isNotNull);
      expect(result!.year, 2026);
      expect(result.month, 8);
      expect(result.day, 6);
      expect(result.hour, 14);
      expect(result.minute, 30);
    });

    test('يُحلّ صيغة ISO بدون ثوانٍ', () {
      final result = DateParser.parse('2026-08-06T14:30');
      expect(result, isNotNull);
      expect(result!.hour, 14);
      expect(result.minute, 30);
      expect(result.second, 0);
    });

    test('يُحلّ صيغة ISO مع ميلي ثانية', () {
      final result = DateParser.parse('2026-08-06T14:30:00.123');
      expect(result, isNotNull);
      expect(result!.hour, 14);
    });

    test('يحافظ على قيم التاريخ الكاملة', () {
      final result = DateParser.parse('2026-12-31T23:59:59');
      expect(result, isNotNull);
      expect(result!.year, 2026);
      expect(result.month, 12);
      expect(result.day, 31);
      expect(result.hour, 23);
      expect(result.minute, 59);
      expect(result.second, 59);
    });

    test('يُحلّ تاريخاً مع مسافات بادئة/خلفية', () {
      final result = DateParser.parse('  2026-08-06T14:30:00  ');
      expect(result, isNotNull);
      expect(result!.year, 2026);
      expect(result.month, 8);
    });

    test('يُحلّ تواريخ من سنوات مختلفة', () {
      expect(DateParser.parse('2020-01-01T00:00:00')!.year, 2020);
      expect(DateParser.parse('2025-06-15T12:30:00')!.month, 6);
      expect(DateParser.parse('2030-12-31T23:59:00')!.day, 31);
    });
  });
}
