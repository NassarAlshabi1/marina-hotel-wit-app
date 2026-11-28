import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/stay_balance_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomNumber = 'EXT-1401';
  const nightlyRate = 18000.0;
  final checkin = DateTime(2026, 10, 4, 1, 53);
  final plannedCheckout = DateTime(2026, 10, 7, 1, 54);
  final now = DateTime(2026, 10, 5, 1);

  late AppDatabase db;
  late BookingsRepository bookingsRepo;
  late PaymentsRepository paymentsRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookingsRepo = BookingsRepository(db);
    paymentsRepo = PaymentsRepository(db);
    PaymentSessionContext.start(userId: 1, userName: 'اختبار');

    await RoomsRepository(db).create(
      roomNumber: roomNumber,
      type: 'اختبار',
      price: nightlyRate,
      status: 'شاغرة',
    );
  });

  tearDown(() async {
    PaymentSessionContext.clear();
    await db.close();
  });

  Future<Booking> seedBooking({
    required double amount,
    DateTime? checkout,
  }) async {
    final bookingId = await bookingsRepo.create(
      roomNumber: roomNumber,
      guestName: 'اختبار حدّ اليوم الفندقي',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      checkoutDate: (checkout ?? plannedCheckout).toIso8601String(),
      status: 'نشط',
      expectedNights: 4,
    );

    await paymentsRepo.create(
      bookingLocalId: bookingId,
      roomNumber: roomNumber,
      amount: amount,
      paymentDate: checkin.toIso8601String(),
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );

    return (db.select(
      db.bookings,
    )..where((b) => b.id.equals(bookingId))).getSingle();
  }

  group('StayBalanceCalculator — extra paid nights use one hotel-day basis', () {
    test(
      '36 paid nights against 4 planned nights means 32 extra; coverage ends at 14:01',
      () async {
        final booking = await seedBooking(amount: 653000);

        final result = StayBalanceCalculator.calculate(
          booking,
          roomRate: nightlyRate,
          now: now,
        );

        expect(result.totalPaidNights, 36);
        expect(result.manualCheckoutDate, plannedCheckout);
        expect(result.autoCheckoutDate.year, 2026);
        expect(result.autoCheckoutDate.month, 11);
        expect(result.autoCheckoutDate.day, 8);
        expect(result.autoCheckoutDate.hour, 14);
        expect(result.autoCheckoutDate.minute, 1);
        expect(result.extraNightsBeyondManual, 32);
        expect(result.isAutoExtended, isTrue);
      },
    );

    test(
      'coverage of exactly the planned 4 nights is not reported as an extension',
      () async {
        final booking = await seedBooking(amount: 4 * nightlyRate);

        final result = StayBalanceCalculator.calculate(
          booking,
          roomRate: nightlyRate,
          now: now,
        );

        expect(result.totalPaidNights, 4);
        expect(result.autoCheckoutDate.day, 7);
        expect(result.autoCheckoutDate.hour, 14);
        expect(result.autoCheckoutDate.minute, 1);
        expect(result.extraNightsBeyondManual, 0);
        expect(result.isAutoExtended, isFalse);
      },
    );

    test(
      'planned checkout at 14:01 consumes the next hotel night boundary',
      () async {
        final booking = await seedBooking(
          amount: 5 * nightlyRate,
          checkout: DateTime(2026, 10, 7, 14, 0, 59),
        );

        final beforeBoundary = StayBalanceCalculator.calculate(
          booking,
          roomRate: nightlyRate,
          now: now,
        );
        expect(beforeBoundary.extraNightsBeyondManual, 1);

        await bookingsRepo.update(
          booking.id,
          checkoutDate: DateTime(2026, 10, 7, 14, 1).toIso8601String(),
        );
        final updatedBooking = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(booking.id))).getSingle();
        final atBoundary = StayBalanceCalculator.calculate(
          updatedBooking,
          roomRate: nightlyRate,
          now: now,
        );

        expect(atBoundary.extraNightsBeyondManual, 0);
        expect(atBoundary.isAutoExtended, isFalse);
      },
    );
  });
}
