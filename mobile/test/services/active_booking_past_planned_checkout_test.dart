import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/enhanced_booking_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookingsRepository bookings;
  late EnhancedBookingCalculationService calculator;

  final checkin = DateTime(2024, 3, 1, 15);
  final plannedCheckout = DateTime(2024, 3, 2, 14);
  final beforeCutoff = DateTime(2024, 3, 4, 10);
  final afterCutoff = DateTime(2024, 3, 4, 15);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PaymentSessionContext.start(userId: 1, userName: 'اختبار');
    final rooms = RoomsRepository(db);
    bookings = BookingsRepository(db);
    calculator = EnhancedBookingCalculationService(db);
    await rooms.create(
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

  Future<Booking> seedActiveBooking() async {
    final id = await bookings.create(
      roomNumber: '101',
      guestName: 'ضيف الاختبار',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      checkoutDate: plannedCheckout.toIso8601String(),
      status: 'نشط',
      expectedNights: 1,
    );
    return (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();
  }

  test('active booking keeps accruing nights after plannedCheckout', () async {
    final booking = await seedActiveBooking();

    final result = await calculator.calculateForBooking(
      booking,
      now: beforeCutoff,
    );

    expect(result.bookingActive, isTrue);
    expect(result.checkout, beforeCutoff);
    expect(result.financialSummary.totalNights, 3);
  });

  test(
    'active booking adds a night after the 14:01 hotel-day cutoff',
    () async {
      final booking = await seedActiveBooking();

      final result = await calculator.calculateForBooking(
        booking,
        now: afterCutoff,
      );

      expect(result.bookingActive, isTrue);
      expect(result.checkout, afterCutoff);
      expect(result.financialSummary.totalNights, 4);
    },
  );
}
