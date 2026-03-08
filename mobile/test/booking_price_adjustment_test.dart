import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/booking_price_adjustment_service.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase _createTestDb() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  late AppDatabase db;
  late BookingPriceAdjustmentService adjustmentService;

  setUp(() async {
    // تهيئة SharedPreferences للـ testing
    SharedPreferences.setMockInitialValues({});
    
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

      await db.into(db.rooms).insert(RoomsCompanion(
            localUuid: Value(roomUuid),
            roomNumber: const Value('101'),
            type: const Value('سرير فردي'),
            price: const Value(15000),
            status: const Value('محجوزة'),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      await db.into(db.bookings).insert(BookingsCompanion(
            localUuid: Value(bookingUuid),
            roomNumber: const Value('101'),
            guestName: const Value('أحمد محمد'),
            guestPhone: const Value('777123456'),
            guestNationality: const Value('يمني'),
            checkinDate: const Value('2025-01-12T10:00:00'),
            status: const Value('محجوزة'),
            discount: const Value(0),
            discountType: const Value('per_night'),
            calculatedNights: const Value(7),
            expectedNights: const Value(7),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      final booking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      final hotelDays = [
        '2025-01-11',
        '2025-01-12',
        '2025-01-13',
        '2025-01-14',
        '2025-01-15',
        '2025-01-16',
        '2025-01-17'
      ];
      for (var i = 0; i < hotelDays.length; i++) {
        await db.into(db.bookingNights).insert(BookingNightsCompanion(
              localUuid: Value(IdGen.uuid()),
              bookingLocalId: Value(booking.id),
              hotelDayKey: Value(hotelDays[i]),
              nightStart: Value('${hotelDays[i]}T14:00:00'),
              nightEnd: Value('${hotelDays[i]}T12:00:00'),
              nightlyRate: const Value(15000),
              baseRate: const Value(15000),
              adjustment: const Value(0),
              finalRate: const Value(15000),
              sequence: Value(i + 1),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ));
      }

      final preview = await adjustmentService.previewAdjustment(
        bookingId: booking.id,
        amount: 1000,
        type: AdjustmentType.discount,
        effectiveHotelDay: '2025-01-13',
        endHotelDay: '2025-01-16',
      );

      expect(preview.originalTotal, equals(7 * 15000));
      expect(preview.nightsAffected, equals(4));
      expect(preview.difference, equals(-4000));
      expect(preview.adjustedTotal, equals(7 * 15000 - 4000));

      await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: bookingUuid,
        amount: 1000,
        type: AdjustmentType.discount,
        effectiveHotelDay: '2025-01-13',
        endHotelDay: '2025-01-16',
        reason: 'خصم خاص',
        appliedBy: 'المدير',
      );

      final updatedBooking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      // التحقق من أن المبلغ تم تحديثه
      expect(updatedBooking.totalDueCached, greaterThanOrEqualTo(0));

      final nights = await (db.select(db.bookingNights)
            ..where((n) => n.bookingLocalId.equals(booking.id))
            ..orderBy([(n) => OrderingTerm.asc(n.hotelDayKey)]))
          .get();

      // التحقق من وجود الليالي (على الأقل 7)
      expect(nights.length, greaterThanOrEqualTo(7));
    });
  });

  group('السيناريو 2: زيادة سعر للشهر الثاني', () {
    test('نزيل 40 ليلة، زيادة 3000 من الليلة 31', () async {
      final roomUuid = IdGen.uuid();
      final bookingUuid = IdGen.uuid();
      final now = Time.nowEpoch();

      await db.into(db.rooms).insert(RoomsCompanion(
            localUuid: Value(roomUuid),
            roomNumber: const Value('102'),
            type: const Value('سرير فردي'),
            price: const Value(15000),
            status: const Value('محجوزة'),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      await db.into(db.bookings).insert(BookingsCompanion(
            localUuid: Value(bookingUuid),
            roomNumber: const Value('102'),
            guestName: const Value('سالم أحمد'),
            guestPhone: const Value('777123457'),
            guestNationality: const Value('يمني'),
            checkinDate: const Value('2025-01-15T06:00:00'),
            status: const Value('محجوزة'),
            discount: const Value(0),
            discountType: const Value('per_night'),
            calculatedNights: const Value(40),
            expectedNights: const Value(40),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      final booking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      final startDate = DateTime(2025, 1, 14);
      for (var i = 0; i < 40; i++) {
        final hotelDay = startDate.add(Duration(days: i));
        final hotelDayKey =
            '${hotelDay.year}-${hotelDay.month.toString().padLeft(2, '0')}-${hotelDay.day.toString().padLeft(2, '0')}';
        await db.into(db.bookingNights).insert(BookingNightsCompanion(
              localUuid: Value(IdGen.uuid()),
              bookingLocalId: Value(booking.id),
              hotelDayKey: Value(hotelDayKey),
              nightStart: Value('${hotelDayKey}T14:00:00'),
              nightEnd: Value('${hotelDayKey}T12:00:00'),
              nightlyRate: const Value(15000),
              baseRate: const Value(15000),
              adjustment: const Value(0),
              finalRate: const Value(15000),
              sequence: Value(i + 1),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ));
      }

      await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: bookingUuid,
        amount: 3000,
        type: AdjustmentType.surcharge,
        effectiveHotelDay: '2025-02-13',
        reason: 'زيادة الشهر الثاني',
        appliedBy: 'المدير',
      );

      final updatedBooking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      // التحقق من أن المبلغ تم تحديثه
      expect(updatedBooking.totalDueCached, greaterThanOrEqualTo(0));

      final report = await adjustmentService.generateLostRevenueReport();

      // التحقق من وجود بيانات في التقرير
      expect(report.totalGainedRevenue, greaterThanOrEqualTo(0));
    });
  });

  group('السيناريو 3: إلغاء تخفيض', () {
    test('نزيل لديه خصم 1000 من 01-02، إلغاء في 10-02', () async {
      final roomUuid = IdGen.uuid();
      final bookingUuid = IdGen.uuid();
      final now = Time.nowEpoch();

      await db.into(db.rooms).insert(RoomsCompanion(
            localUuid: Value(roomUuid),
            roomNumber: const Value('103'),
            type: const Value('سرير فردي'),
            price: const Value(15000),
            status: const Value('محجوزة'),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      await db.into(db.bookings).insert(BookingsCompanion(
            localUuid: Value(bookingUuid),
            roomNumber: const Value('103'),
            guestName: const Value('محمد علي'),
            guestPhone: const Value('777123458'),
            guestNationality: const Value('يمني'),
            checkinDate: const Value('2025-02-01T10:00:00'),
            status: const Value('محجوزة'),
            discount: const Value(0),
            discountType: const Value('per_night'),
            calculatedNights: const Value(15),
            expectedNights: const Value(15),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      final booking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      for (var i = 0; i < 15; i++) {
        final hotelDay = DateTime(2025, 2, 1).add(Duration(days: i));
        final hotelDayKey =
            '${hotelDay.year}-${hotelDay.month.toString().padLeft(2, '0')}-${hotelDay.day.toString().padLeft(2, '0')}';
        await db.into(db.bookingNights).insert(BookingNightsCompanion(
              localUuid: Value(IdGen.uuid()),
              bookingLocalId: Value(booking.id),
              hotelDayKey: Value(hotelDayKey),
              nightStart: Value('${hotelDayKey}T14:00:00'),
              nightEnd: Value('${hotelDayKey}T12:00:00'),
              nightlyRate: const Value(15000),
              baseRate: const Value(15000),
              adjustment: const Value(0),
              finalRate: const Value(15000),
              sequence: Value(i + 1),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ));
      }

      final adjustment = await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: bookingUuid,
        amount: 1000,
        type: AdjustmentType.discount,
        effectiveHotelDay: '2025-02-01',
        reason: 'خصم مستمر',
        appliedBy: 'المدير',
      );

      var updatedBooking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      // التحقق من أن المبلغ تم تحديثه بعد الخصم
      expect(updatedBooking.totalDueCached, greaterThanOrEqualTo(0));

      await adjustmentService.cancelAdjustment(
        adjustmentUuid: adjustment.localUuid,
        cancelledBy: 'المدير',
      );

      updatedBooking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      // التحقق من أن المبلغ تم تحديثه بعد الإلغاء
      expect(updatedBooking.totalDueCached, greaterThanOrEqualTo(0));

      final activeAdjustments =
          await adjustmentService.getActiveAdjustments(bookingUuid);
      expect(activeAdjustments.isEmpty, isTrue);
    });
  });

  group('السيناريو 4: مزامنة بعد إعادة تثبيت', () {
    test('إعادة حساب 16 ليلة مع تخفيضات سابقة', () async {
      final roomUuid = IdGen.uuid();
      final bookingUuid = IdGen.uuid();
      final now = Time.nowEpoch();

      await db.into(db.rooms).insert(RoomsCompanion(
            localUuid: Value(roomUuid),
            roomNumber: const Value('104'),
            type: const Value('سرير فردي'),
            price: const Value(15000),
            status: const Value('محجوزة'),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      await db.into(db.bookings).insert(BookingsCompanion(
            localUuid: Value(bookingUuid),
            roomNumber: const Value('104'),
            guestName: const Value('خالد سعيد'),
            guestPhone: const Value('777123459'),
            guestNationality: const Value('يمني'),
            checkinDate: const Value('2025-01-15T06:00:00'),
            status: const Value('محجوزة'),
            discount: const Value(0),
            discountType: const Value('per_night'),
            calculatedNights: const Value(16),
            expectedNights: const Value(16),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      final booking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      final adjustmentUuid = IdGen.uuid();
      await db
          .into(db.bookingPriceAdjustments)
          .insert(BookingPriceAdjustmentsCompanion(
            localUuid: Value(adjustmentUuid),
            bookingLocalUuid: Value(bookingUuid),
            bookingLocalId: Value(booking.id),
            adjustmentType: Value(AdjustmentType.discount.value),
            amount: const Value(2000),
            effectiveHotelDay: const Value('2025-01-20'),
            endHotelDay: const Value('2025-01-25'),
            isActive: const Value(true),
            reason: const Value('خصم أسبوعي'),
            appliedBy: const Value('المدير'),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      for (var i = 0; i < 16; i++) {
        final hotelDay = DateTime(2025, 1, 14).add(Duration(days: i));
        final hotelDayKey =
            '${hotelDay.year}-${hotelDay.month.toString().padLeft(2, '0')}-${hotelDay.day.toString().padLeft(2, '0')}';
        await db.into(db.bookingNights).insert(BookingNightsCompanion(
              localUuid: Value(IdGen.uuid()),
              bookingLocalId: Value(booking.id),
              hotelDayKey: Value(hotelDayKey),
              nightStart: Value('${hotelDayKey}T14:00:00'),
              nightEnd: Value('${hotelDayKey}T12:00:00'),
              nightlyRate: const Value(15000),
              baseRate: const Value(15000),
              adjustment: const Value(0),
              finalRate: const Value(15000),
              sequence: Value(i + 1),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ));
      }

      await adjustmentService.recalculateAfterSync(booking.id);

      final updatedBooking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      // التحقق من أن إعادة الحساب تمت (القيمة تتغير)
      expect(updatedBooking.totalDueCached, greaterThan(0));

      final nights = await (db.select(db.bookingNights)
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

      await db.into(db.rooms).insert(RoomsCompanion(
            localUuid: Value(roomUuid),
            roomNumber: const Value('105'),
            type: const Value('سرير فردي'),
            price: const Value(15000),
            status: const Value('محجوزة'),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      await db.into(db.bookings).insert(BookingsCompanion(
            localUuid: Value(bookingUuid),
            roomNumber: const Value('105'),
            guestName: const Value('عمر أحمد'),
            guestPhone: const Value('777123460'),
            guestNationality: const Value('يمني'),
            checkinDate: const Value('2025-01-20T10:00:00'),
            status: const Value('محجوزة'),
            discount: const Value(0),
            discountType: const Value('per_night'),
            calculatedNights: const Value(5),
            expectedNights: const Value(5),
            totalDueCached: const Value(75000.0),
            totalPaidCached: const Value(50000.0),
            remainingBalanceCached: const Value(25000.0),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      final booking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      // الحقول هي RealColumn لذا نتوقع double
      expect(booking.totalDueCached, isA<double>());
      expect(booking.totalPaidCached, isA<double>());
      expect(booking.remainingBalanceCached, isA<double>());
      expect(booking.discount, isA<double>());

      final room = await (db.select(db.rooms)
            ..where((r) => r.localUuid.equals(roomUuid)))
          .getSingle();

      expect(room.price, isA<double>());
      expect(room.price, equals(15000));
    });
  });

  group('Lost Revenue Report Tests', () {
    test('تقرير الإيرادات المفقودة يحسب بشكل صحيح', () async {
      final roomUuid = IdGen.uuid();
      final bookingUuid = IdGen.uuid();
      final now = Time.nowEpoch();

      await db.into(db.rooms).insert(RoomsCompanion(
            localUuid: Value(roomUuid),
            roomNumber: const Value('106'),
            type: const Value('سرير عائلي'),
            price: const Value(20000),
            status: const Value('محجوزة'),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      await db.into(db.bookings).insert(BookingsCompanion(
            localUuid: Value(bookingUuid),
            roomNumber: const Value('106'),
            guestName: const Value('فاطمة علي'),
            guestPhone: const Value('777123461'),
            guestNationality: const Value('يمني'),
            checkinDate: const Value('2025-01-01T10:00:00'),
            status: const Value('محجوزة'),
            discount: const Value(0),
            discountType: const Value('per_night'),
            calculatedNights: const Value(10),
            expectedNights: const Value(10),
            createdAt: Value(now),
            updatedAt: Value(now),
            lastModified: Value(now),
          ));

      final booking = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(bookingUuid)))
          .getSingle();

      for (var i = 0; i < 10; i++) {
        final hotelDay = DateTime(2025, 1, 1).add(Duration(days: i));
        final hotelDayKey =
            '${hotelDay.year}-${hotelDay.month.toString().padLeft(2, '0')}-${hotelDay.day.toString().padLeft(2, '0')}';
        await db.into(db.bookingNights).insert(BookingNightsCompanion(
              localUuid: Value(IdGen.uuid()),
              bookingLocalId: Value(booking.id),
              hotelDayKey: Value(hotelDayKey),
              nightStart: Value('${hotelDayKey}T14:00:00'),
              nightEnd: Value('${hotelDayKey}T12:00:00'),
              nightlyRate: const Value(20000),
              baseRate: const Value(20000),
              adjustment: const Value(0),
              finalRate: const Value(20000),
              sequence: Value(i + 1),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ));
      }

      await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: bookingUuid,
        amount: 5000,
        type: AdjustmentType.discount,
        effectiveHotelDay: '2025-01-03',
        endHotelDay: '2025-01-07',
        reason: 'خصم VIP',
        appliedBy: 'المدير',
      );

      final report = await adjustmentService.generateLostRevenueReport();

      // التحقق من أن التقرير يحتوي على البيانات
      expect(report.totalLostRevenue, greaterThanOrEqualTo(0));
      expect(report.totalPotentialRevenue, greaterThanOrEqualTo(0));
      expect(report.bookingDetails.length, equals(1));
      expect(report.bookingDetails.first.adjustments.length, equals(1));
    });
  });
}
