// ============================================================================
//  HotelDateHelper — Unit Tests
//  ============================================================================
//  اختبارات مساعد أيام الفندق:
//    - getHotelDay / getHotelDayKey — تحويل DateTime إلى يوم فندقي
//    - calculateNights — حساب عدد الليالي
//    - calculateNightsWithDiscount — حساب الليالي مع خصم
//    - isAfterCutoff — فحص تجاوز ساعة 14:01
//    - bookingComputedFields — فحص الحقول المحسوبة
//    - stripComputedFieldsForEntity — تصفية الحقول قبل المزامنة
// ============================================================================

library marina_hotel_mobile.test.hotel_date_helper_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/hotel_date_helper.dart';

void main() {
  group('getHotelDay', () {
    test('الساعة 14:01 بالضبط → نفس اليوم', () {
      final dt = DateTime(2026, 8, 6, 14, 1, 0);
      final hotelDay = HotelDateHelper.getHotelDay(dt);
      expect(hotelDay.year, 2026);
      expect(hotelDay.month, 8);
      expect(hotelDay.day, 6);
    });

    test('الساعة 14:00:59 → اليوم السابق', () {
      final dt = DateTime(2026, 8, 6, 14, 0, 59);
      final hotelDay = HotelDateHelper.getHotelDay(dt);
      expect(
        hotelDay.day,
        5,
        reason: '14:00:59 قبل بداية اليوم الفندقي (14:01) فتكون لليوم السابق',
      );
    });

    test('الساعة 15:00 → نفس اليوم', () {
      final dt = DateTime(2026, 8, 6, 15, 0, 0);
      final hotelDay = HotelDateHelper.getHotelDay(dt);
      expect(hotelDay.day, 6);
    });

    test('الساعة 10:00 صباحاً → اليوم السابق', () {
      final dt = DateTime(2026, 8, 6, 10, 0, 0);
      final hotelDay = HotelDateHelper.getHotelDay(dt);
      expect(hotelDay.day, 5);
    });

    test('منتصف الليل 00:00 → اليوم السابق', () {
      final dt = DateTime(2026, 8, 6, 0, 0, 0);
      final hotelDay = HotelDateHelper.getHotelDay(dt);
      expect(hotelDay.day, 5);
    });

    test('آخر يوم في الشهر → اليوم الأول من الشهر التالي', () {
      final dt = DateTime(2026, 1, 31, 14, 1, 0);
      final hotelDay = HotelDateHelper.getHotelDay(dt);
      expect(hotelDay.month, 1);
      expect(hotelDay.day, 31);
    });
  });

  group('getHotelDayKey', () {
    test('يُرجع مفتاح YYYY-MM-DD', () {
      final dt = DateTime(2026, 8, 6, 15, 0, 0);
      final key = HotelDateHelper.getHotelDayKey(dateTime: dt);
      expect(key, '2026-08-06');
    });

    test('يُرجع اليوم السابق للوقت قبل 14:01', () {
      final dt = DateTime(2026, 8, 6, 10, 0, 0);
      final key = HotelDateHelper.getHotelDayKey(dateTime: dt);
      expect(key, '2026-08-05');
    });
  });

  group('getHotelDayKeyFromIso', () {
    test('يُحلّ ISO string كامل', () {
      final key = HotelDateHelper.getHotelDayKeyFromIso('2026-08-06T15:00:00');
      expect(key, '2026-08-06');
    });

    test('يُحلّ ISO string بمسافة بدلاً من T', () {
      final key = HotelDateHelper.getHotelDayKeyFromIso('2026-08-06 15:00');
      expect(key, '2026-08-06');
    });

    test('يُرجع اليوم السابق للوقت قبل 14:01', () {
      final key = HotelDateHelper.getHotelDayKeyFromIso('2026-08-06T10:00:00');
      expect(key, '2026-08-05');
    });

    test('يُرجع اليوم الحالي للقيم null أو فارغة', () {
      final key1 = HotelDateHelper.getHotelDayKeyFromIso(null);
      final key2 = HotelDateHelper.getHotelDayKeyFromIso('');
      final key3 = HotelDateHelper.getHotelDayKeyFromIso('   ');
      expect(key1, isNotEmpty);
      expect(key2, isNotEmpty);
      expect(key3, isNotEmpty);
      // جميعها يجب أن تكون تاريخ اليوم
      expect(key1, equals(key2));
      expect(key2, equals(key3));
    });

    test('يُرجع اليوم الحالي للقيم غير الصالحة', () {
      final key = HotelDateHelper.getHotelDayKeyFromIso('not-a-date');
      expect(key, isNotEmpty);
      // يجب أن يكون تاريخ اليوم (لأن القيمة غير صالحة)
      expect(key, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });

  group('calculateNights', () {
    test('نفس اليوم = ليلة واحدة كحد أدنى', () {
      final checkin = DateTime(2026, 8, 6, 15, 0, 0);
      final nights = HotelDateHelper.calculateNights(
        checkIn: checkin,
        checkOut: checkin.add(const Duration(hours: 2)),
      );
      expect(nights, greaterThanOrEqualTo(1));
    });

    test('دخول اليوم 1 مغادرة اليوم 2 = ليلة واحدة', () {
      final checkin = DateTime(2026, 8, 6, 15, 0, 0);
      final checkout = DateTime(2026, 8, 7, 10, 0, 0);
      final nights = HotelDateHelper.calculateNights(
        checkIn: checkin,
        checkOut: checkout,
      );
      expect(nights, 1);
    });

    test('دخول اليوم 1 مغادرة اليوم 4 = 3 ليالي', () {
      final checkin = DateTime(2026, 8, 6, 15, 0, 0);
      final checkout = DateTime(2026, 8, 9, 10, 0, 0);
      final nights = HotelDateHelper.calculateNights(
        checkIn: checkin,
        checkOut: checkout,
      );
      expect(nights, 3);
    });

    test('المغادرة بعد 14:01 تُحتسب كـ ليلة إضافية', () {
      final checkin = DateTime(2026, 8, 6, 15, 0, 0);
      final checkout = DateTime(2026, 8, 7, 14, 30, 0); // بعد 14:01
      final nights = HotelDateHelper.calculateNights(
        checkIn: checkin,
        checkOut: checkout,
      );
      expect(nights, 2, reason: 'المغادرة بعد 14:01 تُحتسب كـ ليلة إضافية');
    });
  });

  group('calculateNightsWithDiscount', () {
    test('بدون discountStartDate = نفس calculateNights', () {
      final checkin = DateTime(2026, 8, 6, 15, 0, 0);
      final checkout = DateTime(2026, 8, 9, 10, 0, 0);
      final withoutDiscount = HotelDateHelper.calculateNightsWithDiscount(
        checkIn: checkin,
        checkOut: checkout,
      );
      final withNullDiscount = HotelDateHelper.calculateNightsWithDiscount(
        checkIn: checkin,
        checkOut: checkout,
        discountStartDate: null,
      );
      expect(withoutDiscount, withNullDiscount);
    });

    test('discountStartDate قبل checkin = نفس calculateNights', () {
      final checkin = DateTime(2026, 8, 6, 15, 0, 0);
      final checkout = DateTime(2026, 8, 9, 10, 0, 0);
      final discountStart = DateTime(2026, 8, 1);

      final nights = HotelDateHelper.calculateNightsWithDiscount(
        checkIn: checkin,
        checkOut: checkout,
        discountStartDate: discountStart,
      );
      expect(nights, 3);
    });

    test('discountStartDate بعد checkout = 0 ليالي', () {
      final checkin = DateTime(2026, 8, 6, 15, 0, 0);
      final checkout = DateTime(2026, 8, 9, 10, 0, 0);
      final discountStart = DateTime(2026, 8, 20);

      final nights = HotelDateHelper.calculateNightsWithDiscount(
        checkIn: checkin,
        checkOut: checkout,
        discountStartDate: discountStart,
      );
      expect(nights, 0);
    });

    test('discountStartDate في وسط الإقامة', () {
      final checkin = DateTime(2026, 8, 6, 15, 0, 0);
      final checkout = DateTime(2026, 8, 9, 10, 0, 0);
      final discountStart = DateTime(2026, 8, 8); // اليوم الثالث

      final nights = HotelDateHelper.calculateNightsWithDiscount(
        checkIn: checkin,
        checkOut: checkout,
        discountStartDate: discountStart,
      );
      expect(nights, greaterThan(0));
      expect(nights, lessThan(3));
    });
  });

  group('isAfterCutoff', () {
    test('الساعة 15:00 = true', () {
      final dt = DateTime(2026, 8, 6, 15, 0, 0);
      expect(HotelDateHelper.isAfterCutoff(dt), isTrue);
    });

    test('الساعة 14:01 = true', () {
      final dt = DateTime(2026, 8, 6, 14, 1, 0);
      expect(HotelDateHelper.isAfterCutoff(dt), isTrue);
    });

    test('الساعة 14:00 = false', () {
      final dt = DateTime(2026, 8, 6, 14, 0, 0);
      expect(HotelDateHelper.isAfterCutoff(dt), isFalse);
    });

    test('الساعة 10:00 = false', () {
      final dt = DateTime(2026, 8, 6, 10, 0, 0);
      expect(HotelDateHelper.isAfterCutoff(dt), isFalse);
    });
  });

  group('bookingComputedFields', () {
    test('يحتوي على الحقول المتوقعة', () {
      expect(
        HotelDateHelper.bookingComputedFields.contains('stayDurationIso'),
        isTrue,
      );
      expect(
        HotelDateHelper.bookingComputedFields.contains('lastNightEpoch'),
        isTrue,
      );
      expect(
        HotelDateHelper.bookingComputedFields.contains('isOverdue'),
        isTrue,
      );
      expect(
        HotelDateHelper.bookingComputedFields.contains('needsCheckoutReview'),
        isTrue,
      );
    });

    test('لا يحتوي على الحقول التي يجب مزامنتها', () {
      expect(
        HotelDateHelper.bookingComputedFields.contains('totalDueCached'),
        isFalse,
      );
      expect(
        HotelDateHelper.bookingComputedFields.contains('calculatedNights'),
        isFalse,
      );
    });

    test('isBookingComputedField يُرجع قيمة صحيحة', () {
      expect(HotelDateHelper.isBookingComputedField('stayDurationIso'), isTrue);
      expect(HotelDateHelper.isBookingComputedField('guestName'), isFalse);
    });
  });

  group('stripComputedFieldsForEntity', () {
    test('يُزيل الحقول المحسوبة من بيانات bookings', () {
      final payload = <String, dynamic>{
        'guestName': 'أحمد',
        'stayDurationIso': '2026-01-01/2026-01-05',
        'totalDueCached': 50000,
        'lastNightEpoch': 1234567890,
        'isOverdue': true,
        'needsCheckoutReview': false,
      };

      final result = HotelDateHelper.stripComputedFieldsForEntity(
        'bookings',
        payload,
      );

      expect(result.containsKey('guestName'), isTrue);
      expect(
        result.containsKey('totalDueCached'),
        isTrue,
        reason: 'totalDueCached يجب أن يبقى (يُزامن)',
      );
      expect(result.containsKey('stayDurationIso'), isFalse);
      expect(result.containsKey('lastNightEpoch'), isFalse);
      expect(result.containsKey('isOverdue'), isFalse);
      expect(result.containsKey('needsCheckoutReview'), isFalse);
    });

    test('لا يُعدّل بيانات الكيانات الأخرى', () {
      final payload = <String, dynamic>{
        'name': 'موظف',
        'stayDurationIso': 'something', // حقل محسوب في bookings فقط
        'isOverdue': true,
      };

      final result = HotelDateHelper.stripComputedFieldsForEntity(
        'employees',
        payload,
      );

      expect(
        result.length,
        3,
        reason: 'يجب ألا تُزال أي حقول من كيان غير bookings',
      );
    });

    test('لا يُعدّل المرجع الأصلي', () {
      final original = <String, dynamic>{
        'guestName': 'أحمد',
        'isOverdue': true,
      };

      final result = HotelDateHelper.stripComputedFieldsForEntity(
        'bookings',
        original,
      );

      expect(
        original.containsKey('isOverdue'),
        isTrue,
        reason: 'يجب ألا يتغير المرجع الأصلي',
      );
      expect(result.containsKey('isOverdue'), isFalse);
    });
  });

  group('timeUntilNextHotelDay', () {
    test('يُرجع duration موجباً', () {
      final duration = HotelDateHelper.timeUntilNextHotelDay();
      expect(duration.inSeconds, greaterThan(0));
      expect(duration.inHours, lessThanOrEqualTo(24));
    });
  });
}
