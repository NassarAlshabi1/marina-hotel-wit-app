import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/booking_derived_fields_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
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

  tearDown(() => db.close());

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

  test('إعادة الحساب المحلي تبقى قابلة للرفع عبر Outbox', () async {
    final service = BookingDerivedFieldsService(db);

    await service.refreshForBookingId(
      bookingId,
      now: DateTime.now(),
      forceRebuild: true,
    );

    expect(await outboxCount(), 1);
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
