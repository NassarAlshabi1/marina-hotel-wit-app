// ============================================================================
//  Marina Hotel — Payment Surplus → Negotiated Night Rate (سقف 5000)
// ============================================================================
//  قاعدة العمل (2026-11-01) — «الوضع الآمن لا يتجاوز المبلغ عن 5000 كفائض»:
//
//  فائض الدفعة ضمن السقف (≤ 5000) يُمتص كتعديل سعر (سعر متفاوض عليه)
//  على آخر ليلة مسجلة، فيصبح سعر تلك الليلة = السعر الأساسي + الفائض:
//
//    A1: غرفة 15000 ودُفعت 18000 (فائض 3000) → الليلة تُسعَّر 18000
//        والمتبقي صفر — «يحتسب ضمن حساب اليوم للغرفة باعتبار أن سعر
//        الغرفة هو 18000».
//    A2: غرفة 15000 ودُفعت 20000 (فائض 5000 — سقف الأمان) → الليلة
//        تُسعَّر 20000.
//    A3: التعديل معمّر: إعادة تحديث الحقول المشتقة بعده لا تمسحه —
//        مصدر الحقيقة سجل booking_price_adjustments لا قيم صف الليلة.
//    A4: checkout_date لا يُولَّد ولا يُعدَّل من مسار الدفعة إطلاقاً،
//        والمحرك الموحد (StayBalanceCalculator) يرى السعر المتفاوض عليه.
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/booking_derived_fields_service.dart';
import 'package:marina_hotel_mobile/services/booking_price_adjustment_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/stay_balance_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const double rate = 15000; // سعر الليلة — مثال قاعدة العمل
  late AppDatabase db;
  late BookingsRepository bookingsRepo;
  late PaymentsRepository paymentsRepo;
  late BookingPriceAdjustmentService adjustmentService;
  late BookingDerivedFieldsService derivedService;

  // دخول «الآن» بالضبط: عدد الليالي المتكبدة = 1 دائماً ضمن اليوم نفسه
  // (بغض النظر عن تشغيل الاختبار قبل حد 14:01 أو بعده) لأن الفارق عن
  // بداية اليوم الفندقي أقل من 24 ساعة حتماً.
  final checkin = DateTime.now();

  Future<Booking> fetchBooking(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  Future<List<BookingNight>> fetchNights(int id) =>
      (db.select(db.bookingNights)
            ..where((n) => n.bookingLocalId.equals(id))
            ..where((n) => n.deletedAt.isNull())
            ..orderBy([(n) => OrderingTerm.asc(n.sequence)]))
          .get();

  /// حجز نشط مفتوح بلا تاريخ مغادرة مخطط — نموذج «النزيل بلا موعد»
  /// الذي يدفع (checkout_date = NULL اختياري).
  Future<Booking> seedActiveOpenBooking() async {
    final id = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'نزيل بلا موعد مغادرة',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      status: 'نشط',
      expectedNights: 1,
    );
    return fetchBooking(id);
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookingsRepo = BookingsRepository(db);
    paymentsRepo = PaymentsRepository(db);
    adjustmentService = BookingPriceAdjustmentService(db);
    derivedService = BookingDerivedFieldsService(db);

    PaymentSessionContext.start(userId: 1, userName: 'اختبار');

    await RoomsRepository(
      db,
    ).create(roomNumber: '101', type: 'عادية', price: rate, status: 'شاغرة');
  });

  tearDown(() async {
    PaymentSessionContext.clear();
    await db.close();
  });

  /// نفس تسلسل شاشة الدفع في المسار الجديد (دون طبقة الواجهة):
  /// تحديث مشتق → استهداف آخر ليلة → تسجيل surcharge → دفعة → تحديث مشتق.
  Future<({Booking booking, String targetDay, double surplus})>
  absorbSurplusAndPay(Booking booking, double paymentAmount) async {
    await derivedService.refreshForBookingId(booking.id);

    final nights = await fetchNights(booking.id);
    expect(nights, isNotEmpty, reason: 'ليالٍ متكبدة موجودة');
    final targetDay = nights.last.hotelDayKey;

    final before = await fetchBooking(booking.id);
    final surplus = paymentAmount - before.remainingBalanceCached;

    await adjustmentService.applyTemporaryAdjustment(
      bookingLocalUuid: booking.localUuid,
      amount: surplus.round(),
      type: AdjustmentType.surcharge,
      effectiveHotelDay: targetDay,
      endHotelDay: targetDay,
      reason: 'سعر متفاوض عليه — من فائض الدفعة',
      appliedBy: 'admin',
    );

    await paymentsRepo.create(
      bookingLocalId: booking.id,
      roomNumber: '101',
      amount: paymentAmount,
      paymentDate: checkin.toIso8601String(),
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );

    await derivedService.refreshForBookingId(booking.id);
    return (
      booking: await fetchBooking(booking.id),
      targetDay: targetDay,
      surplus: surplus,
    );
  }

  group('قاعدة العمل: فائض ≤ 5000 يُمتص كسعر متفاوض عليه لليلة', () {
    test(
      'A1 — غرفة 15000 ودُفعت 18000: الليلة تُسعَّر 18000 والمتبقي صفر',
      () async {
        final booking = await seedActiveOpenBooking();
        final result = await absorbSurplusAndPay(booking, 18000);

        expect(result.surplus, 3000, reason: 'الفائض = 18000 - 15000');
        expect(result.surplus, lessThanOrEqualTo(5000));

        final after = result.booking;
        expect(after.checkoutDate, isNull, reason: 'لا تاريخ مغادرة مخطط');
        expect(after.actualCheckout, isNull, reason: 'لا مغادرة فعلية');
        expect(
          after.totalDueCached,
          18000,
          reason: 'سعر الليلة أصبح 18000 — المجموع داخل حساب اليوم للغرفة',
        );
        expect(after.totalPaidCached, 18000);
        expect(after.remainingBalanceCached, 0);
        expect(after.isFullyPaid, isTrue);

        final nights = await fetchNights(booking.id);
        expect(nights, hasLength(1));
        final night = nights.single;
        expect(night.baseRate, 15000, reason: 'السعر الأساسي محفوظ');
        expect(night.adjustment, 3000, reason: 'الفائض ممتص كتعديل سعر');
        expect(night.finalRate, 18000);
        expect(night.nightlyRate, 18000);
      },
    );

    test(
      'A2 — غرفة 15000 ودُفعت 20000 (فائض 5000 — سقف الأمان): الليلة 20000',
      () async {
        final booking = await seedActiveOpenBooking();
        final result = await absorbSurplusAndPay(booking, 20000);

        expect(result.surplus, 5000, reason: 'الحد الأقصى للفائض الآمن');

        final after = result.booking;
        expect(after.totalDueCached, 20000);
        expect(after.totalPaidCached, 20000);
        expect(after.remainingBalanceCached, 0);
        expect(after.isFullyPaid, isTrue);
        expect(after.checkoutDate, isNull);

        final night = (await fetchNights(booking.id)).single;
        expect(night.adjustment, 5000);
        expect(night.finalRate, 20000);
        expect(night.baseRate, 15000);

        // سجل التعديل الكنسي نفسه — مصدر الحقيقة الذي تُعاد منه التسعيرة
        final adjustments = await adjustmentService.getActiveAdjustments(
          booking.localUuid,
        );
        expect(adjustments, hasLength(1));
        final adj = adjustments.single;
        expect(adj.adjustmentType, 1, reason: 'surcharge');
        expect(adj.amount, 5000);
        expect(adj.effectiveHotelDay, result.targetDay);
        expect(adj.endHotelDay, result.targetDay, reason: 'ليلة واحدة فقط');
        expect(adj.isActive, isTrue);
        expect(adj.roomNumber, '101');
      },
    );

    test(
      'A3 — التعديل معمّر: تحديث الحقول المشتقة بعده لا يمسح الفائض الممتص',
      () async {
        final booking = await seedActiveOpenBooking();
        final result = await absorbSurplusAndPay(booking, 18000);

        // محاكاة أي تحديث لاحق: مؤقت اليوم الفندقي، سحب مزامنة، فتح الشاشة
        await derivedService.refreshForBookingId(
          booking.id,
          forceRebuild: true,
        );
        await derivedService.refreshForBookingId(booking.id);

        final after = await fetchBooking(booking.id);
        expect(after.totalDueCached, 18000, reason: 'السعر المتفاوض باقٍ');
        expect(after.remainingBalanceCached, 0);
        expect(after.isFullyPaid, isTrue);

        final nights = await fetchNights(booking.id);
        final target = nights.firstWhere(
          (n) => n.hotelDayKey == result.targetDay,
        );
        expect(target.adjustment, 3000);
        expect(target.finalRate, 18000);
        expect(target.baseRate, 15000);
      },
    );

    test(
      'A4 — المحرك الموحد يرى السعر المتفاوض: ليلة مدفوعة واحدة بلا فائض',
      () async {
        final booking = await seedActiveOpenBooking();
        final result = await absorbSurplusAndPay(booking, 18000);

        final adjustments = await adjustmentService.getActiveAdjustments(
          booking.localUuid,
        );
        final stay = StayBalanceCalculator.calculate(
          result.booking,
          roomRate: rate,
          priceAdjustments: adjustments,
        );

        expect(stay.totalPaid, 18000);
        expect(
          stay.totalPaidNights,
          1,
          reason: '18000 تغطي الليلة بسعرها المتفاوض 18000',
        );
        expect(stay.surplusAfterAllNights, 0);
        expect(stay.consumedCost, 18000);
        expect(stay.effectiveBalance, 0);
        expect(
          stay.autoCheckoutDate,
          DateTime(checkin.year, checkin.month, checkin.day + 1),
          reason: 'التغطية المشتقة من المدفوعات = ليلة واحدة',
        );
      },
    );
  });
}
