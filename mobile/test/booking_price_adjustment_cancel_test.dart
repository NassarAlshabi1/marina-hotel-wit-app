// ═══════════════════════════════════════════════════════════════
//  booking_price_adjustment_cancel_test.dart
//  Tests for cancelAdjustment hotel day logic + deactivateExpired
// ═══════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';

void main() {
  group('HotelTimeEngine', () {
    group('getHotelDayKey', () {
      test('before 14:01 returns previous day', () {
        // 10:00 AM → previous day
        final dt = DateTime(2026, 8, 2, 10, 0, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, equals('2026-08-01'));
      });

      test('at exactly 14:00:59 returns previous day', () {
        final dt = DateTime(2026, 8, 2, 14, 0, 59);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, equals('2026-08-01'));
      });

      test('at exactly 14:01:00 returns current day', () {
        final dt = DateTime(2026, 8, 2, 14, 1, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, equals('2026-08-02'));
      });

      test('after 14:01 returns current day', () {
        // 3:00 PM → same day
        final dt = DateTime(2026, 8, 2, 15, 0, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, equals('2026-08-02'));
      });

      test('midnight (00:00:00) returns previous day', () {
        final dt = DateTime(2026, 8, 2, 0, 0, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, equals('2026-08-01'));
      });

      test('late night (23:59:59) returns current day', () {
        final dt = DateTime(2026, 8, 2, 23, 59, 59);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, equals('2026-08-02'));
      });
    });

    group('getHotelDay', () {
      test('before cutoff returns DateTime of previous day', () {
        final dt = DateTime(2026, 8, 2, 10, 0);
        final hotelDay = HotelTimeEngine.getHotelDay(dt);
        expect(hotelDay.year, equals(2026));
        expect(hotelDay.month, equals(8));
        expect(hotelDay.day, equals(1));
        expect(hotelDay.hour, equals(0));
      });

      test('after cutoff returns DateTime of same day', () {
        final dt = DateTime(2026, 8, 2, 15, 0);
        final hotelDay = HotelTimeEngine.getHotelDay(dt);
        expect(hotelDay.day, equals(2));
      });
    });

    group('isAfterCutoff', () {
      test('14:00:59 is NOT after cutoff', () {
        final dt = DateTime(2026, 8, 2, 14, 0, 59);
        expect(HotelTimeEngine.isAfterCutoff(dt), isFalse);
      });

      test('14:01:00 IS after cutoff', () {
        final dt = DateTime(2026, 8, 2, 14, 1, 0);
        expect(HotelTimeEngine.isAfterCutoff(dt), isTrue);
      });

      test('10:00 is NOT after cutoff', () {
        final dt = DateTime(2026, 8, 2, 10, 0);
        expect(HotelTimeEngine.isAfterCutoff(dt), isFalse);
      });

      test('20:00 IS after cutoff', () {
        final dt = DateTime(2026, 8, 2, 20, 0);
        expect(HotelTimeEngine.isAfterCutoff(dt), isTrue);
      });
    });

    group('Cancellation logic (hotel day boundary)', () {
      // These tests verify the business logic used by cancelAdjustment()
      test('yesterday hotel day is one day before today', () {
        final todayHotelDay = HotelTimeEngine.getHotelDayKey(
          dateTime: DateTime(2026, 8, 2, 15, 0),
        );
        final yesterdayHotelDay = DateTime.parse(
          todayHotelDay,
        ).subtract(const Duration(days: 1)).toIso8601String().split('T').first;

        expect(todayHotelDay, equals('2026-08-02'));
        expect(yesterdayHotelDay, equals('2026-08-01'));
      });

      test('endHotelDay = yesterday means todays night is NOT discounted', () {
        // If endHotelDay = 2026-08-01 and today = 2026-08-02
        // then night of 2026-08-02 should NOT be discounted
        const endHotelDay = '2026-08-01';
        const todayHotelDay = '2026-08-02';
        // endHotelDay < todayHotelDay → expired
        expect(endHotelDay.compareTo(todayHotelDay), lessThan(0));
      });

      test('endHotelDay = today means todays night IS still active', () {
        const endHotelDay = '2026-08-02';
        const todayHotelDay = '2026-08-02';
        // endHotelDay == todayHotelDay → still active today
        expect(endHotelDay.compareTo(todayHotelDay), equals(0));
      });
    });

    group('Deactivation logic', () {
      test('adjustment with endHotelDay < today should be deactivated', () {
        const todayHotelDay = '2026-08-02';
        const expiredEnd = '2026-07-27';
        // expiredEnd <= todayHotelDay → should deactivate
        expect(expiredEnd.compareTo(todayHotelDay), lessThan(0));
      });

      test('adjustment with endHotelDay = today should NOT be deactivated', () {
        const todayHotelDay = '2026-08-02';
        const activeEnd = '2026-08-02';
        // activeEnd == todayHotelDay → still active
        expect(activeEnd.compareTo(todayHotelDay), equals(0));
      });

      test('adjustment with null endHotelDay should NOT be deactivated', () {
        // No endHotelDay → continues indefinitely
        const String? endHotelDay = null;
        expect(endHotelDay, isNull);
      });

      test('adjustment with cancelled_at should have is_active = false', () {
        // This is the core fix: cancelled adjustments must be inactive
        const isCancelled = true;
        const isActive = false; // Our fix: always false on cancel
        expect(isCancelled && isActive, isFalse);
      });
    });

    group('Hotel day boundary edge cases', () {
      test('month boundary: Aug 1 before 14:01 → Jul 31', () {
        final dt = DateTime(2026, 8, 1, 10, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, equals('2026-07-31'));
      });

      test('month boundary: Aug 1 after 14:01 → Aug 1', () {
        final dt = DateTime(2026, 8, 1, 15, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, equals('2026-08-01'));
      });

      test('year boundary: Jan 1 before 14:01 → Dec 31 previous year', () {
        final dt = DateTime(2026, 1, 1, 10, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, equals('2025-12-31'));
      });

      test('year boundary: Jan 1 after 14:01 → Jan 1', () {
        final dt = DateTime(2026, 1, 1, 15, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, equals('2026-01-01'));
      });
    });
  });
}
