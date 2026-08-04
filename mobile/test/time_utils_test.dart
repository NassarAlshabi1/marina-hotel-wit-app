import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  test('hotelDayKey respects cutoff and backshifts same day before cutoff', () {
    // DateTime(2024, 1, 10, 10) with cutoff 14 → 10:00 is before 14:00
    // → subtract 14h → 2024-01-09 20:00 → dateToString → '2024-01-09'
    final t = DateTime(2024, 1, 10, 10);
    expect(Time.hotelDayKey(now: t, cutoffHour: 14), '2024-01-09');

    // DateTime(2024, 1, 10, 16) with cutoff 14 → 16:00 is after 14:00
    // → subtract 14h → 2024-01-10 02:00 → dateToString → '2024-01-10'
    final late = DateTime(2024, 1, 10, 16);
    expect(Time.hotelDayKey(now: late, cutoffHour: 14), '2024-01-10');
  });

  test('hotelDayKeyFromIso trims/normalizes and falls back on parse errors', () {
    // '2024-01-15 10:00:00' → parsed as 2024-01-15T10:00:00 → before 12:00 cutoff
    // → subtract 12h → 2024-01-14 22:00 → '2024-01-14'
    expect(
      Time.hotelDayKeyFromIso('2024-01-15 10:00:00', cutoffHour: 12),
      '2024-01-14',
    );

    // '2024-01-15T15:00:00' → after 12:00 cutoff → subtract 12h → 2024-01-15 03:00 → '2024-01-15'
    expect(
      Time.hotelDayKeyFromIso('2024-01-15T15:00:00', cutoffHour: 12),
      '2024-01-15',
    );

    // Invalid string → falls back to hotelDayKey() (uses DateTime.now())
    final fallback = Time.hotelDayKeyFromIso('not-a-date', cutoffHour: 10);
    expect(fallback.length, 10); // yyyy-mm-dd format
  });

  test('hotelDayStart and end iso helpers', () {
    final t = DateTime(2024, 5, 1, 8); // before 9:00 cutoff
    final start = Time.hotelDayStart(t, cutoffHour: 9);
    expect(start, DateTime(2024, 4, 30, 9)); // shifts to previous day

    expect(
      Time.hotelDayStartIso('2024-11-13', cutoffHour: 9),
      '2024-11-13T09:00:00',
    );
    expect(
      Time.hotelDayEndIso('2024-11-13', cutoffHour: 14),
      '2024-11-14T14:00:00',
    );
  });

  test('safeIsoToDateString returns yyyy-mm-dd or fallback', () {
    expect(Time.safeIsoToDateString('2024-03-15T10:30:00'), '2024-03-15');
    expect(Time.safeIsoToDateString('2024-03-15'), '2024-03-15');
    expect(Time.safeIsoToDateString('invalid'), isNotNull);
    expect(Time.safeIsoToDateString('invalid').length, greaterThanOrEqualTo(8));
  });

  test('nightsWithCutoff uses date difference + cutoff rule', () {
    // Checkin at 15:00 (after 14:00 cutoff), checkout next day at 10:00
    // startOfCheckinHotelDay = 2024-03-01 14:00 (checkin is after, no shift)
    // end = 2024-03-02 10:00
    // duration = 20h = 72000s
    // nights = (72000 ~/ 86400) + 1 = 0 + 1 = 1
    final checkin = DateTime(2024, 3, 1, 15);
    final checkout = DateTime(2024, 3, 2, 10);
    expect(
      Time.nightsWithCutoff(checkin, checkout: checkout, cutoffHour: 14),
      1,
    );

    // Checkin at 10:00 (before 14:00 cutoff) → hotel day shifts to previous day
    // startOfCheckinHotelDay = 2024-02-29 14:00 (shifted back 1 day)
    // end = 2024-03-02 15:00
    // duration = 49h = 176400s
    // nights = (176400 ~/ 86400) + 1 = 2 + 1 = 3
    final earlyCheckin = DateTime(2024, 3, 1, 10);
    final lateCheckout = DateTime(2024, 3, 2, 15);
    expect(
      Time.nightsWithCutoff(
        earlyCheckin,
        checkout: lateCheckout,
        cutoffHour: 14,
      ),
      3,
    );
  });
}
