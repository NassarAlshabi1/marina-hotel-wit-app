import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/booking_computed_stream_service.dart';
import 'package:marina_hotel_mobile/services/enhanced_booking_calculation_service.dart';
import 'package:marina_hotel_mobile/services/guest_payment_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/sync_integrity_checker.dart';
import 'package:marina_hotel_mobile/utils/booking_night_coverage.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookingsRepository bookings;
  late DateTime now;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime.now();
    PaymentSessionContext.start(userId: 1, userName: 'اختبار');
    bookings = BookingsRepository(db);
    final rooms = RoomsRepository(db);
    await rooms.create(
      roomNumber: '101',
      type: 'عادية',
      price: 100,
      status: 'شاغرة',
    );
    await rooms.create(
      roomNumber: '102',
      type: 'عادية',
      price: 100,
      status: 'شاغرة',
    );
  });

  tearDown(() async {
    PaymentSessionContext.clear();
    await db.close();
  });

  Future<Booking> createBooking({
    required String roomNumber,
    required String status,
    String? actualCheckout,
  }) async {
    final checkin = now.subtract(const Duration(days: 3));
    final id = await bookings.create(
      roomNumber: roomNumber,
      guestName: 'ضيف $roomNumber',
      guestPhone: '0500000${roomNumber.substring(1)}',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      checkoutDate: checkin.add(const Duration(days: 1)).toIso8601String(),
      actualCheckout: actualCheckout,
      status: status,
    );
    return (db.select(
      db.bookings,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<void> addPayment({
    required int bookingLocalId,
    required double amount,
    String? bookingUuidCache,
  }) async {
    final stamp = now.millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion(
            localUuid: d.Value(IdGen.uuid()),
            createdAt: d.Value(stamp),
            updatedAt: d.Value(stamp),
            lastModified: d.Value(stamp),
            bookingLocalId: d.Value(bookingLocalId),
            bookingUuidCache: d.Value(bookingUuidCache),
            amount: d.Value(amount),
            paymentDate: d.Value(now.toIso8601String()),
            paymentMethod: const d.Value('نقداً'),
            revenueType: const d.Value('room'),
          ),
        );
  }

  test(
    'status and planned checkout never stop accrual without actualCheckout',
    () async {
      final booking = await createBooking(
        roomNumber: '101',
        status: 'مكتمل',
      );
      final fixedNow = now.add(const Duration(hours: 2));
      final service = BookingComputedStreamService(db, clock: () => fixedNow);

      final computed = await service.buildBookingWithPayments(booking.id);
      expect(computed, isNotNull);
      expect(computed!.computedCheckOut, fixedNow);
      expect(
        computed.days,
        Time.nightsWithCutoff(
          DateTime.parse(booking.checkinDate),
          checkout: fixedNow,
        ),
      );

      final breakdown = await EnhancedBookingCalculationService(
        db,
      ).calculateNightlyBreakdown(booking, now: fixedNow);
      expect(breakdown.length, computed.days);
    },
  );

  test('a recorded actualCheckout alone stops accrual', () async {
    final checkout = now.subtract(const Duration(days: 1));
    final booking = await createBooking(
      roomNumber: '101',
      status: 'نشط',
      actualCheckout: checkout.toIso8601String(),
    );
    final service = BookingComputedStreamService(db, clock: () => now);

    final computed = await service.buildBookingWithPayments(booking.id);
    expect(computed, isNotNull);
    expect(computed!.computedCheckOut, checkout);
    expect(
      computed.days,
      Time.nightsWithCutoff(
        DateTime.parse(booking.checkinDate),
        checkout: checkout,
      ),
    );
  });

  test(
    'UUID ownership overrides a colliding local booking ID everywhere',
    () async {
      final bookingA = await createBooking(
        roomNumber: '101',
        status: 'checked_in',
      );
      final bookingB = await createBooking(
        roomNumber: '102',
        status: 'checked_in',
      );
      await addPayment(
        bookingLocalId: bookingA.id,
        bookingUuidCache: bookingB.localUuid.replaceAll('-', ''),
        amount: 100,
      );
      // A local legacy row with no trusted UUID may retain its verified local FK.
      await addPayment(bookingLocalId: bookingA.id, amount: 30);

      final computed = BookingComputedStreamService(db, clock: () => now);
      expect(
        (await computed.buildBookingWithPayments(bookingA.id))!.totalPaid,
        30,
      );
      expect(
        (await computed.buildBookingWithPayments(bookingB.id))!.totalPaid,
        100,
      );

      final activeRows = await computed.watchActiveBookingsWithPayments().first;
      final byId = {for (final row in activeRows) row.booking.id: row};
      expect(byId[bookingA.id]!.totalPaid, 30);
      expect(byId[bookingB.id]!.totalPaid, 100);

      final guestPayments = GuestPaymentCalculationService(db);
      expect(
        (await guestPayments.calculateForBooking(bookingA, now: now)).totalPaid,
        30,
      );
      expect(
        (await guestPayments.calculateForBooking(bookingB, now: now)).totalPaid,
        100,
      );

      final detailed = EnhancedBookingCalculationService(db);
      expect(
        (await detailed.calculateForBooking(
          bookingA,
          now: now,
        )).financialSummary.totalPaid,
        30,
      );
      expect(
        (await detailed.calculateForBooking(
          bookingB,
          now: now,
        )).financialSummary.totalPaid,
        100,
      );

      final paymentsRepository = PaymentsRepository(db);
      expect(
        (await paymentsRepository.paymentsByBooking(bookingA.id).first)
            .map((payment) => payment.amount)
            .toList(),
        [30],
      );
      expect(
        (await paymentsRepository.paymentsByBooking(bookingB.id).first)
            .map((payment) => payment.amount)
            .toList(),
        [100],
      );
      expect(
        await paymentsRepository
            .watchTotalPaidForBooking(
              bookingA.id,
              bookingUuid: bookingA.localUuid,
            )
            .first,
        30,
      );
      expect(
        await paymentsRepository
            .watchTotalPaidForBooking(
              bookingB.id,
              bookingUuid: bookingB.localUuid,
            )
            .first,
        100,
      );

      final integrity = await SyncIntegrityChecker.instance.verify(db);
      expect(
        integrity.issues.any(
          (issue) =>
              issue.type == IssueType.missingReference &&
              issue.table == 'payments' &&
              issue.description.contains('conflicts with its UUID owner'),
        ),
        isTrue,
      );
      expect(
        integrity.issues.where(
          (issue) =>
              issue.type == IssueType.orphanedRecord &&
              issue.table == 'payments',
        ),
        isEmpty,
      );
    },
  );

  test('night UUIDs and parent UUID remain stable across rebuilds', () async {
    final booking = await createBooking(
      roomNumber: '101',
      status: 'مكتمل',
    );
    final calculations = EnhancedBookingCalculationService(db);

    Future<List<BookingNight>> rebuild() async {
      await calculations.updateNightlyRecords(
        booking,
        now: now,
        enqueueOutbox: false,
      );
      return (db.select(db.bookingNights)
            ..where((night) => night.bookingLocalId.equals(booking.id))
            ..where((night) => night.deletedAt.isNull())
            ..orderBy([(night) => d.OrderingTerm.asc(night.hotelDayKey)]))
          .get();
    }

    final first = await rebuild();
    final second = await rebuild();
    expect(first, isNotEmpty);
    expect(
      BookingNightCoverage.completeForStay(
        nights: second,
        bookingLocalId: booking.id,
        bookingUuid: booking.localUuid,
        checkin: DateTime.parse(booking.checkinDate),
        expectedNights: second.length,
      ),
      isNotNull,
    );
    expect(
      BookingNightCoverage.completeForStay(
        nights: second.skip(1).toList(),
        bookingLocalId: booking.id,
        bookingUuid: booking.localUuid,
        checkin: DateTime.parse(booking.checkinDate),
        expectedNights: second.length,
      ),
      isNull,
    );
    expect(
      second.map((night) => (night.hotelDayKey, night.localUuid)).toList(),
      first.map((night) => (night.hotelDayKey, night.localUuid)).toList(),
    );
    expect(
      second.map((night) => night.hotelDayKey).toSet().length,
      second.length,
    );
    expect(
      second.every((night) => night.bookingUuidCache == booking.localUuid),
      isTrue,
    );
    for (final night in second) {
      expect(
        night.localUuid,
        IdGen.bookingNightUuid(
          bookingUuid: booking.localUuid,
          hotelDayKey: night.hotelDayKey,
        ),
      );
    }
    expect(
      IdGen.bookingNightUuid(
        bookingUuid: booking.localUuid,
        hotelDayKey: second.first.hotelDayKey,
      ),
      IdGen.bookingNightUuid(
        bookingUuid: booking.localUuid.replaceAll('-', ''),
        hotelDayKey: second.first.hotelDayKey,
      ),
    );
  });
}
