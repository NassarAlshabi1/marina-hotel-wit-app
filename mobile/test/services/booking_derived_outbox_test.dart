import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/booking_derived_fields_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
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
      promoteProvisional: false,
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
