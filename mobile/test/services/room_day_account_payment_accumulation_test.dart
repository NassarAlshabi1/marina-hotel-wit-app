// ============================================================================
//  Marina Hotel — Room Day-Account Payment Accumulation
// ============================================================================
//  قاعدة العمل (2026-11-01) — «المجموع المدفوع يُحتسب ضمن حساب اليوم للغرفة»:
//
//  كل دفعة (جزئية أو فائضة) تدخل حساب الغرفة وتتراكم — لا تُهدر ولا تُهمل:
//
//    D1: دفعة جزئية (3000 من ليلة سعرها 15000): الليلة تُحتسب كاملة بالوقت
//        (حد 14:01) لا بحجم الدفعة، والدفعة تخفض المتبقي إلى 12000 وتبقى
//        رصيداً متراكماً نحو تغطية الليلة.
//    D2: الإجمالي المدفوع 18000 = 15000 (سعر الليلة) + 3000 زيادة: المبلغ
//        كله يدخل حساب اليوم للغرفة — ليلة مغطاة كاملة + رصيد 3000 نحو
//        الليلة التالية. التاريخ التلقائي المشتق من المدفوعات = الدخول +
//        ليلة، يُعرض ويُحسب ولا يُحفظ في checkout_date.
//    D3: التراكم: دفع 12000 إضافية لاحقاً (الإجمالي 30000) يغطي الليلة
//        الثانية كاملة — لا شيء من المدفوعات يضيع.
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/booking_derived_fields_service.dart';
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
  late RoomsRepository roomsRepo;

  // دخول أمس 15:00 (بعد حد 14:01) والآن اليوم 10:00 (قبل الحد):
  // nightsWithCutoff = floor(19h59m / 24h) + 1 = 1 ليلة مقضية.
  final today = DateTime.now();
  final checkin = DateTime(today.year, today.month, today.day - 1, 15);
  final now = DateTime(today.year, today.month, today.day, 10);

  Future<Booking> fetchBooking(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  Future<void> addPayment(int bookingId, double amount) async {
    await paymentsRepo.create(
      bookingLocalId: bookingId,
      roomNumber: '101',
      amount: amount,
      paymentDate: checkin.toIso8601String(),
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookingsRepo = BookingsRepository(db);
    paymentsRepo = PaymentsRepository(db);
    roomsRepo = RoomsRepository(db);

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

  /// حجز نشط مفتوح بلا تاريخ مغادرة مخطط — نموذج «النزيل بلا موعد» الذي
  /// يدفع يوماً بيوم (checkout_date = NULL اختياري).
  Future<int> seedActiveOpenBooking() async {
    return bookingsRepo.create(
      roomNumber: '101',
      guestName: 'نزيل بلا موعد مغادرة',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      status: 'نشط',
      expectedNights: 1,
    );
  }

  group('قاعدة العمل: المجموع المدفوع يُحتسب ضمن حساب اليوم للغرفة', () {
    test(
      'D1 — دفعة جزئية 3000 من ليلة بـ15000: الليلة كاملة والدفعة محسوبة',
      () async {
        final bookingId = await seedActiveOpenBooking();
        await addPayment(bookingId, 3000);

        // إعادة حساب الحقول المشتقة بساعة مثبتة (now) حتى لا يتأكد
        // الاختبار من توقيت الجهاز الحقيقي — نفس نمط الإنتاج.
        await BookingDerivedFieldsService(
          db,
        ).refreshForBookingId(bookingId, now: now);

        final booking = await fetchBooking(bookingId);
        expect(
          booking.checkoutDate,
          isNull,
          reason: 'لا تاريخ مغادرة مخطط — الحجز مفتوح',
        );

        final stay = StayBalanceCalculator.calculate(
          booking,
          roomRate: rate,
          now: now,
        );

        expect(
          stay.totalPaid,
          3000,
          reason: 'الدفعة الجزئية محسوبة ضمن حساب الغرفة',
        );
        expect(
          stay.actualNightsSpent,
          1,
          reason: 'الليلة تُحتسب بالوقت (حد 14:01) لا بحجم الدفعة',
        );
        expect(
          stay.consumedCost,
          15000,
          reason: 'حساب اليوم للغرفة = ليلة كاملة بسعرها',
        );
        expect(
          stay.effectiveBalance,
          -12000,
          reason: 'المتبقي على النزيل 12000 بعد الدفعة الجزئية',
        );
        expect(
          stay.totalPaidNights,
          0,
          reason: 'لم تكتمل تغطية أي ليلة بعد — 3000 أقل من 15000',
        );
        expect(
          stay.surplusAfterAllNights,
          3000,
          reason: 'الدفعة تبقى رصيداً متراكماً نحو تغطية الليلة — لا تضيع',
        );
        expect(booking.remainingBalanceCached, 12000);
      },
    );

    test(
      'D2 — الإجمالي 18000 (15000 + 3000 زيادة): ليلة كاملة + رصيد 3000',
      () async {
        final bookingId = await seedActiveOpenBooking();
        await addPayment(bookingId, 15000); // سعر الليلة
        await addPayment(bookingId, 3000); // دفعة زيادة فوق المتبقي

        final booking = await fetchBooking(bookingId);
        expect(
          booking.totalPaidCached,
          18000,
          reason: 'المجموع المدفوع 15000 + 3000 = 18000',
        );

        final stay = StayBalanceCalculator.calculate(
          booking,
          roomRate: rate,
          now: now,
        );

        expect(
          stay.totalPaid,
          18000,
          reason: 'المجموع كله يدخل حساب اليوم للغرفة',
        );
        expect(
          stay.totalPaidNights,
          1,
          reason: '18000 تغطي ليلة واحدة كاملة (15000)',
        );
        expect(
          stay.surplusAfterAllNights,
          3000,
          reason: 'الزيادة 3000 رصيد متراكم نحو الليلة التالية',
        );
        expect(
          stay.effectiveBalance,
          3000,
          reason: 'رصيد فعلي موجب 3000 لصالح النزيل',
        );
        expect(
          stay.autoCheckoutDate,
          DateTime(checkin.year, checkin.month, checkin.day + 1),
          reason: 'التاريخ التلقائي المشتق من المدفوعات = الدخول + ليلة',
        );

        // القاعدة المعمارية: التاريخ التلقائي يُعرض ويُحسب ولا يُحفظ.
        expect(
          booking.checkoutDate,
          isNull,
          reason: 'التاريخ التلقائي لا يُحفظ داخل checkout_date',
        );
      },
    );

    test(
      'D3 — التراكم: 12000 إضافية لاحقاً (الإجمالي 30000) تغطي ليلتين',
      () async {
        final bookingId = await seedActiveOpenBooking();
        await addPayment(bookingId, 15000);
        await addPayment(bookingId, 3000);
        await addPayment(bookingId, 12000); // الإجمالي 30000

        final booking = await fetchBooking(bookingId);
        expect(booking.totalPaidCached, 30000);

        final stay = StayBalanceCalculator.calculate(
          booking,
          roomRate: rate,
          now: now,
        );

        expect(
          stay.totalPaidNights,
          2,
          reason: 'تراكم المدفوعات: 30000 = ليلتان × 15000 — لا شيء يضيع',
        );
        expect(stay.surplusAfterAllNights, 0);
        expect(
          stay.autoCheckoutDate,
          DateTime(checkin.year, checkin.month, checkin.day + 2),
          reason: 'التغطية امتدت لليلتين بعد اكتمال المجموع',
        );
      },
    );
  });
}
