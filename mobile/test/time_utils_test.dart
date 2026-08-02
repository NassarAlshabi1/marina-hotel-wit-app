import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  test('hotelDayKey respects cutoff and backshifts same day before cutoff', () {
    final t = DateTime(
      2024,
      1,
      10,
      10,
    ); // before 14:01 -> shifts to previous day
    expect(Time.hotelDayKey(now: t, cutoffHour: 14, cutoffMinute: 1), '2024-01-09');

    final late = DateTime(2024, 1, 10, 16);
    expect(Time.hotelDayKey(now: late, cutoffHour: 14, cutoffMinute: 1), '2024-01-10');
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
    expect(start, DateTime(2024, 4, 30, 9, 1));
    expect(
      Time.hotelDayStartIso('2024-04-30', cutoffHour: 9),
      '2024-04-30T09:01:00',
    );
    expect(
      Time.hotelDayEndIso('2024-04-30', cutoffHour: 9),
      '2024-05-01T09:01:00',
    );
  });

  test('safeIsoToDateString returns yyyy-mm-dd or fallback', () {
    expect(Time.safeIsoToDateString('2024-02-03T10:20:30Z'), '2024-02-03');
    expect(Time.safeIsoToDateString('2024-02-03'), '2024-02-03');
    expect(Time.safeIsoToDateString(''), hasLength(10));
    expect(Time.safeIsoToDateString(null), hasLength(10));
  });

  test('nightsWithCutoff uses date difference + cutoff rule', () {
    // checkin 1 يناير 13:00, checkout 2 يناير 15:00
    // checkin Jan 1 13:00 (before 14:01) → hotel day starts Dec 31 14:01
    // checkout Jan 2 15:00 (after 14:01) → 3 nights (Dec 31, Jan 1, Jan 2)
    final checkin = DateTime(2024, 1, 1, 13, 0);
    final checkout = DateTime(2024, 1, 2, 15, 0);
    expect(
      Time.nightsWithCutoff(checkin, checkout: checkout, cutoffHour: 14, cutoffMinute: 1),
      3,
    );

    // نفس اليوم → يوم واحد على الأقل، المغادرة 12:00 < 14:01 → لا إضافة
    final sameDay = Time.nightsWithCutoff(
      checkin,
      checkout: DateTime(2024, 1, 1, 12, 0),
      cutoffHour: 14, cutoffMinute: 1,
    );
    expect(sameDay, 1);

    // checkin 10 يناير 20:00, checkout 12 يناير 13:00
    // فرق التواريخ = 2، المغادرة 13:00 < 14:01 → 2
    final multi = Time.nightsWithCutoff(
      DateTime(2024, 1, 10, 20, 0),
      checkout: DateTime(2024, 1, 12, 13, 0),
      cutoffHour: 14, cutoffMinute: 1,
    );
    expect(multi, 2);

    // checkin 10 يناير 20:00, checkout 12 يناير 14:01
    // فرق التواريخ = 2، المغادرة 14:01 > 14:01 → +1 = 3
    final afterCutoff = Time.nightsWithCutoff(
      DateTime(2024, 1, 10, 20, 0),
      checkout: DateTime(2024, 1, 12, 14, 1),
      cutoffHour: 14, cutoffMinute: 1,
    );
    expect(afterCutoff, 3);

    // المغادرة بالضبط عند 14:00:00 → لا يوم إضافي
    final exactCutoff = Time.nightsWithCutoff(
      DateTime(2024, 1, 10, 20, 0),
      checkout: DateTime(2024, 1, 12, 14, 0, 0),
      cutoffHour: 14, cutoffMinute: 1,
    );
    expect(exactCutoff, 2);
  });
}
