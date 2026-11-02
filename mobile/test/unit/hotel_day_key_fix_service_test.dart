import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/hotel_day_key_fix_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // computeCorrectHotelDayKey — حساب مفتاح اليوم الفندقي
  // ═══════════════════════════════════════════════════════════════
  group('HotelDayKeyFixService — computeCorrectHotelDayKey', () {
    test('تاريخ تقويمي (yyyy-MM-dd) يعيد نفس اليوم (لأنه يمرر 14:01)', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey('2025-06-15');
      expect(key, '2025-06-15');
    });

    test('تاريخ ISO بعد 14:01 يعود لنفس اليوم', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey(
        '2025-06-15 15:00:00',
      );
      expect(key, '2025-06-15');
    });

    test('تاريخ ISO قبل 14:01 يعود لليوم السابق', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey(
        '2025-06-15 10:00:00',
      );
      expect(key, '2025-06-14');
    });

    test('تاريخ ISO بالضبط 14:00 يعود لليوم السابق', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey(
        '2025-06-15 14:00:00',
      );
      expect(key, '2025-06-14');
    });

    test('تاريخ ISO بالضبط 14:01 يعود لنفس اليوم', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey(
        '2025-06-15 14:01:00',
      );
      expect(key, '2025-06-15');
    });

    test('تاريخ ISO بتنسيق T', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey(
        '2025-06-15T15:30:00',
      );
      expect(key, '2025-06-15');
    });

    test('تاريخ ISO بتنسيق T قبل الحد', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey(
        '2025-06-15T10:00:00',
      );
      expect(key, '2025-06-14');
    });

    test('سلسلة فارغة تعيد مفتاح اليوم الحالي', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey('');
      expect(key.length, 10);
    });

    test('تاريخ غير صالح يعيد مفتاح اليوم الحالي', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey('not-a-date');
      expect(key.length, 10);
    });

    test('تاريخ مع مسافات بادئة/خلفية', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey(
        '  2025-06-15  ',
      );
      expect(key, '2025-06-15');
    });

    test('تاريخ تقويمي بتنسيق غير صالح (أجزاء < 3)', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey('2025-06');
      expect(key.length, 10); // يقع في اليوم الحالي
    });

    test('منتصف الليل (00:00) يعود لليوم السابق', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey(
        '2025-06-15 00:00:00',
      );
      expect(key, '2025-06-14');
    });

    test('قيمة حدية: بداية سنة جديدة', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey('2025-01-01');
      expect(key, '2025-01-01');
    });

    test('قيمة حدية: بداية سنة جديدة مع وقت مبكر', () {
      final key = HotelDayKeyFixService.computeCorrectHotelDayKey(
        '2025-01-01 10:00:00',
      );
      expect(key, '2024-12-31');
    });
  });
}
