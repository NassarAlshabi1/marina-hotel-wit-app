import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/hotel_time_engine.dart'
    as services_engine;
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  group('Hotel-day consistency', () {
    test('Time and HotelTimeEngine agree at the 14:01 boundary', () {
      final beforeBoundary = DateTime(2026, 8, 13, 14, 0, 59);
      final atBoundary = DateTime(2026, 8, 13, 14, 1);

      expect(Time.hotelDayKey(now: beforeBoundary), '2026-08-12');
      expect(
        HotelTimeEngine.getHotelDayKey(dateTime: beforeBoundary),
        '2026-08-12',
      );
      expect(Time.hotelDayKey(now: atBoundary), '2026-08-13');
      expect(
        HotelTimeEngine.getHotelDayKey(dateTime: atBoundary),
        '2026-08-13',
      );
    });

    test('a checkout at 14:00:59 does not add a night but 14:01 does', () {
      final checkin = DateTime(2026, 8, 12, 14, 1);

      expect(
        Time.nightsWithCutoff(
          checkin,
          checkout: DateTime(2026, 8, 13, 14, 0, 59),
        ),
        1,
      );
      expect(
        Time.nightsWithCutoff(checkin, checkout: DateTime(2026, 8, 13, 14, 1)),
        2,
      );
    });

    test('services import uses the canonical 14:01 night calculation', () {
      final checkin = DateTime(2026, 8, 12, 14, 1);

      expect(
        services_engine.HotelTimeEngine.calculateDays(
          checkin,
          checkOut: DateTime(2026, 8, 13, 14, 0, 59),
        ),
        1,
      );
      expect(
        services_engine.HotelTimeEngine.calculateDays(
          checkin,
          checkOut: DateTime(2026, 8, 13, 14, 1),
        ),
        2,
      );
    });

    test('new booking check-in at 13:00 receives the early-arrival grace', () {
      final start = Time.hotelDayStartForNewBooking(DateTime(2026, 8, 13, 13));

      expect(start.year, 2026);
      expect(start.month, 8);
      expect(start.day, 13);
      expect(start.hour, 14);
      expect(start.minute, 1);
    });

    test('new booking before 11:00 still starts on the previous hotel day', () {
      final start = Time.hotelDayStartForNewBooking(
        DateTime(2026, 8, 13, 10, 59, 59),
      );

      expect(start.year, 2026);
      expect(start.month, 8);
      expect(start.day, 12);
      expect(start.hour, 14);
      expect(start.minute, 1);
    });
  });
}
