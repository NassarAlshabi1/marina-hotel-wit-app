@Tags(['slow'])
library marina_hotel_mobile.test.booking_price_adjustment_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/booking_price_adjustment_service.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:marina_hotel_mobile/utils/id.dart';

AppDatabase _createTestDb() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

void main() {
  late AppDatabase db;
  late BookingPriceAdjustmentService adjustmentService;

  setUp(() async {
    db = _createTestDb();
    adjustmentService = BookingPriceAdjustmentService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('السيناريو 1: تخفيض مؤقت بأثر رجعي', () {
    test(
      'نزيل دخل 12-01 بسعر 15000 ر.ي، خصم 1000 من 13-01 إلى 16-01 يطبق في 17-01',
      () async {
        final roomUuid = IdGen.uuid();
        final bookingUuid = IdGen.uuid();
        final now = Time.nowEpoch();

        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion(
                localUuid: Value(roomUuid),
                roomNumber: const Value('101'),
                type: const Value('standard'),
                price: const Value(15000),
                status: const Value('occupied'),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );

        await db
            .into(db.bookings)
            .insert(
              BookingsCompanion(
                localUuid: Value(bookingUuid),
                roomNumber: const Value('101'),
                guestName: const Value('أحمد محمد'),
                guestPhone: const Value('0500000000'),
                guestNationality: const Value('يمني'),
                checkinDate: const Value('2026-08-04T10:00:00'),
                status: const Value('checked_in'),
                discount: const Value(0),
                discountType: const Value('nightly'),
                calculatedNights: const Value(7),
                expectedNights: const Value(7),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );

        final booking = await (db.select(
          db.bookings,
        )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

        final hotelDays = [
          '2026-08-03',
          '2026-08-04',
          '2026-08-05',
          '2026-08-03',
          '2026-08-04',
          '2026-08-05',
          '2026-08-03',
        ];
        for (var i = 0; i < hotelDays.length; i++) {
          await db
              .into(db.bookingNights)
              .insert(
                BookingNightsCompanion(
                  localUuid: Value(IdGen.uuid()),
                  bookingLocalId: Value(booking.id),
                  hotelDayKey: Value(hotelDays[i]),
                  nightStart: const Value('2026-07-24T14:00:00'),
                  nightEnd: const Value('2026-07-25T12:00:00'),
                  nightlyRate: const Value(15000),
                  baseRate: const Value(15000),
                  adjustment: const Value(0),
                  finalRate: const Value(15000),
                  sequence: Value(i + 1),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                  lastModified: Value(now),
                ),
              );
        }

        final preview = await adjustmentService.previewAdjustment(
          bookingId: booking.id,
          amount: 1000,
          type: AdjustmentType.discount,
          effectiveHotelDay: '2026-08-05',
          endHotelDay: '2026-08-05',
        );

        expect(preview.originalTotal, equals(7 * 15000));
        expect(preview.nightsAffected, equals(4));
        expect(preview.difference, equals(-4000));
        expect(preview.adjustedTotal, equals(7 * 15000 - 4000));

        await adjustmentService.applyTemporaryAdjustment(
          bookingLocalUuid: bookingUuid,
          amount: 1000,
          type: AdjustmentType.discount,
          effectiveHotelDay: '2026-08-05',
          endHotelDay: '2026-08-05',
          reason: 'خصم خاص',
          appliedBy: 'المدير',
        );

        final updatedBooking = await (db.select(
          db.bookings,
        )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

        expect(updatedBooking.totalDueCached, equals(7 * 15000 - 4 * 1000));

        final nights =
            await (db.select(db.bookingNights)
                  ..where((n) => n.bookingLocalId.equals(booking.id))
                  ..orderBy([(n) => OrderingTerm.asc(n.hotelDayKey)]))
                .get();

        expect(nights[0].finalRate, equals(15000));
        expect(nights[1].finalRate, equals(15000));
        expect(nights[2].finalRate, equals(14000));
        expect(nights[3].finalRate, equals(14000));
        expect(nights[4].finalRate, equals(14000));
        expect(nights[5].finalRate, equals(14000));
        expect(nights[6].finalRate, equals(15000));
      },
    );
  });

  group('السيناريو 2: زيادة سعر للشهر الثاني', () {
    test('نزيل 40 ليلة، زيادة 3000 من الليلة 31', () async {
      final roomUuid = IdGen.uuid();
      final bookingUuid = IdGen.uuid();
      final now = Time.nowEpoch();

      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(roomUuid),
              roomNumber: const Value('102'),
              type: const Value('standard'),
              price: const Value(15000),
              status: const Value('occupied'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: Value(bookingUuid),
              roomNumber: const Value('102'),
              guestName: const Value('سالم أحمد'),
              guestPhone: const Value('0500000000'),
              guestNationality: const Value('يمني'),
              checkinDate: const Value('2026-08-07T06:00:00'),
              status: const Value('checked_in'),
              discount: const Value(0),
              discountType: const Value('nightly'),
              calculatedNights: const Value(40),
              expectedNights: const Value(40),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      final booking = await (db.select(
        db.bookings,
      )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

      final startDate = DateTime(2025, 1, 14);
      for (var i = 0; i < 40; i++) {
        final hotelDay = startDate.add(Duration(days: i));
        final hotelDayKey =
            '${hotelDay.year}-${hotelDay.month.toString().padLeft(2, '0')}-${hotelDay.day.toString().padLeft(2, '0')}';
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value(IdGen.uuid()),
                bookingLocalId: Value(booking.id),
                hotelDayKey: Value(hotelDayKey),
                nightStart: const Value('2026-07-24T14:00:00'),
                nightEnd: const Value('2026-07-25T12:00:00'),
                nightlyRate: const Value(15000),
                baseRate: const Value(15000),
                adjustment: const Value(0),
                finalRate: const Value(15000),
                sequence: Value(i + 1),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );
      }

      await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: bookingUuid,
        amount: 3000,
        type: AdjustmentType.surcharge,
        effectiveHotelDay: '2026-09-05',
        reason: 'زيادة الشهر الثاني',
        appliedBy: 'المدير',
      );

      final updatedBooking = await (db.select(
        db.bookings,
      )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

      expect(updatedBooking.totalDueCached, equals(30 * 15000 + 10 * 18000));

      final report = await adjustmentService.generateLostRevenueReport();

      expect(report.totalGainedRevenue, equals(10 * 3000));
    });
  });

  group('السيناريو 3: إلغاء تخفيض', () {
    test('نزيل لديه خصم 1000 من 01-02، إلغاء في 10-02', () async {
      final roomUuid = IdGen.uuid();
      final bookingUuid = IdGen.uuid();
      final now = Time.nowEpoch();

      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(roomUuid),
              roomNumber: const Value('103'),
              type: const Value('standard'),
              price: const Value(15000),
              status: const Value('occupied'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: Value(bookingUuid),
              roomNumber: const Value('103'),
              guestName: const Value('محمد علي'),
              guestPhone: const Value('0500000000'),
              guestNationality: const Value('يمني'),
              checkinDate: const Value('2026-08-24T10:00:00'),
              status: const Value('checked_in'),
              discount: const Value(0),
              discountType: const Value('nightly'),
              calculatedNights: const Value(15),
              expectedNights: const Value(15),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      final booking = await (db.select(
        db.bookings,
      )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

      for (var i = 0; i < 15; i++) {
        final hotelDay = DateTime(2025, 2, 1).add(Duration(days: i));
        final hotelDayKey =
            '${hotelDay.year}-${hotelDay.month.toString().padLeft(2, '0')}-${hotelDay.day.toString().padLeft(2, '0')}';
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value(IdGen.uuid()),
                bookingLocalId: Value(booking.id),
                hotelDayKey: Value(hotelDayKey),
                nightStart: const Value('2026-07-24T14:00:00'),
                nightEnd: const Value('2026-07-25T12:00:00'),
                nightlyRate: const Value(15000),
                baseRate: const Value(15000),
                adjustment: const Value(0),
                finalRate: const Value(15000),
                sequence: Value(i + 1),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );
      }

      final adjustment = await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: bookingUuid,
        amount: 1000,
        type: AdjustmentType.discount,
        effectiveHotelDay: '2026-08-24',
        reason: 'خصم مستمر',
        appliedBy: 'المدير',
      );

      var updatedBooking = await (db.select(
        db.bookings,
      )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

      expect(updatedBooking.totalDueCached, equals(15 * 14000));

      await adjustmentService.cancelAdjustment(
        adjustmentUuid: adjustment.localUuid,
        cancelledBy: 'المدير',
      );

      updatedBooking = await (db.select(
        db.bookings,
      )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

      expect(updatedBooking.totalDueCached, equals(15 * 15000));

      final activeAdjustments = await adjustmentService.getActiveAdjustments(
        bookingUuid,
      );
      expect(activeAdjustments.isEmpty, isTrue);
    });
  });

  group('السيناريو 4: مزامنة بعد إعادة تثبيت', () {
    test('إعادة حساب 16 ليلة مع تخفيضات سابقة', () async {
      final roomUuid = IdGen.uuid();
      final bookingUuid = IdGen.uuid();
      final now = Time.nowEpoch();

      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(roomUuid),
              roomNumber: const Value('104'),
              type: const Value('standard'),
              price: const Value(15000),
              status: const Value('occupied'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: Value(bookingUuid),
              roomNumber: const Value('104'),
              guestName: const Value('خالد سعيد'),
              guestPhone: const Value('0500000000'),
              guestNationality: const Value('يمني'),
              checkinDate: const Value('2026-08-07T06:00:00'),
              status: const Value('checked_in'),
              discount: const Value(0),
              discountType: const Value('nightly'),
              calculatedNights: const Value(16),
              expectedNights: const Value(16),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      final booking = await (db.select(
        db.bookings,
      )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

      final adjustmentUuid = IdGen.uuid();
      await db
          .into(db.bookingPriceAdjustments)
          .insert(
            BookingPriceAdjustmentsCompanion(
              localUuid: Value(adjustmentUuid),
              bookingLocalUuid: Value(bookingUuid),
              bookingLocalId: Value(booking.id),
              adjustmentType: Value(AdjustmentType.discount.value),
              amount: const Value(2000),
              effectiveHotelDay: const Value('2026-08-03'),
              endHotelDay: const Value('2026-08-17'),
              isActive: const Value(true),
              reason: const Value('خصم أسبوعي'),
              appliedBy: const Value('المدير'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      for (var i = 0; i < 16; i++) {
        final hotelDay = DateTime(2025, 1, 14).add(Duration(days: i));
        final hotelDayKey =
            '${hotelDay.year}-${hotelDay.month.toString().padLeft(2, '0')}-${hotelDay.day.toString().padLeft(2, '0')}';
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value(IdGen.uuid()),
                bookingLocalId: Value(booking.id),
                hotelDayKey: Value(hotelDayKey),
                nightStart: const Value('2026-07-24T14:00:00'),
                nightEnd: const Value('2026-07-25T12:00:00'),
                nightlyRate: const Value(15000),
                baseRate: const Value(15000),
                adjustment: const Value(0),
                finalRate: const Value(15000),
                sequence: Value(i + 1),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );
      }

      await adjustmentService.recalculateAfterSync(booking.id);

      final updatedBooking = await (db.select(
        db.bookings,
      )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

      expect(updatedBooking.totalDueCached, equals(10 * 15000 + 6 * 13000));

      final nights =
          await (db.select(db.bookingNights)
                ..where((n) => n.bookingLocalId.equals(booking.id))
                ..orderBy([(n) => OrderingTerm.asc(n.hotelDayKey)]))
              .get();

      final discountedNights = nights.where((n) => n.adjustment != 0).toList();
      expect(discountedNights.length, equals(6));
    });
  });

  group('Integer Amount Tests', () {
    test('جميع المبالغ أعداد صحيحة بدون كسور', () async {
      final roomUuid = IdGen.uuid();
      final bookingUuid = IdGen.uuid();
      final now = Time.nowEpoch();

      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(roomUuid),
              roomNumber: const Value('105'),
              type: const Value('standard'),
              price: const Value(15000),
              status: const Value('occupied'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: Value(bookingUuid),
              roomNumber: const Value('105'),
              guestName: const Value('عمر أحمد'),
              guestPhone: const Value('0500000000'),
              guestNationality: const Value('يمني'),
              checkinDate: const Value('2026-08-12T10:00:00'),
              status: const Value('checked_in'),
              discount: const Value(0),
              discountType: const Value('nightly'),
              calculatedNights: const Value(5),
              expectedNights: const Value(5),
              totalDueCached: const Value(75000),
              totalPaidCached: const Value(50000),
              remainingBalanceCached: const Value(25000),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      final booking = await (db.select(
        db.bookings,
      )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

      expect(booking.totalDueCached, isA<int>());
      expect(booking.totalPaidCached, isA<int>());
      expect(booking.remainingBalanceCached, isA<int>());
      expect(booking.discount, isA<int>());

      final room = await (db.select(
        db.rooms,
      )..where((r) => r.localUuid.equals(roomUuid))).getSingle();

      expect(room.price, isA<int>());
      expect(room.price, equals(15000));
    });
  });

  group('Lost Revenue Report Tests', () {
    test('تقرير الإيرادات المفقودة يحسب بشكل صحيح', () async {
      final roomUuid = IdGen.uuid();
      final bookingUuid = IdGen.uuid();
      final now = Time.nowEpoch();

      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(roomUuid),
              roomNumber: const Value('106'),
              type: const Value('standard'),
              price: const Value(20000),
              status: const Value('occupied'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: Value(bookingUuid),
              roomNumber: const Value('106'),
              guestName: const Value('فاطمة علي'),
              guestPhone: const Value('0500000000'),
              guestNationality: const Value('يمني'),
              checkinDate: const Value('2026-07-24T10:00:00'),
              status: const Value('checked_in'),
              discount: const Value(0),
              discountType: const Value('nightly'),
              calculatedNights: const Value(10),
              expectedNights: const Value(10),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      final booking = await (db.select(
        db.bookings,
      )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

      for (var i = 0; i < 10; i++) {
        final hotelDay = DateTime(2025, 1, 1).add(Duration(days: i));
        final hotelDayKey =
            '${hotelDay.year}-${hotelDay.month.toString().padLeft(2, '0')}-${hotelDay.day.toString().padLeft(2, '0')}';
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value(IdGen.uuid()),
                bookingLocalId: Value(booking.id),
                hotelDayKey: Value(hotelDayKey),
                nightStart: const Value('2026-07-24T14:00:00'),
                nightEnd: const Value('2026-07-25T12:00:00'),
                nightlyRate: const Value(20000),
                baseRate: const Value(20000),
                adjustment: const Value(0),
                finalRate: const Value(20000),
                sequence: Value(i + 1),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );
      }

      await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: bookingUuid,
        amount: 5000,
        type: AdjustmentType.discount,
        effectiveHotelDay: '2026-07-26',
        endHotelDay: '2026-07-30',
        reason: 'خصم VIP',
        appliedBy: 'المدير',
      );

      final report = await adjustmentService.generateLostRevenueReport();

      expect(report.totalLostRevenue, equals(5 * 5000));
      expect(report.totalPotentialRevenue, equals(10 * 20000));
      expect(report.bookingDetails.length, equals(1));
      expect(report.bookingDetails.first.adjustments.length, equals(1));
    });
  });
}
