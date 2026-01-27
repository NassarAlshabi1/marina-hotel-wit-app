import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  test('hotelDayKey respects cutoff and backshifts same day before cutoff', () {
    final t = DateTime(
      2024,
      1,
      10,
      10,
    ); // before 14:00 -> shifts to previous day
    expect(Time.hotelDayKey(now: t, cutoffHour: 14), '2024-01-09');

    final late = DateTime(2024, 1, 10, 16);
    expect(Time.hotelDayKey(now: late, cutoffHour: 14), '2024-01-10');
  });

  test(
    'hotelDayKeyFromIso trims/normalizes and falls back on parse errors',
    () {
      expect(
        Time.hotelDayKeyFromIso('2024-01-15 10:00:00', cutoffHour: 12),
        '2024-01-14',
      );
      expect(
        Time.hotelDayKeyFromIso('2024-01-15T03:00:00', cutoffHour: 12),
        '2024-01-14',
      );
      final fallback = Time.hotelDayKeyFromIso('not-a-date', cutoffHour: 10);
      expect(fallback.length, 10);
    },
  );

  test('hotelDayStart and end iso helpers', () {
    final t = DateTime(2024, 5, 1, 8);
    final start = Time.hotelDayStart(t, cutoffHour: 9);
    expect(start, DateTime(2024, 4, 30, 9));
    expect(
      Time.hotelDayStartIso('2024-04-30', cutoffHour: 9),
      '2024-04-30T09:00:00',
    );
    expect(
      Time.hotelDayEndIso('2024-04-30', cutoffHour: 9),
      '2024-05-01T09:00:00',
    );
  });

  test('safeIsoToDateString returns yyyy-mm-dd or fallback', () {
    expect(Time.safeIsoToDateString('2024-02-03T10:20:30Z'), '2024-02-03');
    expect(Time.safeIsoToDateString('2024-02-03'), '2024-02-03');
    expect(Time.safeIsoToDateString(''), hasLength(10));
    expect(Time.safeIsoToDateString(null), hasLength(10));
  });

  test('nightsWithCutoff counts segments across cutoff boundaries', () {
    final checkin = DateTime(2024, 1, 1, 13, 0); // before cutoff
    final checkout = DateTime(2024, 1, 2, 15, 0); // after next-day cutoff
    expect(
      Time.nightsWithCutoff(checkin, checkout: checkout, cutoffHour: 14),
      3,
    );

    // checkout before checkin -> minimum 1 night
    final one = Time.nightsWithCutoff(
      checkin,
      checkout: DateTime(2024, 1, 1, 12, 0),
      cutoffHour: 14,
    );
    expect(one, 1);
  });
}
