import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  group('Time utilities', () {
    group('nowEpoch', () {
      test('يجب إرجاع الوقت الحالي بالثواني', () {
        final epoch = Time.nowEpoch();
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        expect(epoch, closeTo(now, 1));
      });
    });

    group('nowIso', () {
      test('يجب إرجاع تاريخ ISO صحيح', () {
        final iso = Time.nowIso();
        expect(iso, contains('T'));
        expect(DateTime.tryParse(iso), isNotNull);
      });
    });

    group('nowDateString', () {
      test('يجب إرجاع تاريخ بتنسيق YYYY-MM-DD', () {
        final dateStr = Time.nowDateString();
        expect(dateStr, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      });
    });

    group('dateToString', () {
      test('يجب تحويل DateTime إلى سلسلة نصية', () {
        final date = DateTime(2024, 1, 15);
        expect(Time.dateToString(date), '2024-01-15');
      });

      test('يجب إضافة الأصفار للأرقام الصغيرة', () {
        final date = DateTime(2024, 3, 5);
        expect(Time.dateToString(date), '2024-03-05');
      });
    });

    group('hotelDayKey', () {
      test('قبل الساعة 14:00 يجب إرجاع اليوم السابق', () {
        final morning = DateTime(2024, 1, 15, 10);
        final key = Time.hotelDayKey(now: morning, cutoffHour: 14);
        expect(key, '2024-01-14');
      });

      test('بعد الساعة 14:00 يجب إرجاع اليوم الحالي', () {
        final evening = DateTime(2024, 1, 15, 16);
        final key = Time.hotelDayKey(now: evening, cutoffHour: 14);
        expect(key, '2024-01-15');
      });

      test('في تمام الساعة 14:00 يجب إرجاع اليوم الحالي', () {
        final cutoff = DateTime(2024, 1, 15, 14);
        final key = Time.hotelDayKey(now: cutoff, cutoffHour: 14);
        expect(key, '2024-01-15');
      });

      test('يجب دعم ساعات قطع مختلفة', () {
        final time = DateTime(2024, 1, 15, 11);
        expect(Time.hotelDayKey(now: time, cutoffHour: 12), '2024-01-14');
        expect(Time.hotelDayKey(now: time, cutoffHour: 10), '2024-01-15');
      });
    });

    group('hotelDayStart', () {
      test('يجب إرجاع بداية يوم الفندق للوقت بعد القطع', () {
        final evening = DateTime(2024, 1, 15, 18);
        final start = Time.hotelDayStart(evening, cutoffHour: 14);
        expect(start.year, 2024);
        expect(start.month, 1);
        expect(start.day, 15);
        expect(start.hour, 14);
      });

      test('يجب إرجاع بداية اليوم السابق للوقت قبل القطع', () {
        final morning = DateTime(2024, 1, 15, 10);
        final start = Time.hotelDayStart(morning, cutoffHour: 14);
        expect(start.day, 14);
        expect(start.hour, 14);
      });
    });

    group('hotelDayStartIso', () {
      test('يجب إرجاع تاريخ ISO لبداية يوم الفندق', () {
        final iso = Time.hotelDayStartIso('2024-01-15', cutoffHour: 14);
        expect(iso, '2024-01-15T14:00:00');
      });
    });

    group('hotelDayEndIso', () {
      test('يجب إرجاع تاريخ ISO لنهاية يوم الفندق', () {
        final iso = Time.hotelDayEndIso('2024-01-15', cutoffHour: 14);
        expect(iso, '2024-01-16T14:00:00');
      });
    });

    group('safeIsoToDateString', () {
      test('يجب تحويل تاريخ ISO إلى سلسلة تاريخ', () {
        expect(Time.safeIsoToDateString('2024-01-15T10:30:00'), '2024-01-15');
      });

      test('يجب معالجة التاريخ بدون وقت', () {
        expect(Time.safeIsoToDateString('2024-01-15'), '2024-01-15');
      });

      test('يجب إرجاع تاريخ اليوم للقيم الفارغة', () {
        final today = Time.nowDateString();
        expect(Time.safeIsoToDateString(null), today);
        expect(Time.safeIsoToDateString(''), today);
      });

      test('يجب إرجاع تاريخ اليوم للقيم غير الصالحة', () {
        final today = Time.nowDateString();
        expect(Time.safeIsoToDateString('invalid'), today);
      });
    });

    group('حالات حدية', () {
      test('منتصف الليل', () {
        final midnight = DateTime(2024, 1, 15);
        final key = Time.hotelDayKey(now: midnight, cutoffHour: 14);
        expect(key, '2024-01-14');
      });

      test('نهاية العام', () {
        final newYearsEve = DateTime(2024, 12, 31, 23, 59);
        final key = Time.hotelDayKey(now: newYearsEve, cutoffHour: 14);
        expect(key, '2024-12-31');
      });

      test('بداية العام', () {
        final newYear = DateTime(2024, 1, 1, 10);
        final key = Time.hotelDayKey(now: newYear, cutoffHour: 14);
        expect(key, '2023-12-31');
      });
    });
  });
}
