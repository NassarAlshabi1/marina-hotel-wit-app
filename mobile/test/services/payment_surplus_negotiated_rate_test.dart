// ============================================================================
//  Marina Hotel — التفاوض على سعر الغرفة من شاشة الدفع (سقف 5000/ليلة)
// ============================================================================
//  قاعدة العمل (2026-11-01): فائض الدفعة الناتج عن اتفاق تفاوضي على سعر
//  الغرفة يُعالَج كزيادة على سعر الليلة الأصلي — يدخلها المستخدم المخوّل
//  يدوياً (وليست مشتقة من مبلغ الدفعة)، وتسري على كامل ليالي الحجز:
//
//    • غرفة 20,000 + زيادة 3,000 → الليلة 23,000 (الأصلي محفوظ).
//    • حجز 4 ليالٍ → إجمالي الإقامة 92,000، وإجمالي الزيادة 12,000.
//    • السقف: الزيادة ≤ 5,000 فوق السعر الأصلي لليلة (الحد 25,000).
//    • مغادرة مبكرة بعد ليلتين → 2 × 23,000 = 46,000 (الزيادة تُستهلك
//      كسعر لليلة، ليست مبلغاً منفصلاً غير قابل للاستهلاك).
//    • التعديل مالي فقط: لا يتمدد الحجز ولا تُضاف ليالٍ ولا تُنشأ دفعات.
//
//  الاختبارات العشرة المطلوبة تغطي: التسعير، حدود السقف، الحجز الكامل،
//  المغادرة المبكرة، إلغاء دفعة، إعادة الفتح، المزامنة، منع التكرار،
//  وعدم تأثر الحجوزات التاريخية.
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/booking_derived_fields_service.dart';
import 'package:marina_hotel_mobile/services/booking_price_adjustment_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/payment_void_service.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/stay_balance_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const double roomRate = 20000; // سعر الغرفة الأصلي — مثال قاعدة العمل
  late AppDatabase db;
  late BookingsRepository bookingsRepo;
  late PaymentsRepository paymentsRepo;
  late BookingPriceAdjustmentService adjustmentService;
  late BookingDerivedFieldsService derivedService;

  // دخول 2026-10-01 الساعة 10:00 (قبل حد 14:01) → يوم الدخول الفندقي
  // يبدأ 2026-09-30 14:01، وبالتالي:
  //   • اللحظة 2026-10-04 10:00 = 4 ليالٍ بالضبط (30/9، 1/10، 2/10، 3/10)
  //   • اللحظة 2026-10-02 10:00 = ليلتان بالضبط (30/9، 1/10)
  final checkin = DateTime(2026, 10, 1, 10);
  final fourNightsLater = DateTime(2026, 10, 4, 10);
  final afterTwoNights = DateTime(2026, 10, 2, 10);

  Future<Booking> fetchBooking(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  Future<List<BookingNight>> fetchNights(int id) =>
      (db.select(db.bookingNights)
            ..where((n) => n.bookingLocalId.equals(id))
            ..where((n) => n.deletedAt.isNull())
            ..orderBy([(n) => OrderingTerm.asc(n.sequence)]))
          .get();

  Future<Booking> seedBooking({DateTime? checkout}) async {
    final id = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'نزيل اختبار',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      checkoutDate: checkout?.toIso8601String(),
      status: 'نشط',
      expectedNights: 4,
    );
    return fetchBooking(id);
  }

  /// نفس تسلسل شاشة الدفع في مسار التفاوض (دون طبقة الواجهة):
  /// تحديث مشتق → اعتماد الزيادة التفاوضية → تسجيل الدفعة → تحديث مشتق.
  /// الدفعة مبلغ حقيقي واحد — لا دفعة وهمية للزيادة.
  Future<Booking> negotiateAndPay(
    Booking booking, {
    required int increase,
    required double paymentAmount,
  }) async {
    await derivedService.refreshForBookingId(booking.id, now: fourNightsLater);
    await adjustmentService.applyNegotiatedRateIncrease(
      bookingLocalUuid: booking.localUuid,
      amount: increase,
      appliedBy: 'اختبار',
      now: fourNightsLater,
    );
    await paymentsRepo.create(
      bookingLocalId: booking.id,
      roomNumber: booking.roomNumber,
      amount: paymentAmount,
      paymentDate: fourNightsLater.toIso8601String(),
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );
    await derivedService.refreshForBookingId(booking.id, now: fourNightsLater);
    return fetchBooking(booking.id);
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookingsRepo = BookingsRepository(db);
    paymentsRepo = PaymentsRepository(db);
    adjustmentService = BookingPriceAdjustmentService(db);
    derivedService = BookingDerivedFieldsService(db);

    PaymentSessionContext.start(userId: 1, userName: 'اختبار');

    await RoomsRepository(db).create(
      roomNumber: '101',
      type: 'عادية',
      price: roomRate,
      status: 'شاغرة',
    );
  });

  tearDown(() async {
    PaymentSessionContext.clear();
    BookingPriceAdjustmentService.debugClearNegotiationGuardsForTest();
    await db.close();
  });

  group('التفاوض على سعر الغرفة من شاشة الدفع (قاعدة 2026-11-01)', () {
    test(
      '1 — غرفة 20,000 وزيادة 3,000 لكل ليلة: السعر الجديد 23,000 والأصلي محفوظ',
      () async {
        final booking = await seedBooking();
        final after = await negotiateAndPay(
          booking,
          increase: 3000,
          paymentAmount: 92000,
        );

        final nights = await fetchNights(booking.id);
        expect(nights, hasLength(4), reason: 'أربع ليالٍ بلا أي تمديد');
        expect(
          nights.every((n) => n.baseRate == roomRate),
          isTrue,
          reason: 'سعر الغرفة الأصلي محفوظ في كل ليلة',
        );
        expect(nights.every((n) => n.adjustment == 3000), isTrue);
        expect(
          nights.every((n) => n.finalRate == 23000 && n.nightlyRate == 23000),
          isTrue,
          reason: 'السعر النهائي المعتمد لكل ليلة = 23,000',
        );
        expect(after.totalDueCached, 92000, reason: 'إجمالي الإقامة 92,000');
        expect(after.totalPaidCached, 92000);
        expect(after.remainingBalanceCached, 0);
        expect(after.isFullyPaid, isTrue);

        // سجل التعديل الكنوني: التاريخ/الوقت والمعتمِد والارتباط بالحجز
        final adjustments = await adjustmentService.getActiveAdjustments(
          booking.localUuid,
        );
        expect(adjustments, hasLength(1));
        final adj = adjustments.single;
        expect(adj.adjustmentType, 1, reason: 'surcharge');
        expect(adj.adjustmentMode, 'per_night');
        expect(adj.amount, 3000);
        expect(adj.appliedBy, 'اختبار');
        expect(adj.createdAt, greaterThan(0), reason: 'تاريخ ووقت الزيادة');
        expect(adj.bookingLocalUuid, booking.localUuid);
        expect(adj.bookingLocalId, booking.id);
        expect(adj.roomNumber, booking.roomNumber);
        expect(adj.endHotelDay, isNull, reason: 'مفتوحة لكامل ليالي الحجز');
      },
    );

    test('2 — زيادة 5,000 (السقف بالضبط): مقبولة والليلة 25,000', () async {
      final booking = await seedBooking();
      final after = await negotiateAndPay(
        booking,
        increase: 5000,
        paymentAmount: 100000,
      );

      final nights = await fetchNights(booking.id);
      expect(nights.every((n) => n.finalRate == 25000), isTrue);
      expect(after.totalDueCached, 100000, reason: '4 × 25,000');

      // السقف الكلّي: بعد بلوغ 5,000 أي زيادة إضافية تُرفض
      await expectLater(
        adjustmentService.applyNegotiatedRateIncrease(
          bookingLocalUuid: booking.localUuid,
          amount: 1,
          appliedBy: 'اختبار',
        ),
        throwsA(isA<StateError>()),
        reason: 'الزيادة الكلية فوق الأصلي لا تتجاوز 5,000/ليلة',
      );
    });

    test('3 — زيادة 5,001: مرفوضة ولا يُنشأ أي سجل ولا يتغير السعر', () async {
      final booking = await seedBooking();
      await derivedService.refreshForBookingId(
        booking.id,
        now: fourNightsLater,
      );

      await expectLater(
        adjustmentService.applyNegotiatedRateIncrease(
          bookingLocalUuid: booking.localUuid,
          amount: 5001,
          appliedBy: 'اختبار',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        await adjustmentService.getActiveAdjustments(booking.localUuid),
        isEmpty,
        reason: 'لا سجل تعديل عند الرفض',
      );
      final nights = await fetchNights(booking.id);
      expect(
        nights.every((n) => n.finalRate == roomRate),
        isTrue,
        reason: 'السعر لم يتغير بعد الرفض',
      );
    });

    test(
      '4 — حجز 4 ليالٍ بسعر متفاوض: 4 × 23,000 = 92,000 والمحرك الموحد يرى السعر',
      () async {
        final booking = await seedBooking(checkout: fourNightsLater);
        final after = await negotiateAndPay(
          booking,
          increase: 3000,
          paymentAmount: 46000, // دفعة جزئية
        );

        expect(after.totalNightsCached, 4, reason: 'عدد الليالي لم يتغير');
        expect(after.totalDueCached, 92000);
        expect(after.totalPaidCached, 46000);
        expect(after.remainingBalanceCached, 46000);
        expect(
          after.checkoutDate,
          isNotNull,
          reason: 'تاريخ المغادرة كما أدخله المستخدم — لم يُمسّ',
        );
        expect(after.expectedNights, 4, reason: 'لا تمديد ولا ليالٍ إضافية');
        expect(
          await fetchNights(booking.id),
          hasLength(4),
          reason: 'لا سجلات ليالٍ وهمية',
        );

        // المحرك الموحد (StayBalanceCalculator) يرى السعر المتفاوض عليه
        final adjustments = await adjustmentService.getActiveAdjustments(
          booking.localUuid,
        );
        final calc = StayBalanceCalculator.calculate(
          after,
          roomRate: roomRate,
          priceAdjustments: StayBalanceCalculator.filterActiveAdjustments(
            after,
            adjustments,
          ),
          now: fourNightsLater,
        );
        expect(calc.consumedCost, 92000, reason: '4 ليالٍ × 23,000');
        expect(calc.effectiveNightlyRate, 23000);
        expect(calc.totalPaidNights, 2, reason: '46,000 تغطي ليلتين فقط');
      },
    );

    test(
      '5 — مغادرة مبكرة بعد ليلتين: 2 × 23,000 = 46,000 والمسترد وفق النظام',
      () async {
        final booking = await seedBooking(checkout: fourNightsLater);
        await negotiateAndPay(booking, increase: 3000, paymentAmount: 92000);

        expect(
          (await fetchBooking(booking.id)).totalDueCached,
          92000,
          reason: 'قبل المغادرة: 4 × 23,000',
        );

        // مغادرة فعلية بعد ليلتين — الليالي المستخدمة بالسعر المتفاوض
        await bookingsRepo.update(
          booking.id,
          actualCheckout: afterTwoNights.toIso8601String(),
        );

        final after = await fetchBooking(booking.id);
        final nights = await fetchNights(booking.id);
        expect(nights, hasLength(2), reason: 'اقتطاع الليالي حتى المغادرة');
        expect(
          nights.every((n) => n.finalRate == 23000),
          isTrue,
          reason: 'الليالي المستخدمة تُحتسب بالسعر المتفاوض عليه',
        );
        expect(after.totalDueCached, 46000, reason: '2 × 23,000 = 46,000');
        expect(after.totalPaidCached, 92000);
        // نظام المحاسبة الحالي: المتبقي يُقيد عند صفر والفارق (46,000)
        // رصيد دائن للنزيل يُعالَج بمسار الاسترداد القائم
        expect(after.remainingBalanceCached, 0);
      },
    );

    test(
      '6 — إلغاء دفعة مرتبطة بالحجز: المتبقي يعود والسعر المتفاوض باقٍ',
      () async {
        final booking = await seedBooking();
        await negotiateAndPay(booking, increase: 3000, paymentAmount: 92000);
        expect((await fetchBooking(booking.id)).isFullyPaid, isTrue);

        final payment =
            (db.select(db.payments)
                  ..where((p) => p.bookingLocalId.equals(booking.id)))
                .get()
                .then((rows) => rows.single);

        final ok = await PaymentVoidService(db).voidPayment(
          paymentUuid: (await payment).localUuid,
          voidReason: 'اختبار — إلغاء دفعة',
          voidedBy: 'اختبار',
        );
        expect(ok, isTrue);

        // إعادة التطبيع بوقت اختباري ثابت (التحديث داخل voidPayment يستخدم
        // الوقت الحقيقي فتنمو ليالي الحجز النشط حتى اليوم) — الغرض: تثبيت
        // عدد الليالي للتحقق من أن السعر المتفاوض باقٍ بعد الإلغاء.
        await derivedService.refreshForBookingId(
          booking.id,
          now: fourNightsLater,
          forceRebuild: true,
        );

        final after = await fetchBooking(booking.id);
        expect(after.totalPaidCached, 0, reason: 'الدفعة الملغاة خارج الرصيد');
        expect(
          after.totalDueCached,
          92000,
          reason: 'إجمالي الإقامة بالسعر المتفاوض لم يتأثر بالإلغاء',
        );
        expect(after.remainingBalanceCached, 92000);
        expect(after.isFullyPaid, isFalse);
        expect(
          (await fetchNights(booking.id)).every((n) => n.finalRate == 23000),
          isTrue,
          reason: 'السعر المتفاوض باقٍ بعد إلغاء الدفعة',
        );
      },
    );

    test(
      '7 — إعادة فتح الحجز: السعر المتفاوض عليه باقٍ بعد إعادة الفتح',
      () async {
        final booking = await seedBooking();
        await negotiateAndPay(booking, increase: 3000, paymentAmount: 92000);

        // تسجيل مغادرة مبكرة ثم إعادة الفتح (مسح المغادرة الفعلية)
        await bookingsRepo.update(
          booking.id,
          actualCheckout: afterTwoNights.toIso8601String(),
        );
        expect(await fetchNights(booking.id), hasLength(2));

        await (db.update(db.bookings)..where((b) => b.id.equals(booking.id)))
            .write(const BookingsCompanion(actualCheckout: Value('')));
        await derivedService.refreshForBookingId(
          booking.id,
          now: fourNightsLater,
          forceRebuild: true,
        );

        final nights = await fetchNights(booking.id);
        expect(
          nights,
          hasLength(4),
          reason: 'عودة الليالي الأربع بعد إعادة الفتح',
        );
        expect(
          nights.every((n) => n.finalRate == 23000),
          isTrue,
          reason: 'السعر المتفاوض محفوظ — مصدره سجل التعديل لا حالة الحجز',
        );
        final after = await fetchBooking(booking.id);
        expect(after.totalDueCached, 92000);
        expect(
          await adjustmentService.getActiveAdjustments(booking.localUuid),
          hasLength(1),
        );
      },
    );

    test(
      '8 — مزامنة الحجز والتعديل مع Appwrite: UUID محفوظ وبلا تكرار',
      () async {
        final booking = await seedBooking();
        await derivedService.refreshForBookingId(
          booking.id,
          now: fourNightsLater,
        );
        final adj = await adjustmentService.applyNegotiatedRateIncrease(
          bookingLocalUuid: booking.localUuid,
          amount: 3000,
          appliedBy: 'اختبار',
        );

        // (أ) عنصر Outbox جاهز للرفع بنفس UUID — لا فقدان عند انقطاع الشبكة
        final outboxRows =
            await (db.select(db.outbox)
                  ..where((t) => t.entity.equals('booking_price_adjustments'))
                  ..where((t) => t.localUuid.equals(adj.localUuid)))
                .get();
        expect(
          outboxRows,
          isNotEmpty,
          reason: 'التعديل مُدرج في Outbox للمزامنة',
        );
        expect(outboxRows.single.op, 'create');

        // (ب) محاكاة سحب مستند Appwrite مرتين (تكرار مزامنة) عبر مسار
        // الـ adapter نفسه — سجل واحد، UUID محفوظ، مرتبط بالحجز الصحيح
        final adapters = AdapterRegistry(db);
        final remoteDoc = <String, dynamic>{
          'localUuid': adj.localUuid,
          'bookingLocalUuid': booking.localUuid,
          'roomNumber': booking.roomNumber,
          'adjustmentType': 1,
          'adjustmentMode': 'per_night',
          'amount': 3000.0,
          'effectiveHotelDay': adj.effectiveHotelDay,
          'endHotelDay': null,
          'isActive': true,
          'reason': BookingPriceAdjustmentService.negotiatedRateReason,
          'appliedBy': 'اختبار',
          'createdAt': adj.createdAt,
          'updatedAt': adj.updatedAt,
          'lastModified': adj.lastModified,
        };

        final first = await adapters.bookingPriceAdjustments.upsertFromJson(
          Map<String, dynamic>.from(remoteDoc),
          src: Source.appwrite,
        );
        await adapters.bookingPriceAdjustments.upsertFromJson(
          Map<String, dynamic>.from(remoteDoc),
          src: Source.appwrite,
        );
        expect(first, greaterThan(0));

        final all = await (db.select(
          db.bookingPriceAdjustments,
        )..where((a) => a.bookingLocalUuid.equals(booking.localUuid))).get();
        expect(
          all,
          hasLength(1),
          reason: 'لا تعديلات مكررة عند تكرار المزامنة',
        );
        expect(all.single.localUuid, adj.localUuid, reason: 'UUID محفوظ');
        expect(
          all.single.bookingLocalId,
          booking.id,
          reason: 'مرتبط بالحجز الصحيح',
        );
        expect(all.single.amount, 3000, reason: 'قيمة الزيادة سليمة بعد السحب');
        expect(all.single.isActive, isTrue);
        expect(
          all.single.reason,
          BookingPriceAdjustmentService.negotiatedRateReason,
        );
      },
    );

    test('9 — منع التكرار عند الضغط المتكرر: سجل واحد فقط', () async {
      final booking = await seedBooking();
      await derivedService.refreshForBookingId(
        booking.id,
        now: fourNightsLater,
      );

      // ضغط متكرر متزامن (double-tap) — نفس النتيجة بلا سجل مكرر
      final results = await Future.wait([
        adjustmentService.applyNegotiatedRateIncrease(
          bookingLocalUuid: booking.localUuid,
          amount: 3000,
          appliedBy: 'اختبار',
          now: fourNightsLater,
        ),
        adjustmentService.applyNegotiatedRateIncrease(
          bookingLocalUuid: booking.localUuid,
          amount: 3000,
          appliedBy: 'اختبار',
          now: fourNightsLater,
        ),
      ]);
      expect(results[0].localUuid, results[1].localUuid);

      // تكرار متتابع سريع خلال نافذة المنع — يعيد السجل نفسه
      final again = await adjustmentService.applyNegotiatedRateIncrease(
        bookingLocalUuid: booking.localUuid,
        amount: 3000,
        appliedBy: 'اختبار',
        now: fourNightsLater,
      );
      expect(again.localUuid, results[0].localUuid);

      final all = await (db.select(
        db.bookingPriceAdjustments,
      )..where((a) => a.bookingLocalUuid.equals(booking.localUuid))).get();
      expect(all, hasLength(1), reason: 'سجل تفاوض واحد مهما تكرر الضغط');
    });

    test(
      '10 — الحجوزات التاريخية لا تتأثر بالإضافة ولا بتغيير سعر الغرفة',
      () async {
        // حجز مكتمل قديم بغرفة أخرى وسعرها المسجّل وقت الإقامة
        await RoomsRepository(db).create(
          roomNumber: '102',
          type: 'عادية',
          price: 15000,
          status: 'شاغرة',
        );
        final oldId = await bookingsRepo.create(
          roomNumber: '102',
          guestName: 'نزيل قديم',
          guestPhone: '0500000001',
          guestNationality: 'يمني',
          checkinDate: DateTime(2026, 9, 1, 10).toIso8601String(),
          status: 'نشط',
          expectedNights: 2,
        );
        final oldUuid = (await fetchBooking(oldId)).localUuid;
        await derivedService.refreshForBookingId(
          oldId,
          now: DateTime(2026, 9, 2, 10),
        );
        await bookingsRepo.update(
          oldId,
          actualCheckout: DateTime(2026, 9, 2, 10).toIso8601String(),
        );
        expect(
          (await fetchBooking(oldId)).totalDueCached,
          30000,
          reason: 'الحجز التاريخي: 2 × 15,000 بسعره المحفوظ',
        );

        // تفاوض على حجز آخر نشط (الميزة الجديدة)
        final booking = await seedBooking();
        await negotiateAndPay(booking, increase: 3000, paymentAmount: 92000);

        // تغيير سعر الغرفة الأساسي مستقبلاً لا يغيّر الحجز المكتمل
        await (db.update(db.rooms)..where((r) => r.roomNumber.equals('102')))
            .write(const RoomsCompanion(price: Value(99999)));
        await derivedService.refreshForBookingId(oldId);

        final oldAfter = await fetchBooking(oldId);
        expect(
          oldAfter.totalDueCached,
          30000,
          reason: 'تغيير سعر الغرفة لا يمسّ الحجوزات المكتملة',
        );
        final oldNights = await fetchNights(oldId);
        expect(oldNights, hasLength(2));
        expect(
          oldNights.every((n) => n.finalRate == 15000),
          isTrue,
          reason: 'الليالي التاريخية بأسعارها المسجّلة',
        );
        expect(
          await adjustmentService.getActiveAdjustments(oldUuid),
          isEmpty,
          reason: 'الحجز القديم لا يُعاد اعتباره حجزاً متفاوضاً عليه',
        );
      },
    );

    test(
      '11 — تخفيض 3,000 لكل ليلة مقبول ويعيد تسعير الليالي الأربع',
      () async {
        final booking = await seedBooking();
        await derivedService.refreshForBookingId(
          booking.id,
          now: fourNightsLater,
        );

        final result = await adjustmentService.applyNegotiatedRateAdjustment(
          bookingLocalUuid: booking.localUuid,
          amount: 3000,
          type: AdjustmentType.discount,
          appliedBy: 'اختبار',
          now: fourNightsLater,
        );

        expect(result.isDuplicate, isFalse);
        expect(result.adjustment.adjustmentType, AdjustmentType.discount.value);
        final nights = await fetchNights(booking.id);
        expect(nights, hasLength(4));
        expect(nights.every((night) => night.finalRate == 17000), isTrue);
        expect((await fetchBooking(booking.id)).totalDueCached, 68000);
      },
    );

    test('12 — تخفيض 3,001 مرفوض ولا ينشئ سجلًا', () async {
      final booking = await seedBooking();
      await derivedService.refreshForBookingId(
        booking.id,
        now: fourNightsLater,
      );

      await expectLater(
        adjustmentService.applyNegotiatedRateAdjustment(
          bookingLocalUuid: booking.localUuid,
          amount: 3001,
          type: AdjustmentType.discount,
          appliedBy: 'اختبار',
          now: fourNightsLater,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        await adjustmentService.getActiveAdjustments(booking.localUuid),
        isEmpty,
      );
    });

    test('13 — لا يقبل التفاوض بعد تسجيل المغادرة الفعلية', () async {
      final booking = await seedBooking();
      await derivedService.refreshForBookingId(
        booking.id,
        now: fourNightsLater,
      );
      await bookingsRepo.update(
        booking.id,
        actualCheckout: fourNightsLater.toIso8601String(),
      );

      await expectLater(
        adjustmentService.applyNegotiatedRateAdjustment(
          bookingLocalUuid: booking.localUuid,
          amount: 1000,
          type: AdjustmentType.surcharge,
          appliedBy: 'اختبار',
          now: fourNightsLater,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        await adjustmentService.getActiveAdjustments(booking.localUuid),
        isEmpty,
      );
    });

    test(
      '14 — الحجز المعاد فتحه مع actualCheckout فارغ يبقى قابلًا للتفاوض',
      () async {
        final booking = await seedBooking();
        await (db.update(db.bookings)
              ..where((row) => row.id.equals(booking.id)))
            .write(const BookingsCompanion(actualCheckout: Value('')));
        await derivedService.refreshForBookingId(
          booking.id,
          now: fourNightsLater,
          forceRebuild: true,
        );

        final result = await adjustmentService.applyNegotiatedRateAdjustment(
          bookingLocalUuid: booking.localUuid,
          amount: 1000,
          type: AdjustmentType.surcharge,
          appliedBy: 'اختبار',
          now: fourNightsLater,
        );

        expect(result.isDuplicate, isFalse);
        expect(result.adjustment.amount, 1000);
        expect(await fetchNights(booking.id), hasLength(4));
      },
    );
  });
}
