import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_wit_app/booking_utils.dart';

void main() {
  group('validateDateRange', () {
    test('returns false when checkIn is null', () {
      expect(validateDateRange(null, DateTime(2026, 6, 10)), false);
    });

    test('returns false when checkOut is null', () {
      expect(validateDateRange(DateTime(2026, 6, 8), null), false);
    });

    test('returns false when check-in date is in the past', () {
      expect(validateDateRange(DateTime(2020, 1, 1), DateTime(2020, 1, 5)), false);
    });

    test('returns false when check-out is before check-in', () {
      expect(validateDateRange(DateTime(2026, 6, 10), DateTime(2026, 6, 8)), false);
    });

    test('returns false when check-out equals check-in', () {
      expect(validateDateRange(DateTime(2026, 6, 10), DateTime(2026, 6, 10)), false);
    });

    test('returns true for valid date range', () {
      expect(validateDateRange(DateTime(2026, 6, 10), DateTime(2026, 6, 15)), true);
    });
  });

  group('calculateBookingPrice', () {
    test('returns -1 for negative nightly rate', () {
      final price = calculateBookingPrice(
        nightlyRate: -100,
        checkIn: DateTime(2026, 6, 10),
        checkOut: DateTime(2026, 6, 15),
      );
      expect(price, -1);
    });

    test('returns -1 for negative service fee', () {
      final price = calculateBookingPrice(
        nightlyRate: 100,
        checkIn: DateTime(2026, 6, 10),
        checkOut: DateTime(2026, 6, 15),
        serviceFee: -10,
      );
      expect(price, -1);
    });

    test('returns -1 when check-out is before check-in', () {
      final price = calculateBookingPrice(
        nightlyRate: 100,
        checkIn: DateTime(2026, 6, 15),
        checkOut: DateTime(2026, 6, 10),
      );
      expect(price, -1);
    });

    test('calculates price correctly without service fee', () {
      final price = calculateBookingPrice(
        nightlyRate: 100,
        checkIn: DateTime(2026, 6, 10),
        checkOut: DateTime(2026, 6, 15),
      );
      expect(price, 500); // 5 nights * $100
    });

    test('calculates price correctly with service fee', () {
      final price = calculateBookingPrice(
        nightlyRate: 100,
        checkIn: DateTime(2026, 6, 10),
        checkOut: DateTime(2026, 6, 15),
        serviceFee: 50,
      );
      expect(price, 550); // 5 nights * $100 + $50
    });

    test('handles single night stay', () {
      final price = calculateBookingPrice(
        nightlyRate: 200,
        checkIn: DateTime(2026, 6, 10),
        checkOut: DateTime(2026, 6, 11),
      );
      expect(price, 200);
    });
  });

  group('isSlipAvailable', () {
    test('returns true when bookedSlips is null', () {
      expect(isSlipAvailable(null, 'slip-1'), true);
    });

    test('returns false when slip is booked', () {
      expect(isSlipAvailable(['slip-1', 'slip-2'], 'slip-1'), false);
    });

    test('returns true when slip is not booked', () {
      expect(isSlipAvailable(['slip-1', 'slip-2'], 'slip-3'), true);
    });

    test('returns true for empty booked array', () {
      expect(isSlipAvailable([], 'slip-1'), true);
    });
  });

  group('formatDate', () {
    test('returns empty string for null date', () {
      expect(formatDate(null), '');
    });

    test('formats date correctly', () {
      expect(formatDate(DateTime(2026, 6, 15)), '2026-06-15');
    });

    test('pads single digit month and day', () {
      expect(formatDate(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('Booking', () {
    test('calculates totalPrice correctly', () {
      final booking = Booking(
        id: '1',
        guestName: 'John Doe',
        checkIn: DateTime(2026, 6, 10),
        checkOut: DateTime(2026, 6, 15),
        nightlyRate: 100,
        roomType: 'Standard',
      );
      expect(booking.totalPrice, 500);
    });

    test('calculates nights correctly', () {
      final booking = Booking(
        id: '1',
        guestName: 'John Doe',
        checkIn: DateTime(2026, 6, 10),
        checkOut: DateTime(2026, 6, 15),
        nightlyRate: 100,
        roomType: 'Standard',
      );
      expect(booking.nights, 5);
    });

    test('isValid returns true for valid booking', () {
      final booking = Booking(
        id: '1',
        guestName: 'John Doe',
        checkIn: DateTime.now().add(const Duration(days: 1)),
        checkOut: DateTime.now().add(const Duration(days: 5)),
        nightlyRate: 100,
        roomType: 'Standard',
      );
      expect(booking.isValid, true);
    });

    test('toString returns formatted string', () {
      final booking = Booking(
        id: '1',
        guestName: 'John Doe',
        checkIn: DateTime(2026, 6, 10),
        checkOut: DateTime(2026, 6, 15),
        nightlyRate: 100,
        roomType: 'Standard',
      );
      expect(booking.toString(), contains('John Doe'));
    });
  });
}