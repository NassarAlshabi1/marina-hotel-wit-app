// ============================================================================
//  Marina Hotel — Payment Actual Balance Verification (production-path audit)
// ============================================================================
//  يتحقق من قاعدة «الرصيد الفعلي» الموحدة عبر طبقات الإنتاج الحقيقية
//  (PaymentsRepository / BookingDerivedFieldsService /
//  EnhancedBookingCalculationService / BookingComputedStreamService /
//  GuestPaymentCalculationService / StayBalanceCalculator) — لا mock.
//
//  القاعدة المدروسة (المطلب): عند إضافة دفعة — ومنها «رصيد تراكمي للنزيل» —
//  يُحتسب الرصيد الفعلي من كل الأموال الفعلية المرتبطة بالحجز:
//
//    B1: العرابون (deposit — مسار booking_edit) يُحتسب في الرصيد الفعلي.
//    B2: دفعة خدمة (service — مسار booking_checkout_screen) تُحتسب.
//    B3: دفعة «رصيد تراكمي» (room — مسار زر شاشة معالجة المدفوعات) تُحتسب.
//    B4: دفعة مرتبطة بـ UUID فقط (سحب مزامنة بلا bookingLocalId) تُحتسب.
//    B5: الدفعة المعلّقة (isPendingBalance) لا تُحتسب حتى تُعالج.
//    B6: الدفعة الملغاة (voided — مسار PaymentVoidService) تُستبعد فوراً
//        وتُحدَّث الخزائن داخل نفس المعاملة.
//    B7: الاتساق المتقاطع: المحرك == SQL قائمة الحجوزات == ComputedStream ==
//        GuestPaymentCalculation == StayBalanceCalculator == الخزائن المخبأة.
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/booking_computed_stream_service.dart';
import 'package:marina_hotel_mobile/services/booking_derived_fields_service.dart';
import 'package:marina_hotel_mobile/services/guest_payment_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/payment_void_service.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/stay_balance_calculator.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const double rate = 100.0; // سعر الليلة
  late AppDatabase db;
  late BookingsRepository bookingsRepo;
  late PaymentsRepository paymentsRepo;
  late RoomsRepository roomsRepo;
  late PaymentVoidService voidService;

  // ─── خط زمني حتمي في الماضي العميق (مستقل عن ساعة الجهاز) ───
  // حجز مكتمل: دخول d-4@15:00 (بعد حد 14:01) → مغادرة d-1@15:00
  // nightsWithCutoff = floor((d-1@15:00 − d-4@14:01)/24h) + 1 = 4 ليالٍ.
  // totalDue = 4 × 100 = 400.
  final today = DateTime.now();
  DateTime day(int daysBack, [int hour = 15, int minute = 0]) =>
      DateTime(today.year, today.month, today.day - daysBack, hour, minute);

  final checkin = day(4);
  final actualCheckout = day(1);

  Future<Booking> fetchBooking(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  /// إدراج دفعة كما تصل من السحب: مرتبطة بـ UUID فقط بلا bookingLocalId.
  Future<void> insertUuidOnlyPayment(
    String bookingUuid,
    double amount,
    String revenueType,
  ) async {
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            localUuid: 'pay-uuid-only-$nowEpoch-${amount.round()}',
            createdAt: nowEpoch,
            updatedAt: nowEpoch,
            lastModified: nowEpoch,
            amount: amount,
            paymentDate: Time.nowIso(),
            paymentMethod: 'نقدي',
            revenueType: revenueType,
            bookingUuidCache: d.Value(bookingUuid),
            roomNumber: const d.Value('101'),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookingsRepo = BookingsRepository(db);
    paymentsRepo = PaymentsRepository(db);
    roomsRepo = RoomsRepository(db);
    voidService = PaymentVoidService(db);

    PaymentSessionContext.start(userId: 1, userName: 'اختبار');

    await roomsRepo.create(
      roomNumber: '101',
      type: 'عادية',
      price: rate,
      status: 'شاغرة',
    );
  });

  tearDown(() async {
    PaymentSessionContext.clear();
    await db.close();
  });

  /// حجز مكتمل 4 ليالٍ × 100 = 400 إجمالي (ليالي مثبتة لا تتغير مع الوقت).
  Future<int> seedCompletedBooking() async {
    final id = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'سالم ناصر',
      guestPhone: '0509876543',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      checkoutDate: day(1, 12).toIso8601String(),
      status: 'نشط',
      expectedNights: 4,
    );
    await bookingsRepo.update(
      id,
      status: 'مكتمل',
      actualCheckout: actualCheckout.toIso8601String(),
      calculatedNights: 4,
    );
    return id;
  }

  group('B1+B2+B3 — الرصيد الفعلي يضم العرابون والخدمة والرصيد التراكمي', () {
    test(
      'deposit/service/room كلها تُخصم من المتبقي عبر المحرك الموحد',
      () async {
        final bookingId = await seedCompletedBooking();

        // العرابون — مسار شاشة تعديل الحجز (booking_edit).
        await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: 100,
          paymentDate: checkin.toIso8601String(),
          paymentMethod: 'نقدي',
          revenueType: 'deposit',
        );

        // خدمات إضافية — مسار شاشة الدفع عند المغادرة.
        await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: 50,
          paymentDate: checkin.toIso8601String(),
          paymentMethod: 'نقدي',
          revenueType: 'service',
        );

        // رصيد تراكمي — مسار زر شاشة معالجة المدفوعات (post-dda160ee).
        await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: 200,
          paymentDate: checkin.toIso8601String(),
          paymentMethod: 'نقدي',
          revenueType: 'room',
        );

        final booking = await fetchBooking(bookingId);
        expect(
          booking.totalDueCached,
          400,
          reason: 'إجمالي الاستحقاق: 4 ليالٍ × 100',
        );
        expect(
          booking.totalPaidCached,
          350,
          reason:
              'الرصيد الفعلي = 100 (عرابون) + 50 (خدمة) + 200 (رصيد تراكمي)',
        );
        expect(
          booking.remainingBalanceCached,
          50,
          reason: 'المتبقي = 400 − 350',
        );
        expect(booking.isFullyPaid, false);
      },
    );
  });

  group('B4 — الدفعة المرتبطة بـ UUID فقط (سيناريو السحب) تُحتسب', () {
    test(
      'المحرك يطابق الدفعات بـ bookingLocalId أو bookingUuidCache',
      () async {
        final bookingId = await seedCompletedBooking();
        final booking = await fetchBooking(bookingId);

        await insertUuidOnlyPayment(booking.localUuid, 400, 'room');

        await BookingDerivedFieldsService(db).refreshForBookingId(bookingId);
        final after = await fetchBooking(bookingId);

        expect(
          after.totalPaidCached,
          400,
          reason: 'دفعة مزامنة بلا bookingLocalId يجب أن تُحتسب عبر uuid',
        );
        expect(after.remainingBalanceCached, 0);
        expect(after.isFullyPaid, true);
      },
    );
  });

  group('B5 — الدفعة المعلّقة (isPendingBalance) لا تُحتسب', () {
    test('الرصيد الفعلي يستثني المعلّقة حتى تُعالج', () async {
      final bookingId = await seedCompletedBooking();

      // دفعة معلّقة (غير مُطابقة) — كما تصل من مزامنة قديمة.
      await paymentsRepo.create(
        bookingLocalId: bookingId,
        roomNumber: '101',
        amount: 250,
        paymentDate: checkin.toIso8601String(),
        paymentMethod: 'نقدي',
        revenueType: 'room',
        isPendingBalance: true,
      );

      final booking = await fetchBooking(bookingId);
      expect(
        booking.totalPaidCached,
        0,
        reason: 'المعلّقة لا تدخل الرصيد الفعلي',
      );
      expect(booking.remainingBalanceCached, 400);

      // معالجة الأرصدة المعلّقة (مسار settings_maintenance): تحويلها لفعلية.
      await paymentsRepo.update(
        (await paymentsRepo.paymentsByBooking(bookingId).first).first.id,
        isPendingBalance: false,
        revenueType: 'room',
      );

      final processed = await fetchBooking(bookingId);
      expect(processed.totalPaidCached, 250);
      expect(processed.remainingBalanceCached, 150);
    });
  });

  group('B6 — الإلغاء (void) يُستبعد فوراً ويُحدّث الخزائن ذرّياً', () {
    test('PaymentVoidService يطرح المبلغ الملغى من الرصيد الفعلي', () async {
      final bookingId = await seedCompletedBooking();

      final roomPayId = await paymentsRepo.create(
        bookingLocalId: bookingId,
        roomNumber: '101',
        amount: 300,
        paymentDate: checkin.toIso8601String(),
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      final servicePayId = await paymentsRepo.create(
        bookingLocalId: bookingId,
        roomNumber: '101',
        amount: 100,
        paymentDate: checkin.toIso8601String(),
        paymentMethod: 'نقدي',
        revenueType: 'service',
      );

      var booking = await fetchBooking(bookingId);
      expect(booking.totalPaidCached, 400);
      expect(booking.isFullyPaid, true);

      // إلغاء دفعة الخدمة (مسار الإلغاء الإنتاجي بالكامل).
      final servicePayment = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(servicePayId))).getSingle();
      final ok = await voidService.voidPayment(
        paymentUuid: servicePayment.localUuid,
        voidReason: 'اختبار: استبعاد الملغاة من الرصيد الفعلي',
        voidedBy: 'اختبار',
      );
      expect(ok, true, reason: 'مسار الإلغاء يجب أن ينجح');

      // الخزائن محدثة داخل نفس معاملة الإلغاء — بلا تحديث يدوي لاحق.
      booking = await fetchBooking(bookingId);
      expect(
        booking.totalPaidCached,
        300,
        reason: 'الرصيد الفعلي بعد الإلغاء = دفعة الغرفة فقط',
      );
      expect(booking.remainingBalanceCached, 100);
      expect(booking.isFullyPaid, false);

      // الإلغاء idempotent: تكرار الإلغاء يرفض ولا يخصم مرتين.
      final again = await voidService.voidPayment(
        paymentUuid: servicePayment.localUuid,
        voidReason: 'تكرار',
        voidedBy: 'اختبار',
      );
      expect(again, false);
      booking = await fetchBooking(bookingId);
      expect(booking.totalPaidCached, 300);

      // الدفعة الفعلية الباقية ما زالت محسوبة.
      final roomPayment = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(roomPayId))).getSingle();
      expect(roomPayment.isVoided, false);
    });
  });

  group('B7 — الاتساق المتقاطع بين كل مستهلكي الرصيد', () {
    test(
      'المحرك == SQL القائمة == ComputedStream == GuestCalc == StayBalance',
      () async {
        final bookingId = await seedCompletedBooking();

        await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: 100,
          paymentDate: checkin.toIso8601String(),
          paymentMethod: 'نقدي',
          revenueType: 'deposit',
        );
        await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: 250,
          paymentDate: checkin.toIso8601String(),
          paymentMethod: 'نقدي',
          revenueType: 'room',
        );
        // معلّقة + ملغاة: لا تدخلان في أي حساب.
        final voidMeId = await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: 999,
          paymentDate: checkin.toIso8601String(),
          paymentMethod: 'نقدي',
          revenueType: 'room',
        );
        await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: 777,
          paymentDate: checkin.toIso8601String(),
          paymentMethod: 'نقدي',
          revenueType: 'room',
          isPendingBalance: true,
        );
        final voidMe = await (db.select(
          db.payments,
        )..where((p) => p.id.equals(voidMeId))).getSingle();
        await voidService.voidPayment(
          paymentUuid: voidMe.localUuid,
          voidReason: 'اختبار الاتساق',
          voidedBy: 'اختبار',
        );

        const int expectedPaid = 350; // 100 + 250 فقط
        final booking = await fetchBooking(bookingId);

        // ① الخزائن المخبأة (المحرك الموحد).
        expect(booking.totalPaidCached, expectedPaid);

        // ② SQL قائمة الحجوزات (bookingPaidAmountProvider).
        final sqlPaid = await paymentsRepo
            .watchTotalPaidForBooking(bookingId)
            .first;
        expect(sqlPaid, expectedPaid.toDouble());

        // ③ BookingComputedStreamService (شبكة الغرف/اللوحة).
        final computed = await BookingComputedStreamService(
          db,
        ).buildBookingWithPayments(bookingId);
        expect(computed, isNotNull);
        expect(computed!.totalPaid, expectedPaid);
        expect(computed.remainingBalance, 400 - expectedPaid);

        // ④ GuestPaymentCalculationService (كشف حساب النزيل).
        final guestCalc = await GuestPaymentCalculationService(
          db,
        ).calculateForBooking(booking);
        expect(guestCalc.totalPaid, expectedPaid.toDouble());
        expect(guestCalc.remainingBalance, (400 - expectedPaid).toDouble());

        // ⑤ StayBalanceCalculator (المغادرة التلقائية/الليالي المدفوعة).
        final stay = StayBalanceCalculator.calculate(booking, roomRate: rate);
        expect(stay.totalPaid, expectedPaid.toDouble());
        expect(stay.totalPaidNights, 3, reason: '350 يغطي 3 ليالٍ × 100');
      },
    );
  });
}
