import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  group('اختبارات منطق احتساب التكلفة الجديد - قاعدة 14:00', () {
    test('المثال الأصلي: دخول 05/11 19:00، خروج 06/11 14:01', () {
      final checkin = DateTime(2024, 11, 5, 19, 0);
      final checkout = DateTime(2024, 11, 6, 14, 1);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);
      const roomPrice = 15000.0;
      final totalCost = nights * roomPrice;

      expect(
        nights,
        2,
        reason:
            'يجب أن يكون يومين: يوم من 05/11 إلى 06/11، ويوم إضافي لأن المغادرة بعد 14:00',
      );
      expect(totalCost, 30000, reason: 'التكلفة = 2 أيام × 15000 = 30000');
    });

    test('مغادرة قبل 14:00 - لا يُضاف يوم إضافي', () {
      final checkin = DateTime(2024, 11, 5, 19, 0);
      final checkout = DateTime(2024, 11, 6, 13, 59);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

      expect(nights, 1, reason: 'يوم واحد فقط لأن المغادرة قبل 14:00');
    });

    test('مغادرة في تمام 14:00 - لا يُضاف يوم إضافي', () {
      final checkin = DateTime(2024, 11, 5, 19, 0);
      final checkout = DateTime(2024, 11, 6, 14, 0);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

      expect(nights, 1, reason: 'يوم واحد فقط لأن المغادرة في تمام 14:00');
    });

    test('مغادرة بعد 14:00 بدقيقة واحدة - يُضاف يوم إضافي', () {
      final checkin = DateTime(2024, 11, 5, 19, 0);
      final checkout = DateTime(2024, 11, 6, 14, 1);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

      expect(
        nights,
        2,
        reason: 'يومان: يوم أساسي + يوم إضافي للمغادرة بعد 14:00',
      );
    });

    test('إقامة في نفس اليوم - يوم واحد على الأقل', () {
      final checkin = DateTime(2024, 11, 5, 10, 0);
      final checkout = DateTime(2024, 11, 5, 13, 0);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

      expect(nights, 1, reason: 'الحد الأدنى يوم واحد حتى لو في نفس التاريخ');
    });

    test('إقامة في نفس اليوم مع مغادرة بعد 14:00', () {
      final checkin = DateTime(2024, 11, 5, 10, 0);
      final checkout = DateTime(2024, 11, 5, 15, 0);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

      expect(nights, 2, reason: 'يوم أساسي + يوم إضافي للمغادرة بعد 14:00');
    });

    test('إقامة يومين كاملين مع مغادرة قبل 14:00', () {
      final checkin = DateTime(2024, 11, 5, 19, 0);
      final checkout = DateTime(2024, 11, 7, 13, 0);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

      expect(
        nights,
        2,
        reason: 'يومان: من 05/11 إلى 06/11، ومن 06/11 إلى 07/11',
      );
    });

    test('إقامة يومين كاملين مع مغادرة بعد 14:00', () {
      final checkin = DateTime(2024, 11, 5, 19, 0);
      final checkout = DateTime(2024, 11, 7, 15, 0);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

      expect(nights, 3, reason: 'يومان أساسيان + يوم إضافي للمغادرة بعد 14:00');
    });

    test('إقامة أسبوع كامل مع مغادرة بعد 14:00', () {
      final checkin = DateTime(2024, 11, 5, 10, 0);
      final checkout = DateTime(2024, 11, 12, 16, 30);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

      expect(
        nights,
        9,
        reason: '7 أيام أساسية + يوم إضافي لكل تجاوز بعد 14:00',
      );
    });

    test('حالة حدية: منتصف الليل', () {
      final checkin = DateTime(2024, 11, 5, 23, 59);
      final checkout = DateTime(2024, 11, 6, 0, 1);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

      expect(
        nights,
        1,
        reason: 'يوم واحد للانتقال من يوم إلى آخر مع مغادرة قبل 14:00',
      );
    });

    test('حالة خاصة: دخول وخروج في ساعات الصباح الباكر', () {
      final checkin = DateTime(2024, 11, 5, 2, 0);
      final checkout = DateTime(2024, 11, 5, 6, 0);

      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

      expect(nights, 1, reason: 'الحد الأدنى يوم واحد');
    });

    test('اختبار شامل للتكلفة مع أسعار مختلفة', () {
      final testCases = [
        {
          'checkin': DateTime(2024, 11, 5, 19, 0),
          'checkout': DateTime(2024, 11, 6, 14, 1),
          'expectedDays': 2,
          'roomPrice': 15000.0,
          'expectedCost': 30000.0,
          'description': 'المثال الأصلي',
        },
        {
          'checkin': DateTime(2024, 11, 5, 19, 0),
          'checkout': DateTime(2024, 11, 8, 14, 1),
          'expectedDays': 4,
          'roomPrice': 20000.0,
          'expectedCost': 80000.0,
          'description': 'إقامة 3 أيام + يوم إضافي',
        },
        {
          'checkin': DateTime(2024, 11, 5, 10, 0),
          'checkout': DateTime(2024, 11, 5, 16, 0),
          'expectedDays': 2,
          'roomPrice': 12000.0,
          'expectedCost': 24000.0,
          'description': 'نفس اليوم مع مغادرة بعد 14:00',
        },
      ];

      for (final testCase in testCases) {
        final checkin = testCase['checkin'] as DateTime;
        final checkout = testCase['checkout'] as DateTime;
        final expectedDays = testCase['expectedDays'] as int;
        final roomPrice = testCase['roomPrice'] as double;
        final expectedCost = testCase['expectedCost'] as double;
        final description = testCase['description'] as String;

        final nights = Time.nightsWithCutoff(checkin, checkout: checkout);
        final totalCost = nights * roomPrice;

        expect(
          nights,
          expectedDays,
          reason: '$description - عدد الأيام غير صحيح',
        );
        expect(
          totalCost,
          expectedCost,
          reason: '$description - التكلفة الإجمالية غير صحيحة',
        );
      }
    });

    test('اختبار مع ساعات القطع المختلفة', () {
      final checkin = DateTime(2024, 11, 5, 19, 0);
      final checkout = DateTime(2024, 11, 6, 15, 1);

      // اختبار مع ساعة قطع 14:00 (الافتراضية)
      final nights14 = Time.nightsWithCutoff(
        checkin,
        checkout: checkout,
        cutoffHour: 14,
      );
      expect(nights14, 2, reason: 'مع ساعة قطع 14:00 يجب أن يكون يومين');

      // اختبار مع ساعة قطع 16:00
      final nights16 = Time.nightsWithCutoff(
        checkin,
        checkout: checkout,
        cutoffHour: 16,
      );
      expect(nights16, 1, reason: 'مع ساعة قطع 16:00 يجب أن يكون يوم واحد');

      // اختبار مع ساعة قطع 12:00
      final nights12 = Time.nightsWithCutoff(
        checkin,
        checkout: checkout,
        cutoffHour: 12,
      );
      expect(nights12, 2, reason: 'مع ساعة قطع 12:00 يجب أن يكون يومين');
    });

    test('اختبار checkout = null (يستخدم الوقت الحالي)', () {
      final checkin = DateTime.now().subtract(const Duration(days: 2));

      final nights = Time.nightsWithCutoff(checkin);

      expect(
        nights,
        greaterThanOrEqualTo(2),
        reason: 'يجب أن يكون على الأقل يومين للإقامة التي بدأت منذ يومين',
      );
    });

    test('حالات حدية للأوقات', () {
      final testCases = [
        {
          'checkout': DateTime(
            2024,
            11,
            6,
            13,
            59,
            59,
          ), // قبل 14:00 بثانية واحدة
          'expectedDays': 1,
          'description': 'قبل 14:00 بثانية واحدة',
        },
        {
          'checkout': DateTime(2024, 11, 6, 14, 0, 0), // تمام 14:00
          'expectedDays': 1,
          'description': 'تمام الساعة 14:00',
        },
        {
          'checkout': DateTime(2024, 11, 6, 14, 0, 1), // بعد 14:00 بثانية واحدة
          'expectedDays': 2,
          'description': 'بعد 14:00 بثانية واحدة',
        },
        {
          'checkout': DateTime(2024, 11, 6, 23, 59, 59), // آخر ثانية في اليوم
          'expectedDays': 2,
          'description': 'آخر ثانية في اليوم',
        },
      ];

      for (final testCase in testCases) {
        final checkin = DateTime(2024, 11, 5, 19, 0);
        final checkout = testCase['checkout'] as DateTime;
        final expectedDays = testCase['expectedDays'] as int;
        final description = testCase['description'] as String;

        final nights = Time.nightsWithCutoff(checkin, checkout: checkout);

        expect(
          nights,
          expectedDays,
          reason: '$description - النتيجة غير صحيحة',
        );
      }
    });
  });
}
