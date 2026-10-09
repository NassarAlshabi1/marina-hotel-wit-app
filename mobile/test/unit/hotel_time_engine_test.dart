import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // ثوابت اليوم الفندقي
  // ═══════════════════════════════════════════════════════════════
  group('HotelTimeEngine — ثوابت اليوم الفندقي', () {
    test('boundaryHour = 14 و boundaryMinute = 1', () {
      expect(HotelTimeEngine.boundaryHour, 14);
      expect(HotelTimeEngine.boundaryMinute, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // getHotelDay — تحويل التاريخ إلى يوم فندقي
  // ═══════════════════════════════════════════════════════════════
  group('getHotelDay', () {
    test('الوقت بعد 14:01 يعود لنفس اليوم', () {
      final dt = DateTime(2025, 6, 15, 14, 1);
      final result = HotelTimeEngine.getHotelDay(dt);
      expect(result, DateTime(2025, 6, 15));
    });

    test('الوقت بعد 14:01 بفترة يعود لنفس اليوم', () {
      final dt = DateTime(2025, 6, 15, 20, 0);
      final result = HotelTimeEngine.getHotelDay(dt);
      expect(result, DateTime(2025, 6, 15));
    });

    test('الوقت قبل 14:01 يعود لليوم السابق', () {
      final dt = DateTime(2025, 6, 15, 10, 0);
      final result = HotelTimeEngine.getHotelDay(dt);
      expect(result, DateTime(2025, 6, 14));
    });

    test('الوقت بالضبط 14:00 يعود لليوم السابق', () {
      final dt = DateTime(2025, 6, 15, 14, 0);
      final result = HotelTimeEngine.getHotelDay(dt);
      expect(result, DateTime(2025, 6, 14));
    });

    test('الوقت بالضبط 14:00:59 يعود لليوم السابق', () {
      final dt = DateTime(2025, 6, 15, 14, 0, 59);
      final result = HotelTimeEngine.getHotelDay(dt);
      expect(result, DateTime(2025, 6, 14));
    });

    test('الوقت بالضبط 14:01:00 يعود لنفس اليوم', () {
      final dt = DateTime(2025, 6, 15, 14, 1, 0);
      final result = HotelTimeEngine.getHotelDay(dt);
      expect(result, DateTime(2025, 6, 15));
    });

    test('منتصف الليل (00:00) يعود لليوم السابق', () {
      final dt = DateTime(2025, 6, 15, 0, 0);
      final result = HotelTimeEngine.getHotelDay(dt);
      expect(result, DateTime(2025, 6, 14));
    });

    test('بداية سنة جديدة — 1 يناير 00:00 يعود لـ 31 ديسمبر', () {
      final dt = DateTime(2025, 1, 1, 0, 0);
      final result = HotelTimeEngine.getHotelDay(dt);
      expect(result, DateTime(2024, 12, 31));
    });

    test('بداية سنة جديدة — 1 يناير 14:01 يعود لنفس اليوم', () {
      final dt = DateTime(2025, 1, 1, 14, 1);
      final result = HotelTimeEngine.getHotelDay(dt);
      expect(result, DateTime(2025, 1, 1));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // getHotelDayKey — مفتاح اليوم الفندقي YYYY-MM-DD
  // ═══════════════════════════════════════════════════════════════
  group('getHotelDayKey', () {
    test('يعيد نص بصيغة YYYY-MM-DD', () {
      final key = HotelTimeEngine.getHotelDayKey(
        dateTime: DateTime(2025, 6, 15, 15, 0),
      );
      expect(key, '2025-06-15');
    });

    test('قبل 14:01 يعود لليوم السابق', () {
      final key = HotelTimeEngine.getHotelDayKey(
        dateTime: DateTime(2025, 6, 15, 13, 59),
      );
      expect(key, '2025-06-14');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // getHotelDayKeyFromIso — من سلسلة ISO
  // ═══════════════════════════════════════════════════════════════
  group('getHotelDayKeyFromIso', () {
    test('صيغة ISO مع T تعمل بشكل صحيح', () {
      final key = HotelTimeEngine.getHotelDayKeyFromIso('2025-06-15T15:00:00');
      expect(key, '2025-06-15');
    });

    test('صيغة ISO مع مسافة تعمل بشكل صحيح', () {
      final key = HotelTimeEngine.getHotelDayKeyFromIso('2025-06-15 15:00:00');
      expect(key, '2025-06-15');
    });

    test('قبل 14:01 يعود لليوم السابق', () {
      final key = HotelTimeEngine.getHotelDayKeyFromIso('2025-06-15T10:00:00');
      expect(key, '2025-06-14');
    });

    test('قيمة null تعيد مفتاح اليوم الحالي', () {
      final key = HotelTimeEngine.getHotelDayKeyFromIso(null);
      expect(key.length, 10);
    });

    test('سلسلة فارغة تعيد مفتاح اليوم الحالي', () {
      final key = HotelTimeEngine.getHotelDayKeyFromIso('');
      expect(key.length, 10);
    });

    test('تاريخ غير صالح يعيد مفتاح اليوم الحالي', () {
      final key = HotelTimeEngine.getHotelDayKeyFromIso('not-a-date');
      expect(key.length, 10);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // calculateTotal — حساب المبلغ الإجمالي
  // ═══════════════════════════════════════════════════════════════
  group('calculateTotal', () {
    test('3 ليالي × 100 ريال = 300', () {
      expect(HotelTimeEngine.calculateTotal(days: 3, roomPrice: 100), 300);
    });

    test('خصم كلي: 3 ليالي × 100 - خصم 50 = 250', () {
      expect(
        HotelTimeEngine.calculateTotal(
          days: 3,
          roomPrice: 100,
          discount: 50,
          discountType: 'total',
        ),
        250,
      );
    });

    test('خصم لكل ليلة: 3 ليالي × 100 - خصم 10×3 = 270', () {
      expect(
        HotelTimeEngine.calculateTotal(
          days: 3,
          roomPrice: 100,
          discount: 10,
          discountType: 'per_night',
        ),
        270,
      );
    });

    test('أيام <= 0 تعيد 0', () {
      expect(HotelTimeEngine.calculateTotal(days: 0, roomPrice: 100), 0);
      expect(HotelTimeEngine.calculateTotal(days: -1, roomPrice: 100), 0);
    });

    test('سعر <= 0 يعيد 0', () {
      expect(HotelTimeEngine.calculateTotal(days: 3, roomPrice: 0), 0);
      expect(HotelTimeEngine.calculateTotal(days: 3, roomPrice: -50), 0);
    });

    test('الخصم أكبر من المجموع يعيد 0 (لا مبلغ سالب)', () {
      expect(
        HotelTimeEngine.calculateTotal(
          days: 1,
          roomPrice: 50,
          discount: 100,
          discountType: 'total',
        ),
        0,
      );
    });

    test('خصم لكل ليلة أكبر من السعر يعيد 0', () {
      expect(
        HotelTimeEngine.calculateTotal(
          days: 2,
          roomPrice: 30,
          discount: 50,
          discountType: 'per_night',
        ),
        0,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // isOverdue — هل الحجز متأخر
  // ═══════════════════════════════════════════════════════════════
  group('isOverdue', () {
    test('حجز نشط مع تاريخ خروج قديم = متأخر', () {
      expect(
        HotelTimeEngine.isOverdue(status: 'نشط', checkoutDate: '2020-01-01'),
        isTrue,
      );
    });

    test('حجز نشط مع تاريخ خروج في المستقبل = غير متأخر', () {
      expect(
        HotelTimeEngine.isOverdue(status: 'نشط', checkoutDate: '2099-12-31'),
        isFalse,
      );
    });

    test('حجز غير نشط = غير متأخر حتى لو تاريخه قديم', () {
      expect(
        HotelTimeEngine.isOverdue(
          status: 'checked_out',
          checkoutDate: '2020-01-01',
        ),
        isFalse,
      );
    });

    test('checkoutDate فارغ = غير متأخر', () {
      expect(
        HotelTimeEngine.isOverdue(status: 'نشط', checkoutDate: null),
        isFalse,
      );
      expect(
        HotelTimeEngine.isOverdue(status: 'نشط', checkoutDate: ''),
        isFalse,
      );
    });

    test('checkoutDate بتنسيق ISO يعمل', () {
      expect(
        HotelTimeEngine.isOverdue(
          status: 'نشط',
          checkoutDate: '2020-01-01T12:00:00',
        ),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // needsCheckoutReview
  // ═══════════════════════════════════════════════════════════════
  group('needsCheckoutReview', () {
    test('متأخر = يحتاج مراجعة', () {
      expect(
        HotelTimeEngine.needsCheckoutReview(
          isOverdue: true,
          remainingBalance: 0,
        ),
        isTrue,
      );
    });

    test('رصيد متبقي = يحتاج مراجعة', () {
      expect(
        HotelTimeEngine.needsCheckoutReview(
          isOverdue: false,
          remainingBalance: 50,
        ),
        isTrue,
      );
    });

    test('لا تأخر ولا رصيد = لا يحتاج مراجعة', () {
      expect(
        HotelTimeEngine.needsCheckoutReview(
          isOverdue: false,
          remainingBalance: 0,
        ),
        isFalse,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // bookingComputedFields — الحقول المحسوبة
  // ═══════════════════════════════════════════════════════════════
  group('bookingComputedFields', () {
    test('isBookingComputedField يتعرف على الحقول المحسوبة', () {
      expect(
        HotelTimeEngine.isBookingComputedField('calculatedNights'),
        isTrue,
      );
      expect(HotelTimeEngine.isBookingComputedField('totalDueCached'), isTrue);
      expect(HotelTimeEngine.isBookingComputedField('isOverdue'), isTrue);
      expect(HotelTimeEngine.isBookingComputedField('isFullyPaid'), isTrue);
    });

    test('isBookingComputedField يرفض الحقول العادية', () {
      expect(HotelTimeEngine.isBookingComputedField('guestName'), isFalse);
      expect(HotelTimeEngine.isBookingComputedField('roomNumber'), isFalse);
      expect(HotelTimeEngine.isBookingComputedField('status'), isFalse);
    });

    test('stripComputedFields يزيل الحقول المحسوبة فقط', () {
      final payload = <String, dynamic>{
        'guestName': 'أحمد',
        'roomNumber': '101',
        'calculatedNights': 3,
        'totalDueCached': 300,
        'isOverdue': false,
        'status': 'نشط',
      };
      final result = HotelTimeEngine.stripComputedFields(payload);
      expect(result.containsKey('guestName'), isTrue);
      expect(result.containsKey('roomNumber'), isTrue);
      expect(result.containsKey('status'), isTrue);
      expect(result.containsKey('calculatedNights'), isFalse);
      expect(result.containsKey('totalDueCached'), isFalse);
      expect(result.containsKey('isOverdue'), isFalse);
    });

    test('stripComputedFields لا يعدل القاموس الأصلي', () {
      final payload = <String, dynamic>{
        'guestName': 'أحمد',
        'calculatedNights': 3,
      };
      final result = HotelTimeEngine.stripComputedFields(payload);
      expect(payload.containsKey('calculatedNights'), isTrue);
      expect(result.containsKey('calculatedNights'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // isAfterCutoff
  // ═══════════════════════════════════════════════════════════════
  group('isAfterCutoff', () {
    test('قبل 14:01 = false', () {
      expect(
        HotelTimeEngine.isAfterCutoff(DateTime(2025, 6, 15, 10, 0)),
        isFalse,
      );
    });

    test('14:00 بالضبط = false', () {
      expect(
        HotelTimeEngine.isAfterCutoff(DateTime(2025, 6, 15, 14, 0)),
        isFalse,
      );
    });

    test('14:01 بالضبط = true', () {
      expect(
        HotelTimeEngine.isAfterCutoff(DateTime(2025, 6, 15, 14, 1)),
        isTrue,
      );
    });

    test('بعد 14:01 = true', () {
      expect(
        HotelTimeEngine.isAfterCutoff(DateTime(2025, 6, 15, 20, 0)),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // getHotelDayRange
  // ═══════════════════════════════════════════════════════════════
  group('getHotelDayRange', () {
    test('قبل 14:01: البداية أمس 14:01 والنهاية اليوم 14:00:59', () {
      final range = HotelTimeEngine.getHotelDayRange(
        DateTime(2025, 6, 15, 10, 0),
      );
      expect(range['start'], DateTime(2025, 6, 14, 14, 1));
      expect(range['end'], DateTime(2025, 6, 15, 14, 0, 59, 999));
    });

    test('بعد 14:01: البداية اليوم 14:01 والنهاية غداً 14:00:59', () {
      final range = HotelTimeEngine.getHotelDayRange(
        DateTime(2025, 6, 15, 16, 0),
      );
      expect(range['start'], DateTime(2025, 6, 15, 14, 1));
      expect(range['end'], DateTime(2025, 6, 16, 14, 0, 59, 999));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // calculateDaysWithDiscount
  // ═══════════════════════════════════════════════════════════════
  group('calculateDaysWithDiscount', () {
    test('بدون تاريخ بداية خصم = نفس calculateDays', () {
      final checkIn = DateTime(2025, 6, 10, 15, 0);
      final checkOut = DateTime(2025, 6, 13, 12, 0);
      final result = HotelTimeEngine.calculateDaysWithDiscount(
        checkIn: checkIn,
        checkOut: checkOut,
      );
      expect(
        result,
        HotelTimeEngine.calculateDays(checkIn, checkOut: checkOut),
      );
    });

    test('تاريخ بداية الخصم بعد الدخول = ليالي أقل', () {
      final checkIn = DateTime(2025, 6, 10, 15, 0);
      final checkOut = DateTime(2025, 6, 15, 12, 0);
      final discountStart = DateTime(2025, 6, 13, 14, 1);
      final result = HotelTimeEngine.calculateDaysWithDiscount(
        checkIn: checkIn,
        checkOut: checkOut,
        discountStartDate: discountStart,
      );
      expect(result, 2);
    });

    test('تاريخ بداية الخصم قبل الدخول = نفس calculateDays', () {
      final checkIn = DateTime(2025, 6, 10, 15, 0);
      final checkOut = DateTime(2025, 6, 15, 12, 0);
      final discountStart = DateTime(2025, 6, 5, 14, 1);
      final result = HotelTimeEngine.calculateDaysWithDiscount(
        checkIn: checkIn,
        checkOut: checkOut,
        discountStartDate: discountStart,
      );
      expect(
        result,
        HotelTimeEngine.calculateDays(checkIn, checkOut: checkOut),
      );
    });

    test('تاريخ بداية الخصم بعد الخروج = 0', () {
      final checkIn = DateTime(2025, 6, 10, 15, 0);
      final checkOut = DateTime(2025, 6, 12, 12, 0);
      final discountStart = DateTime(2025, 6, 20, 14, 1);
      final result = HotelTimeEngine.calculateDaysWithDiscount(
        checkIn: checkIn,
        checkOut: checkOut,
        discountStartDate: discountStart,
      );
      expect(result, 0);
    });
  });
}
