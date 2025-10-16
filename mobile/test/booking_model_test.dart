import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/models/booking.dart';

void main() {
  group('Booking night-count logic', () {
    final DateTime checkIn = DateTime(2025, 1, 10, 10, 0);

    test('nightsForDisplay respects 13:00 cutoff for in-house guests', () {
      final booking = Booking(
        id: 'CUT-001',
        guestName: 'ضيف',
        roomNumber: '101',
        checkIn: checkIn,
        nightlyRate: 200,
      );

      // Same day before cutoff: minimum one night
      final sameDay = DateTime(2025, 1, 10, 12, 30);
      expect(booking.nightsForDisplay(now: sameDay), 1);

      // Next day before cutoff: still counts 1 night (datediff = 1, no cutoff increment)
      final nextDayBeforeCutoff = DateTime(2025, 1, 11, 12, 59);
      expect(booking.nightsForDisplay(now: nextDayBeforeCutoff), 1);

      // After cutoff the next day: adds the cutoff night
      final afterCutoff = DateTime(2025, 1, 11, 13, 15);
      expect(booking.nightsForDisplay(now: afterCutoff), 2);
    });

    test('nightsForBilling uses actual checkout when present', () {
      final booking = Booking(
        id: 'ACT-001',
        guestName: 'ضيف',
        roomNumber: '101',
        checkIn: checkIn,
        actualCheckout: DateTime(2025, 1, 12, 8, 0),
        nightlyRate: 150,
      );

      expect(booking.nightsForBilling(), 2);
      expect(booking.totalDue(), 300);
    });

    test('nightsForBilling falls back to planned checkout if actual is missing', () {
      final booking = Booking(
        id: 'PLAN-001',
        guestName: 'ضيف',
        roomNumber: '101',
        checkIn: checkIn,
        plannedCheckout: DateTime(2025, 1, 13, 9, 0),
        nightlyRate: 180,
      );

      expect(booking.nightsForBilling(), 3);
      expect(booking.totalDue(), 540);
    });
  });

  test('Remaining amount never goes negative even if payments exceed total', () {
    final booking = Booking(
      id: 'PAY-001',
      guestName: 'ضيف',
      roomNumber: '101',
      checkIn: DateTime(2025, 1, 10, 10, 0),
      plannedCheckout: DateTime(2025, 1, 11, 10, 0),
      nightlyRate: 250,
      payments: const [
        BookingPaymentEntry(amount: 400, paymentDate: DateTime(2025, 1, 10, 18)),
      ],
    );

    expect(booking.totalDue(), 250);
    expect(booking.paidTotal, 400);
    expect(booking.remaining(), 0);
  });
}
