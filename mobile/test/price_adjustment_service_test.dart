// ============================================================================
//  PriceAdjustmentService — Unit Tests
//  ============================================================================
//  اختبارات خدمة تعديل سعر الغرفة:
//    1. معاينة تغيير السعر (previewPriceChange) — لا تُعدّل البيانات
//    2. تطبيق تغيير السعر على حجز نشط — يُحدّث سعر الغرفة + outbox + audit
//    3. الحجوزات المغلقة لا تتأثر بتغيير السعر
//    4. الخصومات (discount) تُحسب بشكل صحيح في المعاينة
//
//  جميع التواريخ مبنية على DateTime.now() لضمان استقرار الاختبارات في CI.
//  لا نعتمد على تواريخ ثابتة hardcoded.
// ============================================================================

library marina_hotel_mobile.test.price_adjustment_service_test;

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/price_adjustment_service.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

/// Helper: ينشئ تاريخاً ديناميكياً مع إزاحة بعدد أيام محدد من اليوم.
DateTime _dayFromNow(int days, {int hour = 15, int minute = 0}) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days, hour, minute);
}

/// Helper: يحوّل DateTime إلى مفتاح يوم فندقي (YYYY-MM-DD).
String _hotelDayKey(DateTime dt) => Time.hotelDayKey(now: dt);

/// Helper: ينشئ تاريخ ISO مع فاصل مسافة بدلاً من T (متوافق مع التطبيق).
String _isoSpace(DateTime dt) => dt.toIso8601String().replaceFirst('T', ' ');

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

  group('معاينة تغيير السعر (previewPriceChange)', () {
    test('يجب أن تحسب الليالي المتأثرة بشكل صحيح', () async {
      // إنشاء غرفة بسعر 10000
      const roomUuid = 'room-101-uuid';
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: const Value(roomUuid),
              roomNumber: const Value('101'),
              type: const Value('عادية'),
              price: const Value(10000.0),
              status: const Value('محجوزة'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      // إنشاء حجز نشط (تاريخ دخول في الماضي)
      final checkinDate = _dayFromNow(-9, hour: 15);
      final bookingId = await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: const Value('booking-preview-uuid'),
              roomNumber: const Value('101'),
              guestName: const Value('أحمد محمد'),
              guestPhone: const Value('777123456'),
              guestNationality: const Value('يمني'),
              checkinDate: Value(_isoSpace(checkinDate)),
              status: const Value('مؤكد'),
              discount: const Value(0),
              discountType: const Value('per_night'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      // إدراج 10 ليالي بتواريخ ديناميكية: today-9 إلى today
      // الليالي الخمس الأولى (today-9 إلى today-5) قديمة
      // الليالي الخمس الأخيرة (today-4 إلى today) ستتأثر بالتغيير
      for (var i = 0; i < 10; i++) {
        final nightDate = _dayFromNow(-9 + i);
        final nightKey = _hotelDayKey(nightDate);
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value('night-preview-$i-uuid'),
                bookingLocalId: Value(bookingId),
                hotelDayKey: Value(nightKey),
                nightStart: Value('${nightKey}T14:01:00'),
                nightEnd: Value(
                  '${_hotelDayKey(nightDate.add(const Duration(days: 1)))}T14:01:00',
                ),
                nightlyRate: const Value(10000.0),
                baseRate: const Value(10000.0),
                adjustment: const Value(0.0),
                finalRate: const Value(10000.0),
                sequence: Value(i + 1),
                createdAt: Value(Time.nowEpoch()),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );
      }

      // تاريخ بداية التغيير: today-4 عند الساعة 14:01 (بداية يوم الفندق)
      final effectiveFrom = _dayFromNow(-4, hour: 14, minute: 1);

      final preview = await service.previewPriceChange(
        roomNumber: '101',
        newPrice: 12000.0,
        effectiveFrom: effectiveFrom,
      );

      // يجب أن تتأثر 5 ليالي (today-4, today-3, today-2, today-1, today)
      expect(preview['bookingsAffected'], 1);
      expect(preview['totalNightsAffected'], 5);
      expect(preview['totalOldAmount'], 50000.0);
      expect(preview['totalNewAmount'], 60000.0);
      expect(preview['totalDifference'], 10000.0);

      // المعاينة لا تُعدّل البيانات
      final nightsAfterPreview = await db.select(db.bookingNights).get();
      for (final night in nightsAfterPreview) {
        expect(night.nightlyRate, 10000.0);
      }
    });

    test('الخصم per_night يُطبّق في المعاينة بشكل صحيح', () async {
      const roomUuid = 'room-102-uuid';
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: const Value(roomUuid),
              roomNumber: const Value('102'),
              type: const Value('عادية'),
              price: const Value(10000.0),
              status: const Value('محجوزة'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      final checkinDate = _dayFromNow(-4, hour: 15);
      final bookingId = await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: const Value('booking-discount-preview-uuid'),
              roomNumber: const Value('102'),
              guestName: const Value('علي أحمد'),
              guestPhone: const Value('777999888'),
              guestNationality: const Value('يمني'),
              checkinDate: Value(_isoSpace(checkinDate)),
              status: const Value('مؤكد'),
              discount: const Value(2000),
              discountType: const Value('per_night'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      // 5 ليالي بسعر 8000 (بعد خصم 2000 من 10000)
      for (var i = 0; i < 5; i++) {
        final nightDate = _dayFromNow(-4 + i);
        final nightKey = _hotelDayKey(nightDate);
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value('night-discount-preview-$i-uuid'),
                bookingLocalId: Value(bookingId),
                hotelDayKey: Value(nightKey),
                nightStart: Value('${nightKey}T14:01:00'),
                nightEnd: Value(
                  '${_hotelDayKey(nightDate.add(const Duration(days: 1)))}T14:01:00',
                ),
                nightlyRate: const Value(8000.0),
                baseRate: const Value(10000.0),
                adjustment: const Value(-2000.0),
                finalRate: const Value(8000.0),
                sequence: Value(i + 1),
                createdAt: Value(Time.nowEpoch()),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );
      }

      // المعاينة: رفع السعر إلى 12000، الخصم 2000 → السعر الجديد 10000
      final effectiveFrom = _dayFromNow(-2, hour: 14, minute: 1);
      final preview = await service.previewPriceChange(
        roomNumber: '102',
        newPrice: 12000.0,
        effectiveFrom: effectiveFrom,
      );

      // 3 ليالي متأثرة (today-2, today-1, today)
      expect(preview['bookingsAffected'], 1);
      expect(preview['totalNightsAffected'], 3);
      // القديم: 3 × 8000 = 24000
      expect(preview['totalOldAmount'], 24000.0);
      // الجديد: 3 × (12000 - 2000) = 3 × 10000 = 30000
      expect(preview['totalNewAmount'], 30000.0);
      expect(preview['totalDifference'], 6000.0);
    });
  });

  group('تطبيق تغيير السعر (applyRoomPriceChange)', () {
    test('يُحدّث سعر الغرفة ويُنشئ outbox entries للحجز النشط', () async {
      const roomUuid = 'room-201-uuid';
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: const Value(roomUuid),
              roomNumber: const Value('201'),
              type: const Value('عادية'),
              price: const Value(10000.0),
              status: const Value('محجوزة'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      final checkinDate = _dayFromNow(-9, hour: 15);
      final bookingId = await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: const Value('booking-apply-uuid'),
              roomNumber: const Value('201'),
              guestName: const Value('سالم أحمد'),
              guestPhone: const Value('777555444'),
              guestNationality: const Value('يمني'),
              checkinDate: Value(_isoSpace(checkinDate)),
              status: const Value('مؤكد'),
              discount: const Value(0),
              discountType: const Value('per_night'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      // إدراج 10 ليالي بتواريخ ديناميكية
      for (var i = 0; i < 10; i++) {
        final nightDate = _dayFromNow(-9 + i);
        final nightKey = _hotelDayKey(nightDate);
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value('night-apply-$i-uuid'),
                bookingLocalId: Value(bookingId),
                hotelDayKey: Value(nightKey),
                nightStart: Value('${nightKey}T14:01:00'),
                nightEnd: Value(
                  '${_hotelDayKey(nightDate.add(const Duration(days: 1)))}T14:01:00',
                ),
                nightlyRate: const Value(10000.0),
                baseRate: const Value(10000.0),
                adjustment: const Value(0.0),
                finalRate: const Value(10000.0),
                sequence: Value(i + 1),
                createdAt: Value(Time.nowEpoch()),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );
      }

      final effectiveFrom = _dayFromNow(-4, hour: 14, minute: 1);

      final result = await service.applyRoomPriceChange(
        roomNumber: '201',
        oldPrice: 10000.0,
        newPrice: 12000.0,
        appliedBy: 'admin',
        reason: 'رفع السعر الموسمي',
        effectiveFrom: effectiveFrom,
      );

      expect(result.success, true);
      expect(result.bookingsAffected, 1);
      // 5 ليالي بتاريخ today-4 إلى today يجب أن تتأثر
      expect(result.nightsUpdated, 5);

      // التحقق من تحديث سعر الغرفة
      final updatedRoom = await (db.select(
        db.rooms,
      )..where((r) => r.roomNumber.equals('201'))).getSingle();
      expect(updatedRoom.price, 12000.0);

      // التحقق من وجود outbox entry لتحديث سعر الغرفة
      final outboxEntries = await db.select(db.outbox).get();
      expect(
        outboxEntries.any((e) => e.entity == 'rooms'),
        isTrue,
        reason: 'يجب إنشاء outbox entry لتحديث سعر الغرفة',
      );
      expect(
        outboxEntries.any((e) => e.entity == 'price_adjustments'),
        isTrue,
        reason: 'يجب إنشاء outbox entry لتسجيل تعديل السعر',
      );

      // التحقق من وجود سجل تعديل سعر
      final adjustments = await service.getAdjustmentsForRoom(roomUuid);
      expect(adjustments.length, 1);
      expect(adjustments.first.previousValue, 10000.0);
      expect(adjustments.first.newValue, 12000.0);
      expect(adjustments.first.reason, 'رفع السعر الموسمي');

      // سجل تدقيق مالي واحد مجمّع لكل حجز متأثر، ويتضمن عدد الليالي.
      final auditLogs = await db.select(db.auditLogs).get();
      expect(auditLogs.length, 1);
      expect(auditLogs.first.isFinancial, true);
      expect(auditLogs.first.newState, contains('5 ليلة'));
    });

    test('الحجوزات المغلقة (status=مغادر) لا تتأثر بتغيير السعر', () async {
      const roomUuid = 'room-202-uuid';
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: const Value(roomUuid),
              roomNumber: const Value('202'),
              type: const Value('عادية'),
              price: const Value(10000.0),
              status: const Value('شاغرة'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      // حجز مُغلق (actualCheckout موجود، status=مغادر)
      final checkinDate = _dayFromNow(-5, hour: 15);
      final checkoutDate = _dayFromNow(-1, hour: 11);
      final bookingId = await db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: const Value('booking-closed-uuid'),
              roomNumber: const Value('202'),
              guestName: const Value('محمد علي'),
              guestPhone: const Value('777111222'),
              guestNationality: const Value('يمني'),
              checkinDate: Value(_isoSpace(checkinDate)),
              actualCheckout: Value(_isoSpace(checkoutDate)),
              status: const Value('مغادر'),
              discount: const Value(0),
              discountType: const Value('per_night'),
              createdAt: Value(Time.nowEpoch()),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ),
          );

      // 4 ليالي
      for (var i = 0; i < 4; i++) {
        final nightDate = _dayFromNow(-5 + i);
        final nightKey = _hotelDayKey(nightDate);
        final nextNightKey = _hotelDayKey(
          nightDate.add(const Duration(days: 1)),
        );
        await db
            .into(db.bookingNights)
            .insert(
              BookingNightsCompanion(
                localUuid: Value('night-closed-$i-uuid'),
                bookingLocalId: Value(bookingId),
                hotelDayKey: Value(nightKey),
                nightlyRate: const Value(10000.0),
                nightStart: Value('${nightKey}T14:01:00'),
                nightEnd: Value('${nextNightKey}T12:00:00'),
                baseRate: const Value(10000.0),
                adjustment: const Value(0.0),
                finalRate: const Value(10000.0),
                sequence: Value(i + 1),
                createdAt: Value(Time.nowEpoch()),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );
      }

      final result = await service.applyRoomPriceChange(
        roomNumber: '202',
        oldPrice: 10000.0,
        newPrice: 15000.0,
        appliedBy: 'admin',
        effectiveFrom: _dayFromNow(-3, hour: 14, minute: 1),
      );

      expect(result.success, true);
      expect(result.bookingsAffected, 0);
      expect(result.nightsUpdated, 0);

      // سعر الغرفة يجب أن يُحدَّث على أي حال
      final updatedRoom = await (db.select(
        db.rooms,
      )..where((r) => r.roomNumber.equals('202'))).getSingle();
      expect(updatedRoom.price, 15000.0);

      // الليالي تبقى بسعرها القديم
      final nights = await (db.select(
        db.bookingNights,
      )..where((n) => n.bookingLocalId.equals(bookingId))).get();
      for (final night in nights) {
        expect(night.nightlyRate, 10000.0);
      }

      // لا توجد audit logs لأنه لا توجد ليالي متأثرة
      final auditLogs = await db.select(db.auditLogs).get();
      expect(auditLogs.length, 0);
    });

    test('يرفض التطبيق على غرفة غير موجودة', () async {
      final result = await service.applyRoomPriceChange(
        roomNumber: '999',
        oldPrice: 10000.0,
        newPrice: 15000.0,
        appliedBy: 'admin',
      );

      expect(result.success, false);
      expect(result.error, isNotNull);
      expect(result.error, contains('غير موجود'));
    });
  });

  group('استعلامات تعديلات الأسعار', () {
    test(
      'getAdjustmentsInDateRange يُرجع التعديلات في النطاق الصحيح',
      () async {
        const roomUuid = 'room-301-uuid';
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion(
                localUuid: const Value(roomUuid),
                roomNumber: const Value('301'),
                type: const Value('عادية'),
                price: const Value(10000.0),
                status: const Value('شاغرة'),
                createdAt: Value(Time.nowEpoch()),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ),
            );

        // إنشاء تعديلين بتواريخ مختلفة
        await service.applyRoomPriceChange(
          roomNumber: '301',
          oldPrice: 10000.0,
          newPrice: 11000.0,
          appliedBy: 'admin',
          reason: 'تعديل 1',
          effectiveFrom: _dayFromNow(-5, hour: 14, minute: 1),
        );

        await service.applyRoomPriceChange(
          roomNumber: '301',
          oldPrice: 11000.0,
          newPrice: 12000.0,
          appliedBy: 'admin',
          reason: 'تعديل 2',
          effectiveFrom: _dayFromNow(0, hour: 14, minute: 1),
        );

        // الاستعلام عن نطاق يشمل اليوم فقط
        final todayKey = _hotelDayKey(DateTime.now());
        final tomorrowKey = _hotelDayKey(_dayFromNow(1));
        final adjustments = await service.getAdjustmentsInDateRange(
          todayKey,
          tomorrowKey,
        );

        expect(adjustments.length, 1);
        expect(adjustments.first.reason, 'تعديل 2');
      },
    );
  });
}
