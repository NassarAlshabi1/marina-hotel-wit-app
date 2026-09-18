import 'package:flutter_test/flutter_test.dart';
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

    test('a pre-cutoff booking starts with the previous hotel day', () {
      expect(
        Time.hotelDayStartForNewBooking(DateTime(2026, 8, 13, 14, 0)),
        DateTime(2026, 8, 12, 14, 1),
      );
    });
  });
}
