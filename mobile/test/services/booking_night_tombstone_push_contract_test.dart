import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/enhanced_booking_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync/payload_normalizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'المغادرة المبكرة تمرر tombstone الليلة إلى Worker عبر buildPushOperation',
    () async {
      final now = DateTime.now().toUtc();
      final departure = now.subtract(const Duration(hours: 2));
      final firstNightStart = departure.subtract(const Duration(days: 1));
      final secondNightStart = departure.add(const Duration(hours: 1));
      final createdAt = now.millisecondsSinceEpoch ~/ 1000;

      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: const d.Value('room-tombstone-contract'),
              roomNumber: const d.Value('T-101'),
              type: const d.Value('standard'),
              price: const d.Value(100),
              status: const d.Value('occupied'),
              createdAt: d.Value(createdAt),
              updatedAt: d.Value(createdAt),
              lastModified: d.Value(createdAt),
            ),
          );

      final bookingId = await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: const d.Value('booking-tombstone-contract'),
              roomNumber: const d.Value('T-101'),
              guestName: const d.Value('Contract test'),
              guestPhone: const d.Value(''),
              guestNationality: const d.Value(''),
              checkinDate: d.Value(firstNightStart.toIso8601String()),
              checkoutDate: d.Value(
                secondNightStart.add(const Duration(days: 1)).toIso8601String(),
              ),
              actualCheckout: d.Value(departure.toIso8601String()),
              status: const d.Value('مكتمل'),
              createdAt: d.Value(createdAt),
              updatedAt: d.Value(createdAt),
              lastModified: d.Value(createdAt),
            ),
          );

      String hotelDayKey(DateTime date) =>
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

      Future<void> insertNight({
        required String uuid,
        required DateTime start,
      }) async {
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: d.Value(uuid),
                bookingLocalId: d.Value(bookingId),
                bookingUuidCache: const d.Value('booking-tombstone-contract'),
                hotelDayKey: d.Value(hotelDayKey(start)),
                nightStart: d.Value(start.toIso8601String()),
                nightEnd: d.Value(
                  start.add(const Duration(days: 1)).toIso8601String(),
                ),
                nightlyRate: const d.Value(100),
                baseRate: const d.Value(100),
                finalRate: const d.Value(100),
                createdAt: d.Value(createdAt),
                updatedAt: d.Value(createdAt),
                lastModified: d.Value(createdAt),
              ),
            );
      }

      await insertNight(
        uuid: 'night-retained-contract',
        start: firstNightStart,
      );
      await insertNight(
        uuid: 'night-deleted-contract',
        start: secondNightStart,
      );

      final booking = await (db.select(
        db.bookings,
      )..where((row) => row.id.equals(bookingId))).getSingle();
      await EnhancedBookingCalculationService(db).refreshCompletedStay(booking);

      final deletedNight =
          await (db.select(db.bookingNights)..where(
                (night) => night.localUuid.equals('night-deleted-contract'),
              ))
              .getSingle();
      expect(deletedNight.deletedAt, isNotNull);
      expect(deletedNight.lastModified, deletedNight.deletedAt);

      final outboxItem =
          await (db.select(db.outbox)
                ..where((item) => item.entity.equals('booking_nights'))
                ..where(
                  (item) => item.localUuid.equals('night-deleted-contract'),
                ))
              .getSingle();
      final payload = jsonDecode(outboxItem.payload) as Map<String, dynamic>;
      expect(payload['deletedAt'], deletedNight.deletedAt);
      expect(payload['lastModified'], deletedNight.lastModified);

      final operation = await buildPushOperation(
        outboxItem,
        resolveRowVectorClock: (_, __) async => null,
      );
      final data = operation['data'] as Map<String, dynamic>;

      expect(operation['entity'], 'booking_nights');
      expect(operation['operation'], 'update');
      expect(data['local_uuid'], 'night-deleted-contract');
      expect(data['deleted_at'], deletedNight.deletedAt);
      expect(data['deleted_at_iso'], deletedNight.deletedAtIso);
      expect(data['last_modified'], deletedNight.lastModified);
      expect(data['last_modified_epoch'], deletedNight.lastModifiedEpoch);
      // Service and adapter store these sync epochs in seconds; normalizing
      // camelCase keys must not alter those already-second-based timestamps.
      expect(data['deleted_at'], lessThan(PayloadNormalizer.millisThreshold));
      expect(
        data['last_modified'],
        lessThan(PayloadNormalizer.millisThreshold),
      );
      expect(data.containsKey('deletedAt'), isFalse);
      expect(data.containsKey('lastModified'), isFalse);
    },
  );
}
