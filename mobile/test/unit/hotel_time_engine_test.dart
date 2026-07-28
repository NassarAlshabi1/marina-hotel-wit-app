import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';

void main() {
  group('HotelTimeEngine', () {
    group('getHotelDayKey', () {
      test('should return previous day before 14:01', () {
        // 10:00 AM on July 19 → hotel day = July 18
        final dt = DateTime(2026, 7, 19, 10, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, '2026-07-18');
      });

      test('should return current day at exactly 14:01', () {
        // 14:01 on July 19 → hotel day = July 19
        final dt = DateTime(2026, 7, 19, 14, 1);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, '2026-07-19');
      });

      test('should return previous day at 14:00', () {
        // 14:00 on July 19 → hotel day = July 18 (still in previous hotel day)
        final dt = DateTime(2026, 7, 19, 14, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, '2026-07-18');
      });

      test('should return current day after 14:01', () {
        // 15:00 on July 19 → hotel day = July 19
        final dt = DateTime(2026, 7, 19, 15, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, '2026-07-19');
      });

      test('should handle midnight correctly', () {
        // 00:00 on July 19 → hotel day = July 18
        final dt = DateTime(2026, 7, 19, 0, 0);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, '2026-07-18');
      });

      test('should handle 23:59 correctly', () {
        // 23:59 on July 19 → hotel day = July 19
        final dt = DateTime(2026, 7, 19, 23, 59);
        final key = HotelTimeEngine.getHotelDayKey(dateTime: dt);
        expect(key, '2026-07-19');
      });
    });

    group('calculateDays', () {
      test('same day should be 1 night minimum', () {
        final checkin = DateTime(2026, 7, 19, 14, 1);
        final checkout = DateTime(2026, 7, 19, 18, 0);
        final days = HotelTimeEngine.calculateDays(checkin, checkOut: checkout);
        expect(days, 1);
      });

      test('2 days checkout before 14:01 = 1 night', () {
        final checkin = DateTime(2026, 7, 19, 14, 1);
        final checkout = DateTime(2026, 7, 20, 14, 0);
        final days = HotelTimeEngine.calculateDays(checkin, checkOut: checkout);
        expect(days, 1);
      });

      test('2 days checkout at 14:01 = 2 nights', () {
        final checkin = DateTime(2026, 7, 19, 14, 1);
        final checkout = DateTime(2026, 7, 20, 14, 1);
        final days = HotelTimeEngine.calculateDays(checkin, checkOut: checkout);
        expect(days, 2);
      });

      test('3 days checkout at 14:00 = 2 nights', () {
        final checkin = DateTime(2026, 7, 19, 14, 1);
        final checkout = DateTime(2026, 7, 21, 14, 0);
        final days = HotelTimeEngine.calculateDays(checkin, checkOut: checkout);
        expect(days, 2);
      });

      test('3 days checkout at 14:01 = 3 nights', () {
        final checkin = DateTime(2026, 7, 19, 14, 1);
        final checkout = DateTime(2026, 7, 21, 14, 1);
        final days = HotelTimeEngine.calculateDays(checkin, checkOut: checkout);
        expect(days, 3);
      });
    });
  });
}
