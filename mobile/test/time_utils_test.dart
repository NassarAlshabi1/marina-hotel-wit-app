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
    final t = DateTime(2024, 5, 1, 8); // before 09:01 cutoff
    final start = Time.hotelDayStart(t, cutoffHour: 9);
    expect(start, DateTime(2024, 4, 30, 9, 1)); // shifts to previous day

    expect(
      Time.hotelDayStartIso('2024-11-13', cutoffHour: 9),
      '2024-11-13T09:01:00',
    );
    expect(
      Time.hotelDayEndIso('2024-11-13', cutoffHour: 14),
      '2024-11-14T14:01:00',
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

    // Checkin at 10:00 is before the 11:00 grace window
    // → first hotel-day boundary is 2024-02-29 14:01.
    // end = 2024-03-02 15:00
    // duration = 48h 59m = 176340s
    // nights = (176340 ~/ 86400) + 1 = 2 + 1 = 3
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

  test(
    '11:00 early-arrival grace covers a 13:00-to-13:00 stay in one night',
    () {
      final arrivalAt13 = DateTime(2024, 3, 1, 13);
      final checkoutNextDayAt13 = DateTime(2024, 3, 2, 13);

      expect(
        Time.nightsWithCutoff(arrivalAt13, checkout: checkoutNextDayAt13),
        1,
      );
      expect(
        Time.nightsWithCutoff(
          arrivalAt13,
          checkout: checkoutNextDayAt13,
          applyEarlyCheckinGrace: false,
        ),
        2,
        reason: 'non-arrival intervals retain the original hotel-day cutoff',
      );
      expect(
        Time.nightsWithCutoff(
          DateTime(2024, 3, 1, 10, 59, 59),
          checkout: checkoutNextDayAt13,
        ),
        2,
        reason: 'arrivals before 11:00 remain on the previous hotel day',
      );
      expect(
        Time.nightsWithCutoff(
          DateTime(2024, 3, 1, 11),
          checkout: checkoutNextDayAt13,
        ),
        1,
        reason: '11:00 exactly is the start of the arrival grace window',
      );
    },
  );

  // ════════════════════════════════════════════════════════════════════
  // Boundary tests for 14:01 cutoff — exact minute precision
  // ════════════════════════════════════════════════════════════════════

  test('nightsWithCutoff 14:00:59 does NOT add extra night (before cutoff)', () {
    // Checkin at 15:00 on day 1 (after 14:01 cutoff)
    // Checkout at 14:00:59 on day 2 — still within same hotel day
    // Hotel day started at day 1 14:01, ends at day 2 14:00:59
    // Duration = 23h 00m 59s = 82859s
    // nights = (82859 ~/ 86400) + 1 = 0 + 1 = 1
    final checkin = DateTime(2024, 3, 1, 15);
    final checkout = DateTime(2024, 3, 2, 14, 0, 59);
    expect(
      Time.nightsWithCutoff(
        checkin,
        checkout: checkout,
        cutoffHour: 14,
        cutoffMinute: 1,
      ),
      1,
      reason:
          '14:00:59 is still within the hotel day that started at 14:01 previous day',
    );
  });

  test('nightsWithCutoff 14:01:00 ADDS extra night (at cutoff)', () {
    // Checkin at 15:00 on day 1 (after 14:01 cutoff)
    // Checkout at 14:01:00 on day 2 — exactly at hotel day boundary
    // This crosses into the next hotel day
    // Duration = 23h 01m = 82860s
    // nights = (82860 ~/ 86400) + 1 = 0 + 1 = 1... wait, let's verify
    // Actually: startOfCheckinHotelDay = 2024-03-01 14:01
    // end = 2024-03-02 14:01
    // duration = 24h = 86400s
    // nights = (86400 ~/ 86400) + 1 = 1 + 1 = 2
    final checkin = DateTime(2024, 3, 1, 15);
    final checkout = DateTime(2024, 3, 2, 14, 1, 0);
    expect(
      Time.nightsWithCutoff(
        checkin,
        checkout: checkout,
        cutoffHour: 14,
        cutoffMinute: 1,
      ),
      2,
      reason: '14:01:00 exactly crosses into next hotel day, adding a night',
    );
  });

  test('nightsWithCutoff 14:01:01 ADDS extra night (after cutoff)', () {
    // Checkin at 15:00 on day 1
    // Checkout at 14:01:01 on day 2 — 1 second past cutoff
    final checkin = DateTime(2024, 3, 1, 15);
    final checkout = DateTime(2024, 3, 2, 14, 1, 1);
    expect(
      Time.nightsWithCutoff(
        checkin,
        checkout: checkout,
        cutoffHour: 14,
        cutoffMinute: 1,
      ),
      2,
      reason: 'Any time >= 14:01:00 starts a new hotel day',
    );
  });

  test(
    'nightsWithCutoff midnight boundary (00:00) is within same hotel day',
    () {
      // Checkin at 15:00 on day 1
      // Checkout at midnight (00:00) day 2 — well before 14:01
      // Hotel day started at day 1 14:01, ends at day 2 14:00:59
      final checkin = DateTime(2024, 3, 1, 15);
      final checkout = DateTime(2024, 3, 2, 0, 0, 0);
      expect(
        Time.nightsWithCutoff(
          checkin,
          checkout: checkout,
          cutoffHour: 14,
          cutoffMinute: 1,
        ),
        1,
        reason: 'Midnight is within the hotel day (14:01 to next 14:00:59)',
      );
    },
  );

  test('nightsWithCutoff month/year transition at 14:01', () {
    // Checkin Dec 31 15:00
    // Checkout Jan 1 14:01 — exactly at cutoff, new year
    final checkin = DateTime(2023, 12, 31, 15);
    final checkout = DateTime(2024, 1, 1, 14, 1, 0);
    expect(
      Time.nightsWithCutoff(
        checkin,
        checkout: checkout,
        cutoffHour: 14,
        cutoffMinute: 1,
      ),
      2,
      reason: 'Year transition at 14:01 boundary adds night',
    );
  });
}
