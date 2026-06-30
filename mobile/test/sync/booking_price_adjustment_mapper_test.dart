// ignore_for_file: avoid_dynamic_calls, prefer_const_declarations, prefer_const_constructors, directives_ordering, no_leading_underscores_for_local_identifiers

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync/payload_mapper.dart';

/// اختبارات PayloadMapper لـ booking_price_adjustments
///
/// هذا الكيان هو **الأساس** لتطبيق التخفيضات والزيادات على الحجوزات.
/// كل تعديل سعر (discount, surcharge, override) يُمثَّل كسجل في هذا الجدول.
///
/// تستخدم Drift database في الذاكرة (NativeDatabase.memory()) لإنشاء
/// كائنات BookingPriceAdjustment حقيقية واختبار الـ mapper عليها.
///
/// ملاحظة: booking_price_adjustments لها FK على bookings عبر bookingLocalUuid،
/// لذا نُنشئ booking أولاً في كل اختبار.

void main() {
  late AppDatabase database;
  late PayloadMapper mapper;

  setUpAll(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    mapper = const PayloadMapper();
  });

  tearDownAll(() async {
    await database.close();
  });

  // Helper: إنشاء room + booking لاستخدامهما في اختبارات booking_price_adjustments
  // (bookings لها FK على rooms عبر roomNumber، و booking_price_adjustments
  // لها FK على bookings عبر bookingLocalUuid)
  Future<String> _createBooking(String uuid, String roomNumber) async {
    // إنشاء room أولاً
    await database.into(database.rooms).insert(
          RoomsCompanion.insert(
            localUuid: 'room-$roomNumber',
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
            version: drift.Value(1),
            origin: drift.Value('mobile'),
            vectorClock: drift.Value('{}'),
            deviceId: drift.Value('device-test'),
            roomNumber: roomNumber,
            type: 'standard',
            price: 200.0,
            status: 'available',
          ),
        );
    // ثم إنشاء booking مرتبط بالـ room
    await database.into(database.bookings).insert(
          BookingsCompanion.insert(
            localUuid: uuid,
            createdAt: 1700000000,
            updatedAt: 1700000000,
            lastModified: 1700000000,
            version: drift.Value(1),
            origin: drift.Value('mobile'),
            vectorClock: drift.Value('{}'),
            deviceId: drift.Value('device-test'),
            roomNumber: roomNumber,
            guestName: 'ضيف تجريبي',
            guestPhone: '0501234567',
            guestNationality: 'مصري',
            checkinDate: '2026-01-15',
            status: 'checked_in',
          ),
        );
    return uuid;
  }

  group('bookingPriceAdjustmentToRemote', () {
    test('returns all required sync and business fields for discount', () async {
      final bookingUuid = 'booking-uuid-001';
      await _createBooking(bookingUuid, '101');

      final uuid = 'test-bpa-uuid-001';
      final insertedId = await database.into(database.bookingPriceAdjustments)
          .insert(
        BookingPriceAdjustmentsCompanion.insert(
          localUuid: uuid,
          createdAt: 1700000000,
          updatedAt: 1700000000,
          lastModified: 1700000100,
          version: drift.Value(1),
          origin: drift.Value('mobile'),
          vectorClock: drift.Value('{}'),
          deviceId: drift.Value('device-001'),
          bookingLocalUuid: bookingUuid,
          // adjustmentType: 1 = discount (تخفيض)
          adjustmentType: drift.Value(1),
          adjustmentMode: drift.Value('per_night'),
          amount: drift.Value(50.0),
          effectiveHotelDay: '2026-01-15',
          isActive: drift.Value(true),
        ),
      );
      final adj = await (database.select(database.bookingPriceAdjustments)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.bookingPriceAdjustmentToRemote(adj);

      // ── Sync fields ──
      expect(payload['localUuid'], uuid);
      expect(payload['createdAt'], 1700000000);
      expect(payload['updatedAt'], 1700000000);
      expect(payload['lastModified'], 1700000100);
      expect(payload['version'], 1);
      expect(payload['origin'], 'mobile');
      expect(payload['sync_origin'], 'mobile');
      expect(payload['syncTimestamp'], isNotNull);
      expect(payload['vectorClock'], '{}');
      expect(payload['deviceId'], 'device-001');

      // ── Business fields (discount) ──
      expect(payload['bookingLocalUuid'], bookingUuid);
      expect(payload['adjustmentType'], 1); // discount
      expect(payload['adjustmentMode'], 'per_night');
      expect(payload['amount'], 50); // rounded to int for Appwrite
      expect(payload['effectiveHotelDay'], '2026-01-15');
      expect(payload['isActive'], isTrue);

      // serverId should be absent (null)
      expect(payload.containsKey('serverId'), isFalse);
    });

    test('returns all required fields for surcharge (زيادة)', () async {
      final bookingUuid = 'booking-uuid-002';
      await _createBooking(bookingUuid, '202');

      final uuid = 'test-bpa-uuid-002';
      final insertedId = await database.into(database.bookingPriceAdjustments)
          .insert(
        BookingPriceAdjustmentsCompanion.insert(
          localUuid: uuid,
          createdAt: 1700000000,
          updatedAt: 1700000000,
          lastModified: 1700000100,
          version: drift.Value(1),
          origin: drift.Value('mobile'),
          vectorClock: drift.Value('{}'),
          deviceId: drift.Value('device-002'),
          bookingLocalUuid: bookingUuid,
          // adjustmentType: 2 = surcharge (زيادة)
          adjustmentType: drift.Value(2),
          adjustmentMode: drift.Value('fixed'),
          amount: drift.Value(100.75), // should round to 101
          effectiveHotelDay: '2026-02-20',
          isActive: drift.Value(true),
        ),
      );
      final adj = await (database.select(database.bookingPriceAdjustments)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.bookingPriceAdjustmentToRemote(adj);

      expect(payload['adjustmentType'], 2); // surcharge
      expect(payload['adjustmentMode'], 'fixed');
      expect(payload['amount'], 101); // 100.75 rounds to 101
      expect(payload['effectiveHotelDay'], '2026-02-20');
    });

    test('includes optional fields when present (roomNumber, reason, appliedBy)', () async {
      final bookingUuid = 'booking-uuid-003';
      await _createBooking(bookingUuid, '303');

      final uuid = 'test-bpa-uuid-003';
      final insertedId = await database.into(database.bookingPriceAdjustments)
          .insert(
        BookingPriceAdjustmentsCompanion.insert(
          localUuid: uuid,
          createdAt: 1700000000,
          updatedAt: 1700000000,
          lastModified: 1700000100,
          version: drift.Value(1),
          origin: drift.Value('mobile'),
          vectorClock: drift.Value('{}'),
          deviceId: drift.Value('device-003'),
          bookingLocalUuid: bookingUuid,
          roomNumber: drift.Value('303'),
          adjustmentType: drift.Value(1),
          adjustmentMode: drift.Value('per_night'),
          amount: drift.Value(25.0),
          effectiveHotelDay: '2026-03-01',
          endHotelDay: drift.Value('2026-03-05'),
          isActive: drift.Value(true),
          reason: drift.Value('تخفيض للعميل VIP'),
          appliedBy: drift.Value('admin'),
        ),
      );
      final adj = await (database.select(database.bookingPriceAdjustments)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.bookingPriceAdjustmentToRemote(adj);

      expect(payload['roomNumber'], '303');
      expect(payload['endHotelDay'], '2026-03-05');
      expect(payload['reason'], 'تخفيض للعميل VIP');
      expect(payload['appliedBy'], 'admin');
    });

    test('omits optional fields when null', () async {
      final bookingUuid = 'booking-uuid-004';
      await _createBooking(bookingUuid, '404');

      final uuid = 'test-bpa-uuid-004';
      final insertedId = await database.into(database.bookingPriceAdjustments)
          .insert(
        BookingPriceAdjustmentsCompanion.insert(
          localUuid: uuid,
          createdAt: 1700000000,
          updatedAt: 1700000000,
          lastModified: 1700000100,
          version: drift.Value(1),
          origin: drift.Value('mobile'),
          vectorClock: drift.Value('{}'),
          deviceId: drift.Value('device-004'),
          bookingLocalUuid: bookingUuid,
          adjustmentType: drift.Value(1),
          adjustmentMode: drift.Value('per_night'),
          amount: drift.Value(10.0),
          effectiveHotelDay: '2026-04-01',
          // roomNumber, endHotelDay, reason, appliedBy = null
        ),
      );
      final adj = await (database.select(database.bookingPriceAdjustments)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.bookingPriceAdjustmentToRemote(adj);

      // null optional fields should NOT be in the payload
      expect(payload.containsKey('bookingLocalId'), isFalse);
      expect(payload.containsKey('roomNumber'), isFalse);
      expect(payload.containsKey('endHotelDay'), isFalse);
      expect(payload.containsKey('reason'), isFalse);
      expect(payload.containsKey('appliedBy'), isFalse);
    });

    test('handles cancellation fields (cancelledAt, cancelledBy)', () async {
      final bookingUuid = 'booking-uuid-005';
      await _createBooking(bookingUuid, '505');

      final uuid = 'test-bpa-uuid-005';
      final insertedId = await database.into(database.bookingPriceAdjustments)
          .insert(
        BookingPriceAdjustmentsCompanion.insert(
          localUuid: uuid,
          createdAt: 1700000000,
          updatedAt: 1700000000,
          lastModified: 1700000200,
          version: drift.Value(2),
          origin: drift.Value('mobile'),
          vectorClock: drift.Value('{}'),
          deviceId: drift.Value('device-005'),
          bookingLocalUuid: bookingUuid,
          adjustmentType: drift.Value(1),
          adjustmentMode: drift.Value('per_night'),
          amount: drift.Value(30.0),
          effectiveHotelDay: '2026-05-01',
          isActive: drift.Value(false), // cancelled
          cancelledAt: drift.Value('2026-05-02T10:00:00Z'),
          cancelledBy: drift.Value('manager'),
        ),
      );
      final adj = await (database.select(database.bookingPriceAdjustments)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.bookingPriceAdjustmentToRemote(adj);

      expect(payload['isActive'], isFalse);
      expect(payload['cancelledAt'], '2026-05-02T10:00:00Z');
      expect(payload['cancelledBy'], 'manager');
    });

    test('rounds amount correctly (negative for discounts)', () async {
      final bookingUuid = 'booking-uuid-006';
      await _createBooking(bookingUuid, '606');

      final uuid = 'test-bpa-uuid-006';
      final insertedId = await database.into(database.bookingPriceAdjustments)
          .insert(
        BookingPriceAdjustmentsCompanion.insert(
          localUuid: uuid,
          createdAt: 1700000000,
          updatedAt: 1700000000,
          lastModified: 1700000100,
          version: drift.Value(1),
          origin: drift.Value('mobile'),
          vectorClock: drift.Value('{}'),
          deviceId: drift.Value('device-006'),
          bookingLocalUuid: bookingUuid,
          adjustmentType: drift.Value(1),
          adjustmentMode: drift.Value('percentage'),
          amount: drift.Value(-15.6), // negative discount
          effectiveHotelDay: '2026-06-01',
        ),
      );
      final adj = await (database.select(database.bookingPriceAdjustments)
            ..where((t) => t.id.equals(insertedId)))
          .getSingle();

      final payload = mapper.bookingPriceAdjustmentToRemote(adj);

      // -15.6 rounds to -16
      expect(payload['amount'], -16);
      expect(payload['adjustmentMode'], 'percentage');
    });
  });
}
