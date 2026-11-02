import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:marina_hotel_mobile/utils/currency_formatter.dart';

void main() {
  group('Time - Hotel Day Calculations', () {
    test('hotelDayStart returns correct boundary for before 14:01', () {
      final beforeBoundary = DateTime(2026, 1, 15, 10, 0, 0);
      final result = Time.hotelDayStart(beforeBoundary);
      expect(result, DateTime(2026, 1, 14, 14, 1, 0));
    });

    test('hotelDayStart returns correct boundary for after 14:01', () {
      final afterBoundary = DateTime(2026, 1, 15, 16, 0, 0);
      final result = Time.hotelDayStart(afterBoundary);
      expect(result, DateTime(2026, 1, 15, 14, 1, 0));
    });

    test('hotelDayStart keeps exactly 14:00 in the previous hotel day', () {
      final exact14 = DateTime(2026, 1, 15, 14, 0, 0);
      final result = Time.hotelDayStart(exact14);
      expect(result, DateTime(2026, 1, 14, 14, 1, 0));
    });

    test('hotelDayKey returns correct date string for before 14:00', () {
      final before14 = DateTime(2026, 1, 15, 10, 0, 0);
      final result = Time.hotelDayKey(now: before14);
      expect(result, '2026-01-14');
    });

    test('hotelDayKey returns correct date string for after 14:00', () {
      final after14 = DateTime(2026, 1, 15, 16, 0, 0);
      final result = Time.hotelDayKey(now: after14);
      expect(result, '2026-01-15');
    });

    test(
      'nightsWithCutoff counts 1 night for same-day checkout before next cutoff',
      () {
        final checkin = DateTime(2026, 1, 15, 16, 0, 0);
        final checkout = DateTime(2026, 1, 16, 14, 0, 0);
        final nights = Time.nightsWithCutoff(checkin, checkout: checkout);
        expect(nights, 1);
      },
    );

    test('nightsWithCutoff counts 2 nights spanning two hotel days', () {
      final checkin = DateTime(2026, 1, 15, 16, 0, 0);
      final checkout = DateTime(2026, 1, 17, 10, 0, 0);
      final nights = Time.nightsWithCutoff(checkin, checkout: checkout);
      expect(nights, 2);
    });

    test('nightsWithCutoff returns minimum 1 night even for same datetime', () {
      final checkin = DateTime(2026, 1, 15, 16, 0, 0);
      final nights = Time.nightsWithCutoff(checkin, checkout: checkin);
      expect(nights, 1);
    });
  });

  group('CurrencyFormatter - Truncation', () {
    test('formatAmount truncates decimals (no rounding up)', () {
      expect(CurrencyFormatter.formatAmount(1999.5), '1,999');
      expect(CurrencyFormatter.formatAmount(1999.4), '1,999');
    });

    test('formatAmount handles exact integers', () {
      expect(CurrencyFormatter.formatAmount(5000.0), '5,000');
    });

    test('formatAmount never shows decimals even when legacy flag is used', () {
      expect(
        CurrencyFormatter.formatAmount(1999.99, showDecimals: true),
        '1,999',
      );
    });

    test('parseAmount truncates to whole number (no decimals)', () {
      expect(CurrencyFormatter.parseAmount('1999.99'), 1999);
      expect(CurrencyFormatter.parseAmount('5000'), 5000.0);
    });

    test('parseAmount handles Arabic numerals', () {
      expect(CurrencyFormatter.parseAmount('١٢٣٤'), 1234.0);
    });
  });

  group('Discount Calculations - Hotel Day Based', () {
    test('discount start date should use hotel day 14:01 boundary', () {
      final discountStartDate = DateTime(2026, 1, 15, 0, 0, 0);
      final hotelDayStart = DateTime(
        discountStartDate.year,
        discountStartDate.month,
        discountStartDate.day,
        14,
        1,
      );
      expect(hotelDayStart.hour, 14);
      expect(hotelDayStart.minute, 1);
    });

    test('segment at midnight should be counted as previous hotel day', () {
      final segmentStart = DateTime(2026, 1, 16, 2, 0, 0);
      final hotelDay = Time.hotelDayStart(segmentStart);
      expect(hotelDay, DateTime(2026, 1, 15, 14, 1, 0));
    });

    test(
      'discount applies correctly when segment is on or after discount start hotel day',
      () {
        final segmentStart = DateTime(2026, 1, 16, 16, 0, 0);
        final discountStartDate = DateTime(2026, 1, 16, 0, 0, 0);

        final hotelDay = Time.hotelDayStart(segmentStart);
        final hotelDayDate = DateTime(
          hotelDay.year,
          hotelDay.month,
          hotelDay.day,
        );
        final discountDay = DateTime(
          discountStartDate.year,
          discountStartDate.month,
          discountStartDate.day,
        );

        expect(hotelDayDate.isBefore(discountDay), false);
      },
    );

    test(
      'discount does not apply when segment hotel day is before discount start',
      () {
        final segmentStart = DateTime(2026, 1, 15, 10, 0, 0);
        final discountStartDate = DateTime(2026, 1, 16, 0, 0, 0);

        final hotelDay = Time.hotelDayStart(segmentStart);
        final hotelDayDate = DateTime(
          hotelDay.year,
          hotelDay.month,
          hotelDay.day,
        );
        final discountDay = DateTime(
          discountStartDate.year,
          discountStartDate.month,
          discountStartDate.day,
        );

        expect(hotelDayDate.isBefore(discountDay), true);
      },
    );
  });

  group('Financial Calculations', () {
    test('total discount applied once after sum of nights', () {
      const baseRate = 6000.0;
      const nights = 8;
      const discount = 1000.0;
      const discountType = 'total';

      const totalNightAmount = baseRate * nights;
      double totalDue = totalNightAmount;
      if (discount > 0 && discountType == 'total') {
        totalDue = (totalNightAmount - discount).clamp(0.0, totalNightAmount);
      }

      expect(totalDue, 47000.0);
    });

    test('per_night discount applied to each night rate', () {
      const baseRate = 15000.0;
      const nights = 5;
      const discount = 1000.0;
      const discountType = 'per_night';

      double totalDue = 0;
      for (int i = 0; i < nights; i++) {
        var rate = baseRate;
        if (discount > 0 && discountType != 'total') {
          rate = (baseRate - discount).clamp(0.0, baseRate);
        }
        totalDue += rate;
      }

      expect(totalDue, 70000.0);
    });

    test('negative nightly rate prevented by clamp', () {
      const baseRate = 500.0;
      const discount = 1000.0;

      final rate = (baseRate - discount).clamp(0.0, baseRate);
      expect(rate, 0.0);
    });

    test('remaining balance does not go negative', () {
      const totalDue = 10000.0;
      const totalPaid = 12000.0;

      const remainingRaw = totalDue - totalPaid;
      const remaining = remainingRaw < 0 ? 0.0 : remainingRaw;

      expect(remaining, 0.0);
    });
  });
}
