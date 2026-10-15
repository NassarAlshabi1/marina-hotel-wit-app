import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/booking_derived_fields_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int bookingId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = Time.nowEpoch();
    final checkin = DateTime.now().subtract(const Duration(days: 1));
    final checkout = DateTime.now().add(const Duration(days: 2));

    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion(
            localUuid: const d.Value('room-appwrite-001'),
            roomNumber: const d.Value('101'),
            type: const d.Value('standard'),
            price: const d.Value(15000),
            status: const d.Value('occupied'),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: const d.Value(1),
            origin: const d.Value('server'),
          ),
        );

    bookingId = await db
        .into(db.bookings)
        .insert(
          BookingsCompanion(
            localUuid: const d.Value('booking-appwrite-001'),
            roomNumber: const d.Value('101'),
            guestName: const d.Value('ضيف اختبار'),
            guestPhone: const d.Value('0500000000'),
            guestNationality: const d.Value('يمني'),
            checkinDate: d.Value(checkin.toIso8601String()),
            checkoutDate: d.Value(checkout.toIso8601String()),
            status: const d.Value('checked_in'),
            discount: const d.Value(0),
            discountType: const d.Value('nightly'),
            expectedNights: const d.Value(1),
            calculatedNights: const d.Value(1),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: const d.Value(1),
            origin: const d.Value('server'),
          ),
        );
  });

  tearDown(() async {
    PaymentSessionContext.clear();
    await db.close();
  });

  Future<int> outboxCount() async {
    final result = await db
        .customSelect(
          'SELECT COUNT(*) AS count FROM outbox',
          readsFrom: {db.outbox},
        )
        .getSingle();
    return result.read<int>('count');
  }

  test('إعادة حساب الحقول المشتقة للحجز المسحوب لا تضيف Outbox', () async {
    final service = BookingDerivedFieldsService(db);

    await service.refreshForBookingId(
      bookingId,
      now: DateTime.now(),
      forceRebuild: true,
      enqueueOutbox: false,
    );

    expect(await outboxCount(), 0);
    final nights = await (db.select(
      db.bookingNights,
    )..where((night) => night.bookingLocalId.equals(bookingId))).get();
    expect(nights, isNotEmpty);
  });

  test('تحديث جميع الحجوزات للعرض لا يضيف Outbox', () async {
    final service = BookingDerivedFieldsService(db);

    await service.refreshAllActiveBookings(
      now: DateTime.now(),
      enqueueOutbox: false,
    );

    expect(await outboxCount(), 0);
  });

  test('التحديث للعرض لا يرقّي الحجز المؤقت ولا ينشئ Outbox', () async {
    await (db.update(db.bookings)..where((b) => b.id.equals(bookingId))).write(
      const BookingsCompanion(status: d.Value('مؤقت')),
    );

    final service = BookingDerivedFieldsService(db);
    await service.refreshAllActiveBookings(
      now: DateTime.now().add(const Duration(days: 1)),
      enqueueOutbox: false,
    );

    final booking = await (db.select(
      db.bookings,
    )..where((b) => b.id.equals(bookingId))).getSingle();
    expect(booking.status, 'مؤقت');
    expect(await outboxCount(), 0);
  });

  test('إعادة الحساب المحلي تبقى قابلة للرفع عبر Outbox', () async {
    final service = BookingDerivedFieldsService(db);

    await service.refreshForBookingId(
      bookingId,
      now: DateTime.now(),
      forceRebuild: true,
    );

    expect(await outboxCount(), 1);
  });

  test('دفعة لاحقة لا تعيد تسعير ليالي حجز مكتمل بسعر الغرفة الحالي', () async {
    final now = DateTime.now();
    final checkout = now.subtract(const Duration(days: 1));
    final nightStart = now.subtract(const Duration(days: 2));
    final nightEnd = nightStart.add(const Duration(days: 1));
    final timestamp = Time.nowEpoch();
    final hotelDayKey =
        '${nightStart.year.toString().padLeft(4, '0')}-'
        '${nightStart.month.toString().padLeft(2, '0')}-'
        '${nightStart.day.toString().padLeft(2, '0')}';

    await (db.update(db.rooms)..where((room) => room.roomNumber.equals('101')))
        .write(const RoomsCompanion(price: d.Value(90000)));
    await (db.update(db.bookings)..where((b) => b.id.equals(bookingId))).write(
      BookingsCompanion(
        checkinDate: d.Value(nightStart.toIso8601String()),
        checkoutDate: d.Value(checkout.toIso8601String()),
        actualCheckout: d.Value(checkout.toIso8601String()),
        status: const d.Value('مكتمل'),
        expectedNights: const d.Value(1),
        calculatedNights: const d.Value(1),
        totalNightsCached: const d.Value(1),
        totalDueCached: const d.Value(100),
        totalPaidCached: const d.Value(0),
        remainingBalanceCached: const d.Value(100),
      ),
    );
    await db
        .into(db.bookingNights)
        .insert(
          BookingNightsCompanion(
            localUuid: const d.Value('historical-night-uuid'),
            createdAt: d.Value(timestamp),
            updatedAt: d.Value(timestamp),
            lastModified: d.Value(timestamp),
            bookingLocalId: d.Value(bookingId),
            bookingUuidCache: const d.Value('booking-appwrite-001'),
            hotelDayKey: d.Value(hotelDayKey),
            nightStart: d.Value(nightStart.toIso8601String()),
            nightEnd: d.Value(nightEnd.toIso8601String()),
            nightlyRate: const d.Value(100),
            baseRate: const d.Value(100),
            finalRate: const d.Value(100),
          ),
        );

    PaymentSessionContext.start(userId: 1, userName: 'اختبار');
    await PaymentsRepository(db).create(
      amount: 50,
      paymentDate: now.toIso8601String(),
      paymentMethod: 'cash',
      revenueType: 'room',
      bookingLocalId: bookingId,
      roomNumber: '101',
    );

    final nights = await (db.select(
      db.bookingNights,
    )..where((night) => night.bookingLocalId.equals(bookingId))).get();
    final refreshedBooking = await (db.select(
      db.bookings,
    )..where((booking) => booking.id.equals(bookingId))).getSingle();

    expect(nights, hasLength(1));
    expect(nights.single.localUuid, 'historical-night-uuid');
    expect(nights.single.nightlyRate, 100);
    expect(nights.single.finalRate, 100);
    expect(refreshedBooking.totalDueCached, 100);
    expect(refreshedBooking.totalPaidCached, 50);
    expect(refreshedBooking.remainingBalanceCached, 50);
  });

  Future<String> markCompletedWithHistoricalNight({
    required double totalDueCached,
    bool insertNight = true,
  }) async {
    final now = DateTime.now();
    final checkout = now.subtract(const Duration(days: 1));
    final nightStart = now.subtract(const Duration(days: 2));
    final nightEnd = nightStart.add(const Duration(days: 1));
    final timestamp = Time.nowEpoch();
    final hotelDayKey =
        '${nightStart.year.toString().padLeft(4, '0')}-'
        '${nightStart.month.toString().padLeft(2, '0')}-'
        '${nightStart.day.toString().padLeft(2, '0')}';

    await (db.update(db.rooms)..where((room) => room.roomNumber.equals('101')))
        .write(const RoomsCompanion(price: d.Value(90000)));
    await (db.update(db.bookings)..where((b) => b.id.equals(bookingId))).write(
      BookingsCompanion(
        checkinDate: d.Value(nightStart.toIso8601String()),
        checkoutDate: d.Value(checkout.toIso8601String()),
        actualCheckout: d.Value(checkout.toIso8601String()),
        status: const d.Value('مكتمل'),
        totalDueCached: d.Value(totalDueCached),
        totalPaidCached: const d.Value(0),
        remainingBalanceCached: d.Value(totalDueCached),
      ),
    );
    if (insertNight) {
      await db
          .into(db.bookingNights)
          .insert(
            BookingNightsCompanion(
              localUuid: const d.Value('historical-night-uuid'),
              createdAt: d.Value(timestamp),
              updatedAt: d.Value(timestamp),
              lastModified: d.Value(timestamp),
              bookingLocalId: d.Value(bookingId),
              bookingUuidCache: const d.Value('booking-appwrite-001'),
              hotelDayKey: d.Value(hotelDayKey),
              nightStart: d.Value(nightStart.toIso8601String()),
              nightEnd: d.Value(nightEnd.toIso8601String()),
              nightlyRate: const d.Value(100),
              baseRate: const d.Value(100),
              finalRate: const d.Value(100),
            ),
          );
    }
    return hotelDayKey;
  }

  Future<Booking> reloadBooking() => (db.select(
    db.bookings,
  )..where((b) => b.id.equals(bookingId))).getSingle();

  test(
    'حجز مكتمل مسحوب بلا totalDueCached يُحسب مستحقه من لياليه المحفوظة',
    () async {
      await markCompletedWithHistoricalNight(totalDueCached: 0);

      PaymentSessionContext.start(userId: 1, userName: 'اختبار');
      await PaymentsRepository(db).create(
        amount: 50,
        paymentDate: DateTime.now().toIso8601String(),
        paymentMethod: 'cash',
        revenueType: 'room',
        bookingLocalId: bookingId,
        roomNumber: '101',
      );

      final booking = await reloadBooking();
      final nights = await (db.select(
        db.bookingNights,
      )..where((n) => n.bookingLocalId.equals(bookingId))).get();

      expect(booking.totalDueCached, 100);
      expect(booking.totalPaidCached, 50);
      expect(booking.remainingBalanceCached, 50);
      expect(booking.isFullyPaid, isFalse);
      expect(nights.single.localUuid, 'historical-night-uuid');
      expect(nights.single.finalRate, 100);
    },
  );

  test(
    'تخفيض يُضاف بعد المغادرة يُطبَّق على السعر التاريخي لا سعر الغرفة الحالي',
    () async {
      final hotelDayKey = await markCompletedWithHistoricalNight(
        totalDueCached: 100,
      );
      final timestamp = Time.nowEpoch();
      await db
          .into(db.bookingPriceAdjustments)
          .insert(
            BookingPriceAdjustmentsCompanion(
              localUuid: const d.Value('adj-after-checkout'),
              createdAt: d.Value(timestamp),
              updatedAt: d.Value(timestamp),
              lastModified: d.Value(timestamp),
              bookingLocalUuid: const d.Value('booking-appwrite-001'),
              bookingLocalId: d.Value(bookingId),
              roomNumber: const d.Value('101'),
              amount: const d.Value(20),
              effectiveHotelDay: d.Value(hotelDayKey),
              adjustmentType: const d.Value(0),
              adjustmentMode: const d.Value('nightly'),
              reason: const d.Value('خصم بعد المغادرة'),
            ),
          );

      await BookingDerivedFieldsService(db).refreshForBookingId(bookingId);

      final booking = await reloadBooking();
      final night = await (db.select(
        db.bookingNights,
      )..where((n) => n.bookingLocalId.equals(bookingId))).getSingle();

      expect(night.localUuid, 'historical-night-uuid');
      expect(night.baseRate, 100);
      expect(night.adjustment, -20);
      expect(night.finalRate, 80);
      expect(booking.totalDueCached, 80);
      expect(booking.remainingBalanceCached, 80);
    },
  );

  test('حجز مكتمل بلا ليالٍ ولا مستحق محفوظ لا يُعلَّم مدفوعاً', () async {
    await markCompletedWithHistoricalNight(
      totalDueCached: 0,
      insertNight: false,
    );

    await BookingDerivedFieldsService(
      db,
    ).refreshForBookingId(bookingId, enqueueOutbox: false);

    final booking = await reloadBooking();
    final nights = await (db.select(
      db.bookingNights,
    )..where((n) => n.bookingLocalId.equals(bookingId))).get();

    expect(booking.totalDueCached, greaterThan(0));
    expect(booking.isFullyPaid, isFalse);
    expect(nights, isEmpty);
  });

  test('تنظيف تخفيض موروث مسحوب لا يضيف Outbox', () async {
    final now = Time.nowEpoch();
    await db
        .into(db.bookingPriceAdjustments)
        .insert(
          BookingPriceAdjustmentsCompanion(
            localUuid: const d.Value('legacy-adjustment-appwrite-001'),
            bookingLocalUuid: const d.Value('booking-appwrite-001'),
            bookingLocalId: d.Value(bookingId),
            roomNumber: const d.Value('101'),
            amount: const d.Value(1000),
            effectiveHotelDay: d.Value(Time.hotelDayKey()),
            isActive: const d.Value(true),
            reason: const d.Value('legacy_discount'),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: const d.Value(1),
            origin: const d.Value('server'),
          ),
        );

    await BookingsRepository(
      db,
    ).syncLegacyDiscountToAdjustments(bookingId, enqueueOutbox: false);

    final adjustment =
        await (db.select(db.bookingPriceAdjustments)..where(
              (item) => item.localUuid.equals('legacy-adjustment-appwrite-001'),
            ))
            .getSingle();
    expect(adjustment.isActive, isFalse);
    expect(await outboxCount(), 0);
  });
}
