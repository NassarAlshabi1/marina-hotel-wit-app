import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AdapterRegistry adapters;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapters = AdapterRegistry(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('BookingPriceAdjustmentsAdapter', () {
    test('round-trip from Appwrite with existing parent booking', () async {
      // ترتيب: إنشاء حجز أب في القاعدة
      final bookingUuid = 'booking-uuid-1';
      await db.into(db.bookings).insert(BookingsCompanion(
        localUuid: d.Value(bookingUuid),
        roomNumber: const d.Value('101'),
        guestName: const d.Value('أحمد'),
        guestPhone: const d.Value('0500000000'),
        guestNationality: const d.Value('يمني'),
        checkinDate: const d.Value('2025-06-01'),
        status: const d.Value('checked_in'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      // تنفيذ: محاكاة سحب تعديل سعر من Appwrite
      final json = {
        'localUuid': 'adj-1',
        'bookingLocalUuid': bookingUuid,
        'roomNumber': '101',
        'adjustmentType': 0,
        'adjustmentMode': 'per_night',
        'amount': 1000.0,
        'effectiveHotelDay': '2025-06-03',
        'isActive': true,
        'reason': 'خصم',
        'appliedBy': 'admin',
        'createdAt': 2000,
        'lastModified': 2000,
      };

      final refs = await adapters.bookingPriceAdjustments.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      // التحقق: تم حل FK إلى معرف الحجز المحلي
      expect(refs.bookingLocalId, isNotNull);
      expect(refs.bookingUuidCache, equals(bookingUuid));

      final comp = adapters.bookingPriceAdjustments.adapter.fromJson(
        json,
        src: Source.appwrite,
        refs: refs,
      );

      await db.into(db.bookingPriceAdjustments).insert(comp);

      // التحقق: تم إدراج التعديل بنجاح
      final row = await db.select(db.bookingPriceAdjustments).getSingle();
      expect(row.localUuid, equals('adj-1'));
      expect(row.bookingLocalUuid, equals(bookingUuid));
      expect(row.amount, equals(1000.0));
      expect(row.isActive, isTrue);

      // التحقق من round-trip (toJson)
      final out = adapters.bookingPriceAdjustments.toJsonForSource(
        row,
        src: Source.appwrite,
      );
      expect(out['localUuid'], equals('adj-1'));
      expect(out['bookingLocalUuid'], equals(bookingUuid));
      expect(out['amount'], equals(1000)); // integer على Appwrite
    });

    test('resolveRefs returns null bookingLocalId when parent booking missing', () async {
      // تنفيذ: محاولة حل FK لتعديل سعر بدون حجز أب
      final json = {
        'localUuid': 'adj-orphan',
        'bookingLocalUuid': 'nonexistent-booking-uuid',
        'roomNumber': '102',
        'adjustmentType': 0,
        'adjustmentMode': 'total',
        'amount': 5000.0,
        'effectiveHotelDay': '2025-06-05',
        'isActive': true,
        'reason': 'تخفيض',
        'appliedBy': 'admin',
        'createdAt': 3000,
        'lastModified': 3000,
      };

      final refs = await adapters.bookingPriceAdjustments.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      // التحقق: لا يمكن حل FK لأن الحجز الأب غير موجود
      expect(refs.bookingLocalId, isNull);
      expect(refs.bookingUuidCache, equals('nonexistent-booking-uuid'));
    });

    test('fromJson with missing parent booking triggers FK error on insert', () async {
      // تنفيذ: محاولة إدراج تعديل سعر بدون حجز أب في القاعدة
      final json = {
        'localUuid': 'adj-fk-err',
        'bookingLocalUuid': 'ghost-booking',
        'roomNumber': '103',
        'adjustmentType': 0,
        'adjustmentMode': 'per_night',
        'amount': 2000.0,
        'effectiveHotelDay': '2025-06-10',
        'isActive': true,
        'reason': 'تخفيض',
        'appliedBy': 'admin',
        'createdAt': 4000,
        'lastModified': 4000,
      };

      final refs = await adapters.bookingPriceAdjustments.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      final comp = adapters.bookingPriceAdjustments.adapter.fromJson(
        json,
        src: Source.appwrite,
        refs: refs,
      );

      // التحقق: الإدراج يرمي خطأ FK constraint
      expect(
        () => db.into(db.bookingPriceAdjustments).insert(comp),
        throwsA(isA<Exception>()),
      );
    });

    test('cancelled adjustment round-trip', () async {
      final bookingUuid = 'booking-uuid-2';
      await db.into(db.bookings).insert(BookingsCompanion(
        localUuid: d.Value(bookingUuid),
        roomNumber: const d.Value('201'),
        guestName: const d.Value('محمد'),
        guestPhone: const d.Value('0500000001'),
        guestNationality: const d.Value('مصري'),
        checkinDate: const d.Value('2025-06-01'),
        status: const d.Value('checked_in'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      final json = {
        'localUuid': 'adj-cancelled',
        'bookingLocalUuid': bookingUuid,
        'roomNumber': '201',
        'adjustmentType': 0,
        'adjustmentMode': 'per_night',
        'amount': 1500.0,
        'effectiveHotelDay': '2025-06-03',
        'endHotelDay': '2025-06-05',
        'isActive': false,
        'reason': 'خصم VIP',
        'appliedBy': 'admin',
        'cancelledAt': '2025-06-06T10:00:00Z',
        'cancelledBy': 'admin',
        'createdAt': 5000,
        'lastModified': 6000,
      };

      final refs = await adapters.bookingPriceAdjustments.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );
      final comp = adapters.bookingPriceAdjustments.adapter.fromJson(
        json,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.bookingPriceAdjustments).insert(comp);

      final row = await db.select(db.bookingPriceAdjustments).getSingle();
      expect(row.isActive, isFalse);
      expect(row.cancelledAt, equals('2025-06-06T10:00:00Z'));
      expect(row.cancelledBy, equals('admin'));
      expect(row.endHotelDay, equals('2025-06-05'));
    });

    test('drive source uses snake_case keys', () async {
      final bookingUuid = 'booking-uuid-3';
      await db.into(db.bookings).insert(BookingsCompanion(
        localUuid: d.Value(bookingUuid),
        roomNumber: const d.Value('301'),
        guestName: const d.Value('علي'),
        guestPhone: const d.Value('0500000002'),
        guestNationality: const d.Value('سعودي'),
        checkinDate: const d.Value('2025-06-01'),
        status: const d.Value('checked_in'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      // من Drive، المفاتيح تكون snake_case
      final json = {
        'local_uuid': 'adj-drive-1',
        'booking_local_uuid': bookingUuid,
        'room_number': '301',
        'adjustment_type': 0,
        'adjustment_mode': 'total',
        'amount': 3000.0,
        'effective_hotel_day': '2025-06-03',
        'is_active': true,
        'reason': 'تخفيض',
        'applied_by': 'admin',
        'created_at': 7000,
        'last_modified': 7000,
      };

      final refs = await adapters.bookingPriceAdjustments.adapter.resolveRefs(
        db,
        json,
        src: Source.drive,
      );
      final comp = adapters.bookingPriceAdjustments.adapter.fromJson(
        json,
        src: Source.drive,
        refs: refs,
      );
      await db.into(db.bookingPriceAdjustments).insert(comp);

      final row = await db.select(db.bookingPriceAdjustments).getSingle();
      expect(row.localUuid, equals('adj-drive-1'));
      expect(row.amount, equals(3000.0));

      // toJson للـ Drive يعيد snake_case
      final out = adapters.bookingPriceAdjustments.toJsonForSource(
        row,
        src: Source.drive,
      );
      expect(out['local_uuid'], equals('adj-drive-1'));
      expect(out['booking_local_uuid'], equals(bookingUuid));
      expect(out['adjustment_type'], equals(0));
      expect(out['adjustment_mode'], equals('total'));
    });

    test('fromJson falls back to booking_uuid_cache when bookingLocalUuid missing', () async {
      final bookingUuid = 'booking-uuid-fallback';
      await db.into(db.bookings).insert(BookingsCompanion(
        localUuid: d.Value(bookingUuid),
        roomNumber: const d.Value('401'),
        guestName: const d.Value('خالد'),
        guestPhone: const d.Value('0500000003'),
        guestNationality: const d.Value('عماني'),
        checkinDate: const d.Value('2025-06-01'),
        status: const d.Value('checked_in'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      // بيانات بدون bookingLocalUuid ولكن مع booking_uuid_cache
      final json = {
        'localUuid': 'adj-fallback',
        'booking_uuid_cache': bookingUuid,
        'roomNumber': '401',
        'adjustmentType': 0,
        'adjustmentMode': 'per_night',
        'amount': 500.0,
        'effectiveHotelDay': '2025-06-05',
        'isActive': true,
        'reason': 'تخفيض بسيط',
        'appliedBy': 'admin',
        'createdAt': 8000,
        'lastModified': 8000,
      };

      final refs = await adapters.bookingPriceAdjustments.adapter.resolveRefs(
        db,
        json,
        src: Source.appwrite,
      );

      // يجب أن يحل bookingUuidCache المرجع
      expect(refs.bookingLocalId, isNotNull);
      expect(refs.bookingUuidCache, equals(bookingUuid));

      final comp = adapters.bookingPriceAdjustments.adapter.fromJson(
        json,
        src: Source.appwrite,
        refs: refs,
      );
      await db.into(db.bookingPriceAdjustments).insert(comp);

      final row = await db.select(db.bookingPriceAdjustments).getSingle();
      expect(row.amount, equals(500.0));
    });

    test('multiple adjustments for same booking', () async {
      final bookingUuid = 'booking-uuid-multi';
      await db.into(db.bookings).insert(BookingsCompanion(
        localUuid: d.Value(bookingUuid),
        roomNumber: const d.Value('501'),
        guestName: const d.Value('سامي'),
        guestPhone: const d.Value('0500000004'),
        guestNationality: const d.Value('يمني'),
        checkinDate: const d.Value('2025-06-01'),
        status: const d.Value('checked_in'),
        createdAt: const d.Value(1000),
        updatedAt: const d.Value(1000),
        lastModified: const d.Value(1000),
        createdAtEpoch: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
      ));

      // إدراج 3 تعديلات أسعار لنفس الحجز
      for (var i = 0; i < 3; i++) {
        final json = {
          'localUuid': 'adj-multi-$i',
          'bookingLocalUuid': bookingUuid,
          'roomNumber': '501',
          'adjustmentType': 0,
          'adjustmentMode': 'per_night',
          'amount': (1000 * (i + 1)).toDouble(),
          'effectiveHotelDay': '2025-06-${3 + i}',
          'isActive': true,
          'reason': 'تعديل $i',
          'appliedBy': 'admin',
          'createdAt': 9000 + i,
          'lastModified': 9000 + i,
        };

        final refs = await adapters.bookingPriceAdjustments.adapter.resolveRefs(
          db,
          json,
          src: Source.appwrite,
        );
        final comp = adapters.bookingPriceAdjustments.adapter.fromJson(
          json,
          src: Source.appwrite,
          refs: refs,
        );
        await db.into(db.bookingPriceAdjustments).insert(comp);
      }

      // التحقق: كل التعديلات أُدرجت
      final rows = await db.select(db.bookingPriceAdjustments).get();
      expect(rows.length, equals(3));

      // التحقق: كلها تشير لنفس الحجز
      for (final row in rows) {
        expect(row.bookingLocalUuid, equals(bookingUuid));
      }

      // التحقق: المبالغ مختلفة
      expect(rows[0].amount, equals(1000.0));
      expect(rows[1].amount, equals(2000.0));
      expect(rows[2].amount, equals(3000.0));
    });
  });
}
