import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/guest_payment_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/stay_balance_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookingsRepository bookings;
  late GuestPaymentCalculationService calculator;

  const checkin = '2024-03-01T15:00:00.000';
  const plannedCheckout = '2024-03-02T14:00:00.000';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PaymentSessionContext.start(userId: 1, userName: 'اختبار');
    bookings = BookingsRepository(db);
    calculator = GuestPaymentCalculationService(db);
    await RoomsRepository(db).create(
      roomNumber: '101',
      type: 'عادية',
      price: 100,
      status: 'شاغرة',
    );
  });

  tearDown(() async {
    PaymentSessionContext.clear();
    await db.close();
  });

  Future<Booking> createBooking({String? actualCheckout}) async {
    final id = await bookings.create(
      roomNumber: '101',
      guestName: 'ضيف الاختبار',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: checkin,
      checkoutDate: plannedCheckout,
      actualCheckout: actualCheckout,
      status: 'نشط',
    );
    return (db.select(
      db.bookings,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  test(
    'active stay continues past planned checkout and crosses 14:01',
    () async {
      final booking = await createBooking();

      final beforeCutoff = await calculator.calculateForBooking(
        booking,
        now: DateTime(2024, 3, 4, 10),
      );
      final afterCutoff = await calculator.calculateForBooking(
        booking,
        now: DateTime(2024, 3, 4, 15),
      );

      expect(beforeCutoff.actualDaysSpent, 3);
      expect(beforeCutoff.costSoFar, 300);
      expect(afterCutoff.actualDaysSpent, 4);
      expect(afterCutoff.costSoFar, 400);
      expect(
        StayBalanceCalculator.calculate(
          booking,
          roomRate: 100,
          priceAdjustments: const [],
          now: DateTime(2024, 3, 4, 10),
        ).actualNightsSpent,
        3,
      );
    },
  );

  test(
    'recorded actual checkout stops accrual even when now is later',
    () async {
      final booking = await createBooking(
        actualCheckout: '2024-03-03T15:00:00.000',
      );

      final result = await calculator.calculateForBooking(
        booking,
        now: DateTime(2024, 3, 10, 15),
      );

      expect(result.actualDaysSpent, 3);
      expect(result.costSoFar, 300);
    },
  );

  test('a future actual checkout is capped at now', () async {
    final booking = await createBooking(
      actualCheckout: '2024-03-10T10:00:00.000',
    );

    final result = await calculator.calculateForBooking(
      booking,
      now: DateTime(2024, 3, 4, 10),
    );

    expect(result.actualDaysSpent, 3);
    expect(result.costSoFar, 300);
    final balance = StayBalanceCalculator.calculate(
      booking,
      roomRate: 100,
      priceAdjustments: const [],
      now: DateTime(2024, 3, 4, 10),
    );
    expect(balance.actualNightsSpent, 3);
    expect(balance.consumedCost, 300);
  });
}
