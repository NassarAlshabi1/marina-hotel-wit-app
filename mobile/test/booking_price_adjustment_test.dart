// ============================================================================
//  BookingPriceAdjustmentService — Unit Tests
//  ============================================================================
//  اختبارات خدمة تعديلات سعر الحجز (discount/surcharge على ليالي محددة):
//    1. معاينة تخفيض مؤقت بأثر رجعي (previewAdjustment)
//    2. تطبيق تخفيض ومراجعة الليالي المتأثرة
//    3. إلغاء تخفيض (cancelAdjustment)
//    4. تقرير الإيرادات المفقودة (generateLostRevenueReport)
//    5. نقل التعديلات لغرفة جديدة (transferAdjustmentsToRoom)
//
//  جميع التواريخ مبنية على DateTime.now() لضمان استقرار الاختبارات في CI.
// ============================================================================

library marina_hotel_mobile.test.booking_price_adjustment_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/booking_price_adjustment_service.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:marina_hotel_mobile/utils/id.dart';

AppDatabase _createTestDb() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

/// Helper: ينشئ تاريخاً ديناميكياً مع إزاحة بعدد أيام محدد من اليوم.
DateTime _dayFromNow(int days, {int hour = 15}) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days, hour);
}

/// Helper: يحوّل DateTime إلى مفتاح يوم فندقي (YYYY-MM-DD).
String _hotelDayKey(DateTime dt) => Time.dateToString(dt);

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

  /// Helper: يُنشئ غرفة + حجز + N ليلة بتواريخ ديناميكية تبدأ من اليوم-9.
  Future<({Booking booking, String roomUuid, String bookingUuid})>
  seedBookingWithNights({
    required String roomNumber,
    required String roomUuid,
    required String bookingUuid,
    required String guestName,
    required int nightCount,
    required int nightlyRate,
    int roomPrice = 15000,
  }) async {
    final now = Time.nowEpoch();

    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion(
            localUuid: Value(roomUuid),
            roomNumber: Value(roomNumber),
            type: const Value('standard'),
            price: Value(roomPrice.toDouble()),
            status: const Value('occupied'),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ),
        );

    // تاريخ دخول في الماضي ليكون الحجز "نشطاً" ومحسوباً للفترة المعنية
    final checkinDate = _dayFromNow(-(nightCount - 1), hour: 15);
    await db
        .into(db.bookings)
        .insert(
          BookingsCompanion(
            localUuid: Value(bookingUuid),
            roomNumber: Value(roomNumber),
            guestName: Value(guestName),
            guestPhone: const Value('0500000000'),
            guestNationality: const Value('يمني'),
            checkinDate: Value(_hotelDayKey(checkinDate)),
            status: const Value('checked_in'),
            discount: const Value(0),
            discountType: const Value('nightly'),
            calculatedNights: Value(nightCount),
            expectedNights: Value(nightCount),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ),
        );

    final booking = await (db.select(
      db.bookings,
    )..where((b) => b.localUuid.equals(bookingUuid))).getSingle();

    // إدراج N ليلة بتواريخ ديناميكية متتالية
    for (var i = 0; i < nightCount; i++) {
      final nightDate = _dayFromNow(-(nightCount - 1) + i);
      final nightKey = _hotelDayKey(nightDate);
      await db
          .into(db.bookingNights)
          .insert(
            BookingNightsCompanion(
              localUuid: Value(IdGen.uuid()),
              bookingLocalId: Value(booking.id),
              hotelDayKey: Value(nightKey),
              nightStart: Value('${nightKey}T14:00:00'),
              nightEnd: Value(
                '${_hotelDayKey(nightDate.add(const Duration(days: 1)))}T12:00:00',
              ),
              nightlyRate: Value(nightlyRate.toDouble()),
              baseRate: Value(nightlyRate.toDouble()),
              adjustment: const Value(0),
              finalRate: Value(nightlyRate.toDouble()),
              sequence: Value(i + 1),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
    }

    return (booking: booking, roomUuid: roomUuid, bookingUuid: bookingUuid);
  }

  group('السيناريو 1: تخفيض مؤقت بأثر رجعي (preview + apply)', () {
    test('معاينة تخفيض 1000 ر.ي على 4 ليالي', () async {
      final seed = await seedBookingWithNights(
        roomNumber: '101',
        roomUuid: IdGen.uuid(),
        bookingUuid: IdGen.uuid(),
        guestName: 'أحمد محمد',
        nightCount: 7,
        nightlyRate: 15000,
      );

      // تطبيق تخفيض من اليوم-4 إلى اليوم-1 (4 ليالي)
      final effectiveDay = _hotelDayKey(_dayFromNow(-4));
      final endDay = _hotelDayKey(_dayFromNow(-1));

      final preview = await adjustmentService.previewAdjustment(
        bookingId: seed.booking.id,
        amount: 1000,
        type: AdjustmentType.discount,
        effectiveHotelDay: effectiveDay,
        endHotelDay: endDay,
      );

      expect(preview.originalTotal, equals(7 * 15000));
      expect(preview.nightsAffected, equals(4));
      expect(preview.difference, equals(-4000));
      expect(preview.adjustedTotal, equals(7 * 15000 - 4000));
    });

    test('تطبيق تخفيض 1000 ر.ي على 4 ليالي يُنشئ سجل تعديل نشط', () async {
      final seed = await seedBookingWithNights(
        roomNumber: '102',
        roomUuid: IdGen.uuid(),
        bookingUuid: IdGen.uuid(),
        guestName: 'سالم أحمد',
        nightCount: 7,
        nightlyRate: 15000,
      );

      final effectiveDay = _hotelDayKey(_dayFromNow(-4));
      final endDay = _hotelDayKey(_dayFromNow(-1));

      final adjustment = await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: seed.bookingUuid,
        amount: 1000,
        type: AdjustmentType.discount,
        effectiveHotelDay: effectiveDay,
        endHotelDay: endDay,
        reason: 'خصم خاص',
        appliedBy: 'المدير',
      );

      // التحقق من وجود سجل التعديل
      expect(adjustment.localUuid, isNotEmpty);
      expect(adjustment.isActive, isTrue);
      expect(adjustment.amount, equals(1000));

      // التحقق من وجوده في getActiveAdjustments
      final active = await adjustmentService.getActiveAdjustments(
        seed.bookingUuid,
      );
      expect(active.length, equals(1));
      expect(active.first.localUuid, equals(adjustment.localUuid));

      // التحقق من إنشاء outbox entry للمزامنة
      final outboxEntries = await db.select(db.outbox).get();
      expect(
        outboxEntries.any(
          (e) => e.entity == 'booking_price_adjustments' && e.op == 'create',
        ),
        isTrue,
        reason: 'يجب إنشاء outbox entry لتعديل السعر',
      );
    });
  });

  group('السيناريو 2: زيادة سعر (surcharge)', () {
    test(
      'تطبيق surcharge 3000 ر.ي يُسجَّل في تقرير الإيرادات الإضافية',
      () async {
        final seed = await seedBookingWithNights(
          roomNumber: '103',
          roomUuid: IdGen.uuid(),
          bookingUuid: IdGen.uuid(),
          guestName: 'خالد سعيد',
          nightCount: 10,
          nightlyRate: 15000,
        );

        final effectiveDay = _hotelDayKey(_dayFromNow(-3));

        await adjustmentService.applyTemporaryAdjustment(
          bookingLocalUuid: seed.bookingUuid,
          amount: 3000,
          type: AdjustmentType.surcharge,
          effectiveHotelDay: effectiveDay,
          reason: 'زيادة الشهر الثاني',
          appliedBy: 'المدير',
        );

        // surcharge بدون endHotelDay → ينطبق على جميع الليالي من effectiveDay فصاعداً
        // الليالي المتأثرة: today-3, today-2, today-1, today = 4 ليالي
        final report = await adjustmentService.generateLostRevenueReport();

        expect(report.totalGainedRevenue, equals(4 * 3000));
        expect(report.totalLostRevenue, equals(0));
        expect(report.bookingDetails.length, equals(1));
        expect(report.bookingDetails.first.adjustments.length, equals(1));
      },
    );
  });

  group('السيناريو 3: إلغاء تخفيض (cancelAdjustment)', () {
    test('إلغاء تخفيض مستقبلي يُعطّله بالكامل (isActive=false)', () async {
      final seed = await seedBookingWithNights(
        roomNumber: '104',
        roomUuid: IdGen.uuid(),
        bookingUuid: IdGen.uuid(),
        guestName: 'محمد علي',
        nightCount: 10,
        nightlyRate: 15000,
      );

      // تخفيض يبدأ من الغد (تاريخ مستقبلي)
      final futureDay = _hotelDayKey(_dayFromNow(1));

      final adjustment = await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: seed.bookingUuid,
        amount: 1000,
        type: AdjustmentType.discount,
        effectiveHotelDay: futureDay,
        reason: 'خصم مستقبلي',
        appliedBy: 'المدير',
      );

      // التحقق من أنه نشط قبل الإلغاء
      var active = await adjustmentService.getActiveAdjustments(
        seed.bookingUuid,
      );
      expect(active.length, equals(1));

      // إلغاء التعديل
      await adjustmentService.cancelAdjustment(
        adjustmentUuid: adjustment.localUuid,
        cancelledBy: 'المدير',
      );

      // بما أن effectiveHotelDay في المستقبل، يجب أن يُعطَّل بالكامل
      active = await adjustmentService.getActiveAdjustments(seed.bookingUuid);
      expect(
        active.isEmpty,
        isTrue,
        reason: 'التخفيض المستقبلي يجب أن يُعطَّل بالكامل عند الإلغاء',
      );

      // التحقق من وجود outbox entry للإلغاء
      final outboxEntries = await db.select(db.outbox).get();
      expect(
        outboxEntries.any(
          (e) => e.entity == 'booking_price_adjustments' && e.op == 'update',
        ),
        isTrue,
      );
    });

    test('إلغاء تخفيض سابق يقتصر على الليالي السابقة فقط', () async {
      final seed = await seedBookingWithNights(
        roomNumber: '105',
        roomUuid: IdGen.uuid(),
        bookingUuid: IdGen.uuid(),
        guestName: 'فاطمة علي',
        nightCount: 10,
        nightlyRate: 15000,
      );

      // تخفيض يبدأ من الأمس (في الماضي)
      final pastDay = _hotelDayKey(_dayFromNow(-1));

      final adjustment = await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: seed.bookingUuid,
        amount: 1000,
        type: AdjustmentType.discount,
        effectiveHotelDay: pastDay,
        reason: 'خصم ماضٍ',
        appliedBy: 'المدير',
      );

      await adjustmentService.cancelAdjustment(
        adjustmentUuid: adjustment.localUuid,
        cancelledBy: 'المدير',
      );

      // التخفيض يبقى نشطاً لكن مع endHotelDay = أمس
      final allAdjustments = await adjustmentService.getAllAdjustments(
        seed.bookingUuid,
      );
      expect(allAdjustments.length, equals(1));
      expect(
        allAdjustments.first.isActive,
        isTrue,
        reason: 'التخفيض السابق يبقى نشطاً لليالي الماضية',
      );
      expect(allAdjustments.first.endHotelDay, isNotNull);
      expect(allAdjustments.first.cancelledAt, isNotNull);
    });
  });

  group(
    'السيناريو 4: تقرير الإيرادات المفقودة (generateLostRevenueReport)',
    () {
      test('تقرير دقيق لتخفيض 5000 على 5 ليالي', () async {
        final seed = await seedBookingWithNights(
          roomNumber: '106',
          roomUuid: IdGen.uuid(),
          bookingUuid: IdGen.uuid(),
          guestName: 'نورا أحمد',
          nightCount: 10,
          nightlyRate: 20000,
          roomPrice: 20000,
        );

        final effectiveDay = _hotelDayKey(_dayFromNow(-4));
        final endDay = _hotelDayKey(_dayFromNow(0));

        await adjustmentService.applyTemporaryAdjustment(
          bookingLocalUuid: seed.bookingUuid,
          amount: 5000,
          type: AdjustmentType.discount,
          effectiveHotelDay: effectiveDay,
          endHotelDay: endDay,
          reason: 'خصم VIP',
          appliedBy: 'المدير',
        );

        final report = await adjustmentService.generateLostRevenueReport();

        // 5 ليالي متأثرة (today-4 إلى today)
        expect(report.totalLostRevenue, equals(5 * 5000));
        expect(report.totalGainedRevenue, equals(0));
        expect(report.bookingDetails.length, equals(1));
        expect(report.bookingDetails.first.adjustments.length, equals(1));
        expect(
          report.bookingDetails.first.adjustments.first.nightsAffected,
          equals(5),
        );
      });

      test('تقرير مع فلترة تاريخ', () async {
        final seed = await seedBookingWithNights(
          roomNumber: '107',
          roomUuid: IdGen.uuid(),
          bookingUuid: IdGen.uuid(),
          guestName: 'عمر خالد',
          nightCount: 5,
          nightlyRate: 10000,
          roomPrice: 10000,
        );

        // تعديل بتاريخ اليوم
        await adjustmentService.applyTemporaryAdjustment(
          bookingLocalUuid: seed.bookingUuid,
          amount: 1000,
          type: AdjustmentType.discount,
          effectiveHotelDay: _hotelDayKey(_dayFromNow(0)),
          reason: 'خصم اليوم',
          appliedBy: 'المدير',
        );

        // تقرير لنطاق يشمل اليوم
        final todayKey = _hotelDayKey(DateTime.now());
        final tomorrowKey = _hotelDayKey(_dayFromNow(1));
        final report = await adjustmentService.generateLostRevenueReport(
          fromHotelDay: todayKey,
          toHotelDay: tomorrowKey,
        );

        expect(report.bookingDetails.length, equals(1));

        // تقرير لنطاق لا يشمل اليوم (بعد غد)
        final afterTomorrowKey = _hotelDayKey(_dayFromNow(2));
        final nextWeekKey = _hotelDayKey(_dayFromNow(7));
        final emptyReport = await adjustmentService.generateLostRevenueReport(
          fromHotelDay: afterTomorrowKey,
          toHotelDay: nextWeekKey,
        );

        expect(emptyReport.bookingDetails.length, equals(0));
      });
    },
  );

  group('السيناريو 5: نقل التعديلات لغرفة جديدة', () {
    test(
      'transferAdjustmentsToRoom يُحدّث roomNumber لجميع التعديلات النشطة',
      () async {
        final seed = await seedBookingWithNights(
          roomNumber: '108',
          roomUuid: IdGen.uuid(),
          bookingUuid: IdGen.uuid(),
          guestName: 'سعيد محمد',
          nightCount: 5,
          nightlyRate: 12000,
          roomPrice: 12000,
        );

        // إنشاء تعديلين نشطين
        for (var i = 0; i < 2; i++) {
          await adjustmentService.applyTemporaryAdjustment(
            bookingLocalUuid: seed.bookingUuid,
            amount: 1000 + i * 500,
            type: AdjustmentType.discount,
            effectiveHotelDay: _hotelDayKey(_dayFromNow(-2 + i)),
            reason: 'خصم #$i',
            appliedBy: 'المدير',
          );
        }

        // نقل التعديلات لغرفة جديدة (مثلاً '108-A')
        await adjustmentService.transferAdjustmentsToRoom(
          bookingId: seed.booking.id,
          newRoomNumber: '108-A',
        );

        // التحقق من تحديث roomNumber في جميع التعديلات النشطة
        final activeAdjustments = await adjustmentService.getActiveAdjustments(
          seed.bookingUuid,
        );
        expect(activeAdjustments.length, equals(2));
        for (final adj in activeAdjustments) {
          expect(adj.roomNumber, equals('108-A'));
        }

        // التحقق من إنشاء outbox entries للتحديث
        final outboxEntries = await db.select(db.outbox).get();
        final updateEntries = outboxEntries.where(
          (e) => e.entity == 'booking_price_adjustments' && e.op == 'update',
        );
        expect(updateEntries.length, greaterThanOrEqualTo(2));
      },
    );
  });

  group('Whole Amount Tests', () {
    test('المبالغ العشرية تمثل قيماً بلا كسور عند الحاجة', () async {
      final seed = await seedBookingWithNights(
        roomNumber: '109',
        roomUuid: IdGen.uuid(),
        bookingUuid: IdGen.uuid(),
        guestName: 'عمر أحمد',
        nightCount: 5,
        nightlyRate: 15000,
      );

      final booking = await (db.select(
        db.bookings,
      )..where((b) => b.localUuid.equals(seed.bookingUuid))).getSingle();

      expect(booking.totalDueCached, isA<num>());
      expect(booking.discount, isA<double>());
      expect(booking.discount, 0.0);

      final room = await (db.select(
        db.rooms,
      )..where((r) => r.localUuid.equals(seed.roomUuid))).getSingle();

      expect(room.price, equals(15000));
    });
  });

  group('getLongStayBookingsWithoutSurcharge', () {
    test('يكتشف الحجوزات طويلة الأمد بدون surcharge', () async {
      // حجز طويل جداً (35 يوم) بدون surcharge
      final seed = await seedBookingWithNights(
        roomNumber: '110',
        roomUuid: IdGen.uuid(),
        bookingUuid: IdGen.uuid(),
        guestName: 'ضيف طويل الأمد',
        nightCount: 35,
        nightlyRate: 10000,
        roomPrice: 10000,
      );

      final longStays = await adjustmentService
          .getLongStayBookingsWithoutSurcharge(minimumNights: 30);

      expect(longStays.length, greaterThanOrEqualTo(1));
      expect(longStays.any((b) => b.id == seed.booking.id), isTrue);
    });

    test('لا يُرجع الحجوزات التي تحتوي surcharge نشط', () async {
      final seed = await seedBookingWithNights(
        roomNumber: '111',
        roomUuid: IdGen.uuid(),
        bookingUuid: IdGen.uuid(),
        guestName: 'ضيف مع surcharge',
        nightCount: 35,
        nightlyRate: 10000,
        roomPrice: 10000,
      );

      // إضافة surcharge نشط
      await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: seed.bookingUuid,
        amount: 2000,
        type: AdjustmentType.surcharge,
        effectiveHotelDay: _hotelDayKey(_dayFromNow(-10)),
        reason: 'زيادة الإقامة الطويلة',
        appliedBy: 'المدير',
      );

      final longStays = await adjustmentService
          .getLongStayBookingsWithoutSurcharge(minimumNights: 30);

      expect(
        longStays.any((b) => b.id == seed.booking.id),
        isFalse,
        reason: 'الحجز مع surcharge نشط يجب ألا يُرجع في الاستعلام',
      );
    });
  });

  group('watchActiveAdjustments', () {
    test('يبث التعديلات النشطة لحجز محدد', () async {
      final seed = await seedBookingWithNights(
        roomNumber: '112',
        roomUuid: IdGen.uuid(),
        bookingUuid: IdGen.uuid(),
        guestName: 'ضيف البث',
        nightCount: 5,
        nightlyRate: 10000,
        roomPrice: 10000,
      );

      final stream = adjustmentService.watchActiveAdjustments(seed.bookingUuid);

      // لا توجد تعديلات في البداية
      var firstEmission = await stream.first;
      expect(firstEmission, isEmpty);

      // إضافة تعديل
      await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: seed.bookingUuid,
        amount: 1000,
        type: AdjustmentType.discount,
        effectiveHotelDay: _hotelDayKey(_dayFromNow(0)),
        reason: 'خصم بث',
        appliedBy: 'المدير',
      );

      // التحقق من البث الجديد
      final secondEmission = await stream.first;
      expect(secondEmission.length, equals(1));
    });
  });
}
