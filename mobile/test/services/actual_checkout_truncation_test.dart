// ============================================================================
//  Marina Hotel — Actual-Checkout Truncation (production-path review tests)
// ============================================================================
//  اختبارات مراجعة الالتزام 50a0958b «fix: calculate active stays until
//  actual checkout» عبر مسارات الإنتاج الحقيقية (لا mock):
//
//    T1: actualCheckout المسجّل (في الماضي) يقطع تراكم الليالي — الحساب
//        لا يمتد إلى «الآن» ولا يوقفه plannedCheckout المخطط.
//    T2: بعد تسجيل actualCheckout تبقى القيم الفعلية ثابتة مهما تقدّم
//        «الآن» (actualNightsSpent / consumedCost / effectiveBalance).
//    T3: بلا actualCheckout: الحساب يستمر حتى «الآن» حتى لو مضى
//        plannedCheckout — الحجز النشط يتراكم ديناميكياً.
//    T4: حدّ اليوم الفندقي بالثانية: 14:00:59 (لا ليلة إضافية)
//        مقابل 14:01:00 (ليلة إضافية) — عبر المحرك والمسار الافتراضي.
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/enhanced_booking_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/stay_balance_calculator.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const double rate = 100.0; // سعر الليلة

  late AppDatabase db;
  late BookingsRepository bookingsRepo;
  late PaymentsRepository paymentsRepo;
  late EnhancedBookingCalculationService calculator;

  // ─── خط زمني حتمي ثابت (مستقل تماماً عن ساعة الجهاز) ───
  // دخول 2024-03-01 15:00 (بعد حد 14:01) → بداية يوم الفندق 03-01 14:01.
  // plannedCheckout = 2024-03-02 14:00 → ليلتان مخططتان فقط.
  // actualCheckout  = 2024-03-04 10:00 → 3 ليالٍ فعلية محسومة.
  // الآن (A/B/C)    = 2024-03-10 15:00 / 03-20 09:00 / 04-05 12:00.
  final checkin = DateTime(2024, 3, 1, 15);
  final plannedCheckout = DateTime(2024, 3, 2, 14);
  final actualCheckout = DateTime(2024, 3, 4, 10);
  final nowA = DateTime(2024, 3, 10, 15);
  final nowB = DateTime(2024, 3, 20, 9);
  final nowC = DateTime(2024, 4, 5, 12);

  Future<Booking> fetchBooking(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookingsRepo = BookingsRepository(db);
    paymentsRepo = PaymentsRepository(db);
    calculator = EnhancedBookingCalculationService(db);

    PaymentSessionContext.start(userId: 1, userName: 'اختبار');

    await RoomsRepository(
      db,
    ).create(roomNumber: '101', type: 'عادية', price: rate, status: 'شاغرة');
  });

  tearDown(() async {
    PaymentSessionContext.clear();
    await db.close();
  });

  /// حجز مغادر فعلياً: دخول 03-01 15:00، مخطط 03-02 14:00،
  /// فعلي [actual] (افتراضياً 03-04 10:00)، ودفعة 350.
  Future<Booking> seedCheckedOutBooking({DateTime? actual}) async {
    final id = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'ضيف مراجعة المغادرة الفعلية',
      guestPhone: '0500000001',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      checkoutDate: plannedCheckout.toIso8601String(),
      status: 'نشط',
      expectedNights: 1,
    );
    await paymentsRepo.create(
      bookingLocalId: id,
      roomNumber: '101',
      amount: 350,
      paymentDate: checkin.toIso8601String(),
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );
    await bookingsRepo.update(
      id,
      status: 'مكتمل',
      actualCheckout: (actual ?? actualCheckout).toIso8601String(),
      calculatedNights: 3,
    );
    return fetchBooking(id);
  }

  /// حجز نشط بلا مغادرة فعلية: دخول 03-01 15:00، مخطط 03-02 14:00
  /// (مضى قبل «الآن» بفترة طويلة)، ودفعة 350.
  Future<Booking> seedActiveBooking() async {
    final id = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'ضيف مراجعة الإقامة النشطة',
      guestPhone: '0500000002',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      checkoutDate: plannedCheckout.toIso8601String(),
      status: 'نشط',
      expectedNights: 1,
    );
    await paymentsRepo.create(
      bookingLocalId: id,
      roomNumber: '101',
      amount: 350,
      paymentDate: checkin.toIso8601String(),
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );
    return fetchBooking(id);
  }

  group('T1 — actualCheckout المسجّل يقطع تراكم الليالي', () {
    test(
      'StayBalanceCalculator يحسب حتى actualCheckout لا حتى الآن ولا المخطط',
      () async {
        final booking = await seedCheckedOutBooking();

        final stay = StayBalanceCalculator.calculate(
          booking,
          roomRate: rate,
          now: nowA,
        );

        // 3 ليالٍ فعلية: حتى 03-04 10:00. لولاه لكانت 10 (حتى الآن)
        // أو 2 (حتى المخطط) — القيمة تميّز المسار الصحيح وحده.
        expect(
          stay.actualNightsSpent,
          3,
          reason:
              'الإقامة تنتهي عند actualCheckout=03-04 10:00 '
              'وليس عند now=03-10 15:00 ولا plannedCheckout=03-02 14:00',
        );
        expect(stay.consumedCost, 300, reason: '3 ليالٍ × 100');
        expect(stay.effectiveBalance, 50, reason: '350 مدفوع − 300 مستهلك');
        expect(stay.manualNightsRemaining, 0, reason: 'المخطط مضى قبل الآن');
      },
    );

    test(
      'EnhancedBookingCalculationService يعتمد actualCheckout نهايةً للإقامة',
      () async {
        final booking = await seedCheckedOutBooking();

        final result = await calculator.calculateForBooking(booking, now: nowA);

        expect(result.bookingActive, isFalse);
        expect(result.checkout, actualCheckout);
        expect(
          result.financialSummary.totalNights,
          3,
          reason: 'التفصيل الليلي يُبنى حتى actualCheckout فقط',
        );
      },
    );
  });

  group('T2 — بعد actualCheckout تبقى القيم ثابتة مهما تقدّم الآن', () {
    test(
      'StayBalanceCalculator: نفس الليالي والتكلفة والرصيد عبر ثلاث لحظات',
      () async {
        final booking = await seedCheckedOutBooking();

        final results = [
          StayBalanceCalculator.calculate(booking, roomRate: rate, now: nowA),
          StayBalanceCalculator.calculate(booking, roomRate: rate, now: nowB),
          StayBalanceCalculator.calculate(booking, roomRate: rate, now: nowC),
        ];

        for (final stay in results) {
          expect(stay.actualNightsSpent, 3);
          expect(stay.consumedCost, 300);
          expect(stay.effectiveBalance, 50);
        }
        expect(
          results[0].consumedCost,
          results[2].consumedCost,
          reason: 'لا تراكم بعد انتهاء الإقامة الفعلية',
        );
      },
    );

    test(
      'المحرك الموحد: checkout وtotalNights لا يتغيران بتقدم الآن',
      () async {
        final booking = await seedCheckedOutBooking();

        final rA = await calculator.calculateForBooking(booking, now: nowA);
        final rB = await calculator.calculateForBooking(booking, now: nowB);
        final rC = await calculator.calculateForBooking(booking, now: nowC);

        expect(rA.checkout, actualCheckout);
        expect(rB.checkout, actualCheckout);
        expect(rC.checkout, actualCheckout);
        expect(rA.financialSummary.totalNights, 3);
        expect(rB.financialSummary.totalNights, 3);
        expect(rC.financialSummary.totalNights, 3);
      },
    );
  });

  group('T3 — بلا actualCheckout: الاستمرار حتى الآن رغم مضي المخطط', () {
    test(
      'StayBalanceCalculator يراكم حتى now وليس حتى plannedCheckout',
      () async {
        final booking = await seedActiveBooking();

        final stay = StayBalanceCalculator.calculate(
          booking,
          roomRate: rate,
          now: nowA,
        );

        // حتى الآن = 10 ليالٍ؛ لولا ذلك لكانت 2 (سقف المخطط).
        expect(
          stay.actualNightsSpent,
          10,
          reason:
              'الحجز النشط يتراكم ديناميكياً حتى اللحظة الحالية، '
              'والمغادرة المخططة 03-02 14:00 لا توقفه',
        );
        expect(stay.consumedCost, 1000, reason: '10 ليالٍ × 100');
        expect(
          stay.manualNightsRemaining,
          0,
          reason: 'لا ليالٍ متبقية حتى مخطط مضى',
        );
      },
    );

    test(
      'المحرك الموحد: bookingActive=true وcheckout=now وtotalNights ديناميكي',
      () async {
        final booking = await seedActiveBooking();

        final result = await calculator.calculateForBooking(booking, now: nowA);

        expect(result.bookingActive, isTrue);
        expect(result.checkout, nowA);
        expect(
          result.financialSummary.totalNights,
          10,
          reason: 'الحساب ديناميكي حتى اللحظة الحالية',
        );
      },
    );
  });

  group('T4 — حدّ اليوم الفندقي بالثانية: 14:00:59 مقابل 14:01:00', () {
    test('nightsWithCutoff بالبارامترات الافتراضية يميّز الثانية الواحدة', () {
      // بداية يوم الفندق: 03-01 14:01.
      // حتى 03-04 14:00:59 → 2×24h + 23:59:59 → ليلتان + أساس = 3.
      expect(
        Time.nightsWithCutoff(
          checkin,
          checkout: DateTime(2024, 3, 4, 14, 0, 59),
        ),
        3,
        reason: '14:00:59 ما زال داخل اليوم الفندقي — لا ليلة إضافية',
      );
      // حتى 03-04 14:01:00 → 3×24h بالضبط → 4 ليالٍ.
      expect(
        Time.nightsWithCutoff(
          checkin,
          checkout: DateTime(2024, 3, 4, 14, 1, 0),
        ),
        4,
        reason: '14:01:00 يبدأ يوماً فندقياً جديداً — ليلة إضافية',
      );
    });

    test('getHotelDay وisAfterCutoff وgetHotelDayRange عند الحدّ', () {
      final beforeCutoff = DateTime(2024, 3, 4, 14, 0, 59);
      final atCutoff = DateTime(2024, 3, 4, 14, 1, 0);

      expect(HotelTimeEngine.getHotelDay(beforeCutoff), DateTime(2024, 3, 3));
      expect(HotelTimeEngine.getHotelDay(atCutoff), DateTime(2024, 3, 4));

      expect(HotelTimeEngine.isAfterCutoff(beforeCutoff), isFalse);
      expect(HotelTimeEngine.isAfterCutoff(atCutoff), isTrue);

      final rangeBefore = HotelTimeEngine.getHotelDayRange(beforeCutoff);
      expect(rangeBefore['start'], DateTime(2024, 3, 3, 14, 1));
      expect(rangeBefore['end'], DateTime(2024, 3, 4, 14, 0, 59, 999));

      final rangeAt = HotelTimeEngine.getHotelDayRange(atCutoff);
      expect(rangeAt['start'], DateTime(2024, 3, 4, 14, 1));
      expect(rangeAt['end'], DateTime(2024, 3, 5, 14, 0, 59, 999));
    });

    test('actualCheckout عند 14:00:59 → 3 ليالٍ عبر مسار الإنتاج', () async {
      final booking = await seedCheckedOutBooking(
        actual: DateTime(2024, 3, 4, 14, 0, 59),
      );

      final stay = StayBalanceCalculator.calculate(
        booking,
        roomRate: rate,
        now: nowA,
      );
      expect(stay.actualNightsSpent, 3);
      expect(stay.consumedCost, 300);

      final result = await calculator.calculateForBooking(booking, now: nowA);
      expect(result.financialSummary.totalNights, 3);
      expect(result.checkout, DateTime(2024, 3, 4, 14, 0, 59));
    });

    test('actualCheckout عند 14:01:00 → 4 ليالٍ عبر مسار الإنتاج', () async {
      final booking = await seedCheckedOutBooking(
        actual: DateTime(2024, 3, 4, 14, 1, 0),
      );

      final stay = StayBalanceCalculator.calculate(
        booking,
        roomRate: rate,
        now: nowA,
      );
      expect(stay.actualNightsSpent, 4);
      expect(stay.consumedCost, 400);

      final result = await calculator.calculateForBooking(booking, now: nowA);
      expect(result.financialSummary.totalNights, 4);
      expect(result.checkout, DateTime(2024, 3, 4, 14, 1, 0));
    });
  });
}
