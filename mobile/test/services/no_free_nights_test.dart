// ============================================================================
//  Marina Hotel — «لا ليالٍ مجانية» (No Free Nights) — قاعدة المالك المثبتة
// ============================================================================
//  يغطي بنود الاختبار الإلزامي 8.2 من التدقيق (المحدّثة بقاعدة المالك
//  2026-11-23):
//   ① خصم يصفّر ليلة (per_night وtotal) يُرفض عند الإدخال برسالة صريحة.
//   ② إن وصلت ليلة صفرية السعر إلى الحاسبة من بيانات قديمة ⇒ النتيجة
//      تحمل hasAnomaly + anomalyNights — لا عبور صامت ولا مجانية ولا
//      إيقاف صامت غير معلن.
//   ③ سعر أساسي صفري مع مدفوعات ⇒ إعلان شذوذ صريح لا محاكاة صامتة.
//   ④ منع الاشتقاق المزدوج: baseRate من المتوسط المخبأ لا تُعاد عليه
//      التعديلات مرة ثانية.
//   ⑤ توحيد توزيع تعديل total بمنطق المحرك: على ليالي الإقامة الفعلية
//      داخل النطاق فقط — لا انتشار زور على 365 يوماً.
//  لا mock — قاعدة SQLite حقيقية في الذاكرة (NativeDatabase.memory).
// ============================================================================

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/booking_price_adjustment_service.dart';
import 'package:marina_hotel_mobile/services/enhanced_booking_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/stay_balance_calculator.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late RoomsRepository roomsRepo;
  late BookingsRepository bookingsRepo;
  late BookingPriceAdjustmentService adjustmentService;

  final today = DateTime.now();
  DateTime day(int daysBack, [int hour = 15, int minute = 0]) =>
      DateTime(today.year, today.month, today.day - daysBack, hour, minute);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    roomsRepo = RoomsRepository(db);
    bookingsRepo = BookingsRepository(db);
    adjustmentService = BookingPriceAdjustmentService(db);
    await roomsRepo.create(
      roomNumber: '101',
      type: 'عادية',
      price: 100.0,
      status: 'شاغرة',
    );
  });

  tearDown(() => db.close());

  Future<Booking> fetchBooking(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  /// تحديث الخزائن المخبأة مباشرة (كما تتركها المزامنة/الاستعادة).
  Future<void> setCachedTotals(
    int id, {
    required double due,
    required double paid,
    required int nights,
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await (db.update(db.bookings)..where((b) => b.id.equals(id))).write(
      BookingsCompanion(
        totalDueCached: d.Value(due),
        totalPaidCached: d.Value(paid),
        remainingBalanceCached: d.Value(due - paid),
        calculatedNights: d.Value(nights),
        updatedAt: d.Value(stamp),
      ),
    );
  }

  /// حجز نشط مفتوح (بلا مغادرة) — دخول بعد حد 14:01.
  Future<Booking> seedActiveBooking({
    int nightsAgo = 5,
    double due = 500,
    double paid = 500,
    int calculatedNights = 5,
    double discount = 0,
    String discountType = 'total',
  }) async {
    final id = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'نزيل اختبار',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: day(nightsAgo).toIso8601String(),
      status: 'نشط',
      expectedNights: nightsAgo,
      discount: discount,
      discountType: discountType,
    );
    await setCachedTotals(id, due: due, paid: paid, nights: calculatedNights);
    return fetchBooking(id);
  }

  /// إدراج تعديل سعر نشط مباشرة (نمط المسحوب من السحابة/القديم).
  Future<void> seedAdjustment(
    Booking booking, {
    required double amount,
    required int type, // 0 خصم / 1 زيادة
    required String mode,
    required String effectiveHotelDay,
    String? endHotelDay,
    String reason = 'تعديل سعري موثق للاختبار',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.bookingPriceAdjustments)
        .insert(
          BookingPriceAdjustmentsCompanion.insert(
            localUuid: 'adj-$now-${amount.round()}-$type',
            bookingLocalUuid: booking.localUuid,
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            bookingLocalId: d.Value(booking.id),
            roomNumber: d.Value(booking.roomNumber),
            amount: d.Value(amount),
            effectiveHotelDay: effectiveHotelDay,
            endHotelDay: d.Value(endHotelDay),
            reason: d.Value(reason),
            adjustmentType: d.Value(type),
            adjustmentMode: d.Value(mode),
          ),
        );
  }

  Future<List<BookingPriceAdjustment>> activeAdjustments(Booking booking) =>
      (db.select(db.bookingPriceAdjustments)
            ..where(
              (a) =>
                  a.bookingLocalUuid.equals(booking.localUuid) |
                  a.bookingLocalId.equals(booking.id),
            )
            ..where((a) => a.deletedAt.isNull()))
          .get();

  group('① منع عند الإدخال — خصم يصفّر ليلة يُرفض', () {
    test('per_night بمبلغ = سعر الغرفة يُرفض برسالة «لا ليالٍ مجانية»', () async {
      final booking = await seedActiveBooking();
      expect(
        () => adjustmentService.applyTemporaryAdjustment(
          bookingLocalUuid: booking.localUuid,
          amount: 100, // = السعر كاملاً → ليلة مجانية
          type: AdjustmentType.discount,
          mode: AdjustmentMode.perNight,
          effectiveHotelDay: HotelTimeEngine.getHotelDayKey(
            dateTime: day(2),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('لا ليالٍ مجانية'),
          ),
        ),
      );
      // ولم يُدرج أي سجل بعد الرفض
      expect(await activeAdjustments(booking), isEmpty);
    });

    test('per_night فوق الخصم الليلي القديم يُرفض (تراكم يصفّر الليلة)', () async {
      // سعر 100 − خصم قديم 50 = قاعدة فعلية 50؛ خصم جديد 60 يصفّرها.
      final booking = await seedActiveBooking(
        discount: 50,
        discountType: 'per_night',
      );
      expect(
        () => adjustmentService.applyTemporaryAdjustment(
          bookingLocalUuid: booking.localUuid,
          amount: 60,
          type: AdjustmentType.discount,
          mode: AdjustmentMode.perNight,
          effectiveHotelDay: HotelTimeEngine.getHotelDayKey(
            dateTime: day(1),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('total يغطي كامل الإقامة يُرفض (قسامة = السعر كاملاً)', () async {
      final booking = await seedActiveBooking(
        nightsAgo: 3,
        due: 300,
        calculatedNights: 3,
      );
      final startDay = HotelTimeEngine.getHotelDayKey(dateTime: day(3));
      final endDay = DateTime.parse(startDay)
          .add(const Duration(days: 2)); // نطاق 3 ليالٍ حتمي
      expect(
        () => adjustmentService.applyTemporaryAdjustment(
          bookingLocalUuid: booking.localUuid,
          amount: 10000, // 3 ليالٍ × 100 = 300 كحد أقصى → تصفير كامل حتمي
          type: AdjustmentType.discount,
          mode: AdjustmentMode.total,
          effectiveHotelDay: startDay,
          endHotelDay: Time.dateToString(endDay),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('لا ليالٍ مجانية'),
          ),
        ),
      );
    });

    test('خصم لا يصفّر يُقبل، وزيادة لا يمسها الحارس', () async {
      final booking = await seedActiveBooking();
      final accepted = await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: booking.localUuid,
        amount: 60, // 100 − 60 = 40 > 0
        type: AdjustmentType.discount,
        mode: AdjustmentMode.perNight,
        effectiveHotelDay: HotelTimeEngine.getHotelDayKey(
          dateTime: day(1),
        ),
      );
      expect(accepted.amount, 60);

      final surcharge = await adjustmentService.applyTemporaryAdjustment(
        bookingLocalUuid: booking.localUuid,
        amount: 500, // زيادة — لا يمكنها تصفير ليلة
        type: AdjustmentType.surcharge,
        mode: AdjustmentMode.perNight,
        effectiveHotelDay: HotelTimeEngine.getHotelDayKey(
          dateTime: day(1),
        ),
      );
      expect(surcharge.adjustmentType, 1);
    });
  });

  group('② إنذار عند الحساب — ليلة صفرية السعر من بيانات قديمة', () {
    test('hasAnomaly + anomalyNights، لا عبور ولا عدّ يتجاوزها', () async {
      final booking = await seedActiveBooking(
        nightsAgo: 5,
        due: 500,
        paid: 500,
        calculatedNights: 5,
      );
      // خصم قديم (بيانات مسحوبة) يساوي السعر كاملاً من الليلة الثالثة
      final checkinDay = HotelTimeEngine.getHotelDayKey(dateTime: day(5));
      final thirdNight = DateTime.parse(checkinDay)
          .add(const Duration(days: 2));
      await seedAdjustment(
        booking,
        amount: 100,
        type: 0,
        mode: 'per_night',
        effectiveHotelDay: Time.dateToString(thirdNight),
      );

      final result = StayBalanceCalculator.calculate(
        booking,
        roomRate: 100,
        priceAdjustments: await activeAdjustments(booking),
        now: day(0, 10),
      );

      expect(result.hasAnomaly, isTrue, reason: 'ليلة بسعر صفري يجب أن تُعلن');
      expect(result.anomalyNights, isNotEmpty);
      expect(result.anomalyReason, contains('لا ليالٍ مجانية'));
      // التغطية تتوقف عند الليلة الصفرية معلنةً — لا تعبرها مجاناً:
      // ليلتان قبلها فقط مغطاتان (المدفوع 500 لكن المحاكاة أوقفتها الشنورة)
      expect(result.totalPaidNights, 2);
      expect(result.coveredDates.length, 2);
    });

    test('ليلة مقضية فعلياً بسعر صفري تُسجل شذوذاً ولا تضاف بتكلفة زائفة', () async {
      final booking = await seedActiveBooking(
        nightsAgo: 5,
        due: 500,
        paid: 300,
        calculatedNights: 5,
      );
      final checkinDay = HotelTimeEngine.getHotelDayKey(dateTime: day(5));
      await seedAdjustment(
        booking,
        amount: 100,
        type: 0,
        mode: 'per_night',
        effectiveHotelDay: checkinDay, // من أول ليلة
      );

      final result = StayBalanceCalculator.calculate(
        booking,
        roomRate: 100,
        priceAdjustments: await activeAdjustments(booking),
        now: day(0, 10),
      );
      expect(result.hasAnomaly, isTrue);
      expect(result.anomalyNights, isNotEmpty);
    });
  });

  group('③ سعر أساسي صفري مع مدفوعات ⇒ شذوذ معلن لا محاكاة صامتة', () {
    test('النتيجة الاحتياطية تحمل سبباً صريحاً', () async {
      final booking = await seedActiveBooking(
        due: 0,
        paid: 500,
        calculatedNights: 0,
      );
      final result = StayBalanceCalculator.calculate(
        booking,
        roomRate: null, // لا سعر ممرر
        now: day(0, 10),
      );
      expect(result.hasAnomaly, isTrue);
      expect(result.anomalyReason, contains('سعر الليلة الأساسي'));
      expect(result.totalPaidNights, 0);
    });
  });

  group('④ منع الاشتقاق المزدوج للمتوسط المخبأ', () {
    test('baseRate من totalDueCached/nights لا تُعاد عليه التعديلات', () async {
      // متوسط مخبأ 100/ليلة (يضم أثر التعديلات أصلاً)
      final booking = await seedActiveBooking(
        nightsAgo: 10,
        due: 1000,
        paid: 500,
        calculatedNights: 10,
      );
      // تعديل إضافي لو طُبق لانقص 20/ليلة → احتساب مزدوج
      final checkinDay = HotelTimeEngine.getHotelDayKey(dateTime: day(10));
      await seedAdjustment(
        booking,
        amount: 20,
        type: 0,
        mode: 'per_night',
        effectiveHotelDay: checkinDay,
      );

      final result = StayBalanceCalculator.calculate(
        booking,
        roomRate: null, // يشتق من المخبأ → يجب ألا يطبق التعديلات ثانية
        priceAdjustments: await activeAdjustments(booking),
        now: day(0, 10),
      );

      // 10 ليالٍ مقضية × 100 (المتوسط) = 1000 — لا 10×80=800
      expect(result.actualNightsSpent, 10);
      expect(result.consumedCost, 1000);
      // التغطية: 500/100 = 5 ليال — لا 500/80
      expect(result.totalPaidNights, 5);
      expect(result.hasAnomaly, isFalse);
    });
  });

  group('⑤ توحيد توزيع total بمنطق المحرك (بند 3.1)', () {
    test('خصم كلي 20,000 على 10 ليالٍ × 3,000 ⇒ 2,000/ليلة للإقامة فقط',
        () async {
      // حجز نشط 10 ليالٍ حتى الآن، سعر 3,000
      await roomsRepo.create(
        roomNumber: '102',
        type: 'جناح',
        price: 3000.0,
        status: 'شاغرة',
      );
      final id = await bookingsRepo.create(
        roomNumber: '102',
        guestName: 'نزيل توحيد التوزيع',
        guestPhone: '0500000001',
        guestNationality: 'يمني',
        checkinDate: day(10).toIso8601String(),
        status: 'نشط',
        expectedNights: 10,
      );
      await setCachedTotals(id, due: 30000, paid: 10000, nights: 10);
      final booking = await fetchBooking(id);

      final checkinDay = HotelTimeEngine.getHotelDayKey(dateTime: day(10));
      // خصم كلي 20,000 بلا نهاية — الكود القديم وزعه على 365 يوماً (≈55/يوم)
      await seedAdjustment(
        booking,
        amount: 20000,
        type: 0,
        mode: 'total',
        effectiveHotelDay: checkinDay,
      );

      final adjustments = await activeAdjustments(booking);
      final result = StayBalanceCalculator.calculate(
        booking,
        roomRate: 3000,
        priceAdjustments: adjustments,
        now: day(0, 10), // قبل 15:00 → 10 ليالٍ مقضية بالضبط
      );

      // كل ليلة فعالة = 3000 − 2000 = 1000 → المدفوع 10,000 يغطي 10 ليالٍ
      expect(result.totalPaidNights, 10,
          reason: 'التوزيع الموحد: 20,000 على 10 ليالٍ = 2,000/ليلة');
      expect(result.surplusAfterAllNights, 0);

      // ✅ نفس رقم المحرك الموحد: المستحق = 10×3000 − 20,000 = 10,000
      final engine = EnhancedBookingCalculationService(db);
      final financials = await engine.calculateFinancials(
        booking,
        now: day(0, 10),
      );
      expect(financials.totalDue, 10000);
      expect(result.consumedCost, 10000);
    });

    test('تعديل خارج نطاق الإقامة لا يوزَّع زوراً على أيام التقويم', () async {
      final booking = await seedActiveBooking(
        nightsAgo: 5,
        due: 500,
        paid: 500,
        calculatedNights: 5,
      );
      // تعديل كلي يبدأ بعد شهر (خارج نطاق الإقامة الحالي)
      final futureDay = DateTime.parse(
        HotelTimeEngine.getHotelDayKey(dateTime: day(5)),
      ).add(const Duration(days: 30));
      await seedAdjustment(
        booking,
        amount: 500,
        type: 0,
        mode: 'total',
        effectiveHotelDay: Time.dateToString(futureDay),
      );
      final adjustments = await activeAdjustments(booking);

      final map = StayBalanceCalculator.buildPerNightAdjustments(
        adjustments,
        DateTime.parse(
          HotelTimeEngine.getHotelDayKey(dateTime: day(5)),
        ),
        null,
        distributionEnd: DateTime.now(),
      );
      expect(map, isEmpty,
          reason: 'نطاق التعديل خارج الإقامة → لا ليلة واحدة تتأثر');
    });
  });
}
