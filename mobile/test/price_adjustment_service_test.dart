import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/price_adjustment_service.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  late AppDatabase db;
  late PriceAdjustmentService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = PriceAdjustmentService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('تعديل السعر أثناء الإقامة', () {
    test(
      'السيناريو: دخول يوم 5 بسعر 10000، رفع السعر يوم 10 إلى 12000',
      () async {
        final roomUuid = 'room-101-uuid';
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion(
                localUuid: Value(roomUuid),
                roomNumber: const Value('101'),
                type: const Value('عادية'),
                price: const Value(10000.0),
                status: const Value('محجوزة'),
                createdAt: Value(Time.nowEpoch()),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );

        final bookingUuid = 'booking-guest-uuid';
        final bookingId = await db
            .into(db.bookings)
            .insert(
              BookingsCompanion(
                localUuid: Value(bookingUuid),
                roomNumber: const Value('101'),
                guestName: const Value('أحمد محمد'),
                guestPhone: const Value('777123456'),
                guestNationality: const Value('يمني'),
                checkinDate: const Value('2026-02-05T15:00:00'),
                status: const Value('مؤكد'),
                discount: const Value(0),
                discountType: const Value('per_night'),
                expectedNights: const Value(10),
                calculatedNights: const Value(10),
                totalDueCached: const Value(100000.0),
                totalPaidCached: const Value(0),
                remainingBalanceCached: const Value(100000.0),
                createdAt: Value(Time.nowEpoch()),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );

        final nightDates = [
          '2026-02-05',
          '2026-02-06',
          '2026-02-07',
          '2026-02-08',
          '2026-02-09',
          '2026-02-10',
          '2026-02-11',
          '2026-02-12',
          '2026-02-13',
          '2026-02-14',
        ];

        for (var i = 0; i < nightDates.length; i++) {
          await db
              .into(db.bookingNights)
              .insert(
                BookingNightsCompanion(
                  localUuid: Value('night-$i-uuid'),
                  bookingLocalId: Value(bookingId),
                  hotelDayKey: Value(nightDates[i]),
                  nightStart: Value('${nightDates[i]}T14:00:00'),
                  nightEnd: Value(
                    '${nightDates[(i + 1) % nightDates.length]}T14:00:00',
                  ),
                  nightlyRate: const Value(10000.0),
                  sequence: Value(i + 1),
                  createdAt: Value(Time.nowEpoch()),
                  updatedAt: Value(Time.nowEpoch()),
                  lastModified: Value(Time.nowEpoch()),
                ),
              );
        }

        final preview = await service.previewPriceChange(
          roomNumber: '101',
          newPrice: 12000.0,
          effectiveFrom: DateTime.parse('2026-02-10T14:00:00'),
        );

        expect(preview['bookingsAffected'], 1);
        expect(preview['totalNightsAffected'], 5);
        expect(preview['totalOldAmount'], 50000.0);
        expect(preview['totalNewAmount'], 60000.0);
        expect(preview['totalDifference'], 10000.0);

        final result = await service.applyRoomPriceChange(
          roomNumber: '101',
          oldPrice: 10000.0,
          newPrice: 12000.0,
          appliedBy: 'admin',
          reason: 'رفع السعر الموسمي',
          effectiveFrom: DateTime.parse('2026-02-10T14:00:00'),
        );

        expect(result.success, true);
        expect(result.bookingsAffected, 1);
        expect(result.nightsUpdated, 5);

        final updatedNights =
            await (db.select(db.bookingNights)
                  ..where((n) => n.bookingLocalId.equals(bookingId))
                  ..orderBy([(n) => OrderingTerm.asc(n.hotelDayKey)]))
                .get();

        expect(updatedNights[0].nightlyRate, 10000.0);
        expect(updatedNights[1].nightlyRate, 10000.0);
        expect(updatedNights[2].nightlyRate, 10000.0);
        expect(updatedNights[3].nightlyRate, 10000.0);
        expect(updatedNights[4].nightlyRate, 10000.0);

        expect(updatedNights[5].nightlyRate, 12000.0);
        expect(updatedNights[6].nightlyRate, 12000.0);
        expect(updatedNights[7].nightlyRate, 12000.0);
        expect(updatedNights[8].nightlyRate, 12000.0);
        expect(updatedNights[9].nightlyRate, 12000.0);

        final updatedBooking = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(bookingId))).getSingle();

        final expectedTotal = (5 * 10000.0) + (5 * 12000.0);
        expect(updatedBooking.totalDueCached, expectedTotal);
        expect(updatedBooking.remainingBalanceCached, expectedTotal);

        final adjustments = await service.getAdjustmentsForRoom(roomUuid);
        expect(adjustments.length, 1);
        expect(adjustments.first.previousValue, 10000.0);
        expect(adjustments.first.newValue, 12000.0);
        expect(adjustments.first.reason, 'رفع السعر الموسمي');

        final auditLogs = await db.select(db.auditLogs).get();
        expect(auditLogs.length, 5);
        expect(auditLogs.first.isFinancial, true);
      },
    );

    test('تعديل السعر مع خصم per_night', () async {
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: const Value('room-102-uuid'),
              roomNumber: const Value('102'),
              type: const Value('عادية'),
              price: const Value(10000.0),
              status: const Value('محجوزة'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      final bookingId = await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: const Value('booking-discount-uuid'),
              roomNumber: const Value('102'),
              guestName: const Value('علي أحمد'),
              guestPhone: const Value('777999888'),
              guestNationality: const Value('يمني'),
              checkinDate: const Value('2026-02-05T15:00:00'),
              status: const Value('مؤكد'),
              discount: const Value(2000),
              discountType: const Value('per_night'),
              discountStartDate: const Value('2026-02-05'),
              expectedNights: const Value(5),
              calculatedNights: const Value(5),
              totalDueCached: const Value(40000.0),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      for (var i = 0; i < 5; i++) {
        final date = '2026-02-0${5 + i}';
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value('night-discount-$i-uuid'),
                bookingLocalId: Value(bookingId),
                hotelDayKey: Value(date),
                nightStart: Value('${date}T14:00:00'),
                nightEnd: Value('2026-02-0${6 + i}T14:00:00'),
                nightlyRate: const Value(8000.0),
                sequence: Value(i + 1),
                createdAt: Value(Time.nowEpoch()),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );
      }

      final result = await service.applyRoomPriceChange(
        roomNumber: '102',
        oldPrice: 10000.0,
        newPrice: 12000.0,
        appliedBy: 'admin',
        effectiveFrom: DateTime.parse('2026-02-07T14:00:00'),
      );

      expect(result.success, true);
      expect(result.nightsUpdated, 3);

      final nights =
          await (db.select(db.bookingNights)
                ..where((n) => n.bookingLocalId.equals(bookingId))
                ..orderBy([(n) => OrderingTerm.asc(n.hotelDayKey)]))
              .get();

      expect(nights[0].nightlyRate, 8000.0);
      expect(nights[1].nightlyRate, 8000.0);

      expect(nights[2].nightlyRate, 10000.0);
      expect(nights[3].nightlyRate, 10000.0);
      expect(nights[4].nightlyRate, 10000.0);
    });

    test('تعديل السعر لا يؤثر على الحجوزات المغلقة', () async {
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: const Value('room-103-uuid'),
              roomNumber: const Value('103'),
              type: const Value('عادية'),
              price: const Value(10000.0),
              status: const Value('شاغرة'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      final bookingId = await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: const Value('booking-closed-uuid'),
              roomNumber: const Value('103'),
              guestName: const Value('محمد علي'),
              guestPhone: const Value('777111222'),
              guestNationality: const Value('يمني'),
              checkinDate: const Value('2026-02-01T15:00:00'),
              actualCheckout: const Value('2026-02-05T12:00:00'),
              status: const Value('مغادر'),
              discount: const Value(0),
              discountType: const Value('per_night'),
              totalDueCached: const Value(40000.0),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      for (var i = 0; i < 4; i++) {
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value('night-closed-$i-uuid'),
                bookingLocalId: Value(bookingId),
                hotelDayKey: Value('2026-02-0${1 + i}'),
                nightlyRate: const Value(10000.0),
                sequence: Value(i + 1),
                createdAt: Value(Time.nowEpoch()),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );
      }

      final result = await service.applyRoomPriceChange(
        roomNumber: '103',
        oldPrice: 10000.0,
        newPrice: 15000.0,
        appliedBy: 'admin',
        effectiveFrom: DateTime.parse('2026-02-03T14:00:00'),
      );

      expect(result.success, true);
      expect(result.bookingsAffected, 0);
      expect(result.nightsUpdated, 0);

      final nights = await (db.select(
        db.bookingNights,
      )..where((n) => n.bookingLocalId.equals(bookingId))).get();

      for (final night in nights) {
        expect(night.nightlyRate, 10000.0);
      }
    });

    test('معاينة التغيير قبل التطبيق', () async {
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: const Value('room-104-uuid'),
              roomNumber: const Value('104'),
              type: const Value('عادية'),
              price: const Value(8000.0),
              status: const Value('محجوزة'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      final bookingId = await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: const Value('booking-preview-uuid'),
              roomNumber: const Value('104'),
              guestName: const Value('سعيد أحمد'),
              guestPhone: const Value('777333444'),
              guestNationality: const Value('يمني'),
              checkinDate: const Value('2026-02-10T15:00:00'),
              status: const Value('مؤكد'),
              discount: const Value(0),
              discountType: const Value('per_night'),
              totalDueCached: const Value(24000.0),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      for (var i = 0; i < 3; i++) {
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value('night-preview-$i-uuid'),
                bookingLocalId: Value(bookingId),
                hotelDayKey: Value('2026-02-1$i'),
                nightlyRate: const Value(8000.0),
                sequence: Value(i + 1),
                createdAt: Value(Time.nowEpoch()),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );
      }

      final preview = await service.previewPriceChange(
        roomNumber: '104',
        newPrice: 10000.0,
        effectiveFrom: DateTime.parse('2026-02-11T14:00:00'),
      );

      expect(preview['bookingsAffected'], 1);
      expect(preview['totalNightsAffected'], 2);
      expect(preview['totalOldAmount'], 16000.0);
      expect(preview['totalNewAmount'], 20000.0);
      expect(preview['totalDifference'], 4000.0);

      final nightsAfterPreview = await db.select(db.bookingNights).get();
      for (final night in nightsAfterPreview) {
        expect(night.nightlyRate, 8000.0);
      }
    });
  });
}
