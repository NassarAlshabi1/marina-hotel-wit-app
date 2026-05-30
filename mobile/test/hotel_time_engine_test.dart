import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';

void main() {
  group('HotelTimeEngine', () {
    group('boundaryHour', () {
      test('should be 14', () {
        expect(HotelTimeEngine.boundaryHour, 14);
      });
    });

    group('getHotelDay', () {
      test('before 14:00 returns previous day', () {
        final dt = DateTime(2025, 1, 15, 13, 59, 59);
        final result = HotelTimeEngine.getHotelDay(dt);
        expect(result.year, 2025);
        expect(result.month, 1);
        expect(result.day, 14);
      });

      test('at 14:00:00 returns previous day (end of hotel day)', () {
        final dt = DateTime(2025, 1, 15, 14, 0, 0);
        final result = HotelTimeEngine.getHotelDay(dt);
        expect(result.year, 2025);
        expect(result.month, 1);
        expect(result.day, 14);
      });

      test('at 14:00:01 returns same day (start of new hotel day)', () {
        final dt = DateTime(2025, 1, 15, 14, 0, 1);
        final result = HotelTimeEngine.getHotelDay(dt);
        expect(result.year, 2025);
        expect(result.month, 1);
        expect(result.day, 15);
      });

      test('after 14:00 returns same day', () {
        final dt = DateTime(2025, 1, 15, 15, 30, 0);
        final result = HotelTimeEngine.getHotelDay(dt);
        expect(result.year, 2025);
        expect(result.month, 1);
        expect(result.day, 15);
      });

      test('at midnight (00:00) returns previous day', () {
        final dt = DateTime(2025, 1, 15, 0, 0, 0);
        final result = HotelTimeEngine.getHotelDay(dt);
        expect(result.year, 2025);
        expect(result.month, 1);
        expect(result.day, 14);
      });
    });

    group('getHotelDayKey', () {
      test('returns formatted date string YYYY-MM-DD', () {
        final dt = DateTime(2025, 1, 15, 14, 0, 1);
        final result = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(result, '2025-01-15');
      });

      test('uses DateTime.now() when no dateTime provided', () {
        final result = HotelTimeEngine.getHotelDayKey();
        expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      });
    });

    group('getHotelDayKeyFromIso', () {
      test('parses ISO format with T', () {
        final result = HotelTimeEngine.getHotelDayKeyFromIso('2025-01-15T14:01');
        expect(result, '2025-01-15');
      });

      test('parses ISO format with space and converts to T', () {
        final result = HotelTimeEngine.getHotelDayKeyFromIso('2025-01-15 14:01');
        expect(result, '2025-01-15');
      });

      test('returns current day for null input', () {
        final result = HotelTimeEngine.getHotelDayKeyFromIso(null);
        expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      });

      test('returns current day for empty string', () {
        final result = HotelTimeEngine.getHotelDayKeyFromIso('');
        expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      });

      test('returns current day for whitespace only', () {
        final result = HotelTimeEngine.getHotelDayKeyFromIso('   ');
        expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      });

      test('returns current day for invalid date string', () {
        final result = HotelTimeEngine.getHotelDayKeyFromIso('invalid-date');
        expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      });
    });

    group('getHotelDayRange', () {
      test('before 14:00 returns yesterday 14:00 to today 13:59', () {
        final dt = DateTime(2025, 1, 15, 10, 0, 0);
        final result = HotelTimeEngine.getHotelDayRange(dt);
        
        expect(result['start'], DateTime(2025, 1, 14, 14, 0, 0));
        expect(result['end'], DateTime(2025, 1, 15, 13, 59, 59, 999));
      });

      test('after 14:00 returns today 14:00 to tomorrow 13:59', () {
        final dt = DateTime(2025, 1, 15, 16, 0, 0);
        final result = HotelTimeEngine.getHotelDayRange(dt);
        
        expect(result['start'], DateTime(2025, 1, 15, 14, 0, 0));
        expect(result['end'], DateTime(2025, 1, 16, 13, 59, 59, 999));
      });
    });

    group('calculateDays', () {
      test('returns 1 for same day check-in and check-out at 14:01', () {
        final checkIn = DateTime(2025, 1, 15, 14, 1);
        final checkOut = DateTime(2025, 1, 15, 14, 1);
        expect(HotelTimeEngine.calculateDays(checkIn, checkOut: checkOut), 1);
      });

      test('returns 2 for next day at 14:01', () {
        final checkIn = DateTime(2025, 1, 15, 14, 1);
        final checkOut = DateTime(2025, 1, 16, 14, 1);
        expect(HotelTimeEngine.calculateDays(checkIn, checkOut: checkOut), 2);
      });

      test('returns 1 for next day at 13:59 (before cutoff)', () {
        final checkIn = DateTime(2025, 1, 15, 14, 1);
        final checkOut = DateTime(2025, 1, 16, 13, 59);
        expect(HotelTimeEngine.calculateDays(checkIn, checkOut: checkOut), 1);
      });
    });

    group('calculateDaysWithDiscount', () {
      test('returns 0 when checkOut is not after effectiveStart', () {
        final checkIn = DateTime(2025, 1, 15, 14, 0);
        final checkOut = DateTime(2025, 1, 16, 13, 0);
        final discountStart = DateTime(2025, 1, 16, 14, 0);
        
        expect(
          HotelTimeEngine.calculateDaysWithDiscount(
            checkIn: checkIn,
            checkOut: checkOut,
            discountStartDate: discountStart,
          ),
          0,
        );
      });

      test('uses discountStartDate when after checkIn', () {
        final checkIn = DateTime(2025, 1, 15, 12, 0);
        final checkOut = DateTime(2025, 1, 20, 12, 0);
        final discountStart = DateTime(2025, 1, 17, 14, 0);
        
        // Effective start becomes 2025-01-17 14:00
        final result = HotelTimeEngine.calculateDaysWithDiscount(
          checkIn: checkIn,
          checkOut: checkOut,
          discountStartDate: discountStart,
        );
        // From 2025-01-17 14:00 to 2025-01-20 12:00 = ~3 days
        expect(result, greaterThan(0));
      });
    });

    group('isNowAfterCutoff', () {
      test('returns boolean value', () {
        final result = HotelTimeEngine.isNowAfterCutoff();
        expect(result, isA<bool>());
      });
    });

    group('isAfterCutoff', () {
      test('returns true for 14:00:01', () {
        final dt = DateTime(2025, 1, 15, 14, 0, 1);
        expect(HotelTimeEngine.isAfterCutoff(dt), true);
      });

      test('returns false for 14:00:00', () {
        final dt = DateTime(2025, 1, 15, 14, 0, 0);
        expect(HotelTimeEngine.isAfterCutoff(dt), false);
      });

      test('returns false for 13:59:59', () {
        final dt = DateTime(2025, 1, 15, 13, 59, 59);
        expect(HotelTimeEngine.isAfterCutoff(dt), false);
      });

      test('returns true for 15:00:00', () {
        final dt = DateTime(2025, 1, 15, 15, 0, 0);
        expect(HotelTimeEngine.isAfterCutoff(dt), true);
      });
    });

    group('calculateTotal', () {
      test('returns 0 for 0 days', () {
        expect(
          HotelTimeEngine.calculateTotal(days: 0, roomPrice: 100),
          0,
        );
      });

      test('returns 0 for 0 room price', () {
        expect(
          HotelTimeEngine.calculateTotal(days: 5, roomPrice: 0),
          0,
        );
      });

      test('returns 0 for negative values', () {
        expect(
          HotelTimeEngine.calculateTotal(days: -1, roomPrice: 100),
          0,
        );
        expect(
          HotelTimeEngine.calculateTotal(days: 5, roomPrice: -100),
          0,
        );
      });

      test('calculates correctly without discount', () {
        expect(
          HotelTimeEngine.calculateTotal(days: 5, roomPrice: 100),
          500,
        );
      });

      test('applies total discount correctly', () {
        expect(
          HotelTimeEngine.calculateTotal(
            days: 5,
            roomPrice: 100,
            discount: 50,
            discountType: 'total',
          ),
          450,
        );
      });

      test('applies per_night discount correctly', () {
        expect(
          HotelTimeEngine.calculateTotal(
            days: 5,
            roomPrice: 100,
            discount: 10,
            discountType: 'per_night',
          ),
          450, // 500 - (10 * 5)
        );
      });

      test('returns 0 when discount exceeds total', () {
        expect(
          HotelTimeEngine.calculateTotal(
            days: 5,
            roomPrice: 100,
            discount: 600,
            discountType: 'total',
          ),
          0,
        );
      });
    });

    group('isOverdue', () {
      test('returns false for non-active status', () {
        expect(
          HotelTimeEngine.isOverdue(
            status: 'checkout',
            checkoutDate: '2025-01-01T10:00',
          ),
          false,
        );
      });

      test('returns false for null checkoutDate', () {
        expect(
          HotelTimeEngine.isOverdue(
            status: 'نشط',
            checkoutDate: null,
          ),
          false,
        );
      });

      test('returns false for empty checkoutDate', () {
        expect(
          HotelTimeEngine.isOverdue(
            status: 'نشط',
            checkoutDate: '',
          ),
          false,
        );
      });

      test('returns false for future checkout date', () {
        final futureDate = DateTime.now().add(const Duration(days: 1));
        final isoString = futureDate.toIso8601String();
        expect(
          HotelTimeEngine.isOverdue(
            status: 'نشط',
            checkoutDate: isoString,
          ),
          false,
        );
      });

      test('returns true for past checkout date', () {
        final pastDate = DateTime.now().subtract(const Duration(days: 1));
        final isoString = pastDate.toIso8601String();
        expect(
          HotelTimeEngine.isOverdue(
            status: 'نشط',
            checkoutDate: isoString,
          ),
          true,
        );
      });

      test('handles date with space instead of T', () {
        final pastDate = DateTime.now().subtract(const Duration(days: 1));
        final dateString = '${pastDate.toIso8601String().split('T')[0]} 10:00';
        expect(
          HotelTimeEngine.isOverdue(
            status: 'نشط',
            checkoutDate: dateString,
          ),
          true,
        );
      });
    });

    group('needsCheckoutReview', () {
      test('returns false when not overdue and no remaining balance', () {
        expect(
          HotelTimeEngine.needsCheckoutReview(
            isOverdue: false,
            remainingBalance: 0,
          ),
          false,
        );
      });

      test('returns true when overdue', () {
        expect(
          HotelTimeEngine.needsCheckoutReview(
            isOverdue: true,
            remainingBalance: 0,
          ),
          true,
        );
      });

      test('returns true when has remaining balance', () {
        expect(
          HotelTimeEngine.needsCheckoutReview(
            isOverdue: false,
            remainingBalance: 100,
          ),
          true,
        );
      });

      test('returns true when both conditions met', () {
        expect(
          HotelTimeEngine.needsCheckoutReview(
            isOverdue: true,
            remainingBalance: 100,
          ),
          true,
        );
      });
    });

    group('calculateNights (compatibility)', () {
      test('delegates to calculateDays', () {
        final checkIn = DateTime(2025, 1, 15, 14, 1);
        final checkOut = DateTime(2025, 1, 17, 14, 1);
        expect(
          HotelTimeEngine.calculateNights(checkIn: checkIn, checkOut: checkOut),
          HotelTimeEngine.calculateDays(checkIn, checkOut: checkOut),
        );
      });
    });

    group('timeUntilNextHotelDay', () {
      test('returns positive duration', () {
        final result = HotelTimeEngine.timeUntilNextHotelDay();
        expect(result.inSeconds, greaterThan(0));
        expect(result.inSeconds, lessThanOrEqualTo(14 * 60 * 60)); // max 14 hours
      });
    });

    group('bookingComputedFields', () {
      test('contains expected fields', () {
        final fields = HotelTimeEngine.bookingComputedFields;
        expect(fields, contains('calculatedNights'));
        expect(fields, contains('totalNightsCached'));
        expect(fields, contains('totalDueCached'));
        expect(fields, contains('totalPaidCached'));
        expect(fields, contains('remainingBalanceCached'));
        expect(fields, contains('isFullyPaid'));
        expect(fields, contains('hotelDayCheckin'));
        expect(fields, contains('hotelDayCheckout'));
      });
    });

    group('isBookingComputedField', () {
      test('returns true for computed fields', () {
        expect(HotelTimeEngine.isBookingComputedField('calculatedNights'), true);
        expect(HotelTimeEngine.isBookingComputedField('totalDueCached'), true);
      });

      test('returns false for non-computed fields', () {
        expect(HotelTimeEngine.isBookingComputedField('guestName'), false);
        expect(HotelTimeEngine.isBookingComputedField('roomNumber'), false);
        expect(HotelTimeEngine.isBookingComputedField('status'), false);
      });
    });

    group('stripComputedFields', () {
      test('removes computed fields from payload', () {
        final payload = {
          'guestName': 'Ahmed',
          'roomNumber': '101',
          'calculatedNights': 5,
          'totalDueCached': 500,
          'status': 'نشط',
        };
        
        final result = HotelTimeEngine.stripComputedFields(payload);
        
        expect(result.containsKey('guestName'), true);
        expect(result.containsKey('roomNumber'), true);
        expect(result.containsKey('status'), true);
        expect(result.containsKey('calculatedNights'), false);
        expect(result.containsKey('totalDueCached'), false);
      });

      test('does not modify original payload', () {
        final payload = {
          'guestName': 'Ahmed',
          'calculatedNights': 5,
        };
        
        HotelTimeEngine.stripComputedFields(payload);
        
        expect(payload.containsKey('calculatedNights'), true);
      });

      test('returns empty map for payload with only computed fields', () {
        final payload = {
          'calculatedNights': 5,
          'totalDueCached': 500,
        };
        
        final result = HotelTimeEngine.stripComputedFields(payload);
        
        expect(result.isEmpty, true);
      });
    });
  });
}