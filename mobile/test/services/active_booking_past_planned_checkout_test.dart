import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/enhanced_booking_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookingsRepository bookings;
  late EnhancedBookingCalculationService calculator;

  final checkin = DateTime(2024, 3, 1, 15);
  final plannedCheckout = DateTime(2024, 3, 2, 14);
  final beforeCutoff = DateTime(2024, 3, 4, 10);
  final afterCutoff = DateTime(2024, 3, 4, 15);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PaymentSessionContext.start(userId: 1, userName: 'اختبار');
    final rooms = RoomsRepository(db);
    bookings = BookingsRepository(db);
    calculator = EnhancedBookingCalculationService(db);
    await rooms.create(
      roomNumber: '101',
      type: 'عادية',
      price: 100,
      status: 'شاغرة',
    );
  });

  tearDown(() async {
    PaymentSessionContext.clear();
    await db.close();
  });

  Future<Booking> seedActiveBooking() async {
    final id = await bookings.create(
      roomNumber: '101',
      guestName: 'ضيف الاختبار',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      checkoutDate: plannedCheckout.toIso8601String(),
      status: 'نشط',
      expectedNights: 1,
    );
    return (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();
  }

  /// حجز نشط مفتوح (بلا تاريخ مغادرة مخطط) — النزيل بلا موعد مغادرة
  /// معروف ويدفع يومياً.
  Future<Booking> seedActiveOpenBooking() async {
    final id = await bookings.create(
      roomNumber: '101',
      guestName: 'ضيف بلا موعد مغادرة',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      status: 'نشط',
      expectedNights: 1,
    );
    return (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();
  }

  test('active booking keeps accruing nights after plannedCheckout', () async {
    final booking = await seedActiveBooking();

    final result = await calculator.calculateForBooking(
      booking,
      now: beforeCutoff,
    );

    expect(result.bookingActive, isTrue);
    expect(result.checkout, beforeCutoff);
    expect(result.financialSummary.totalNights, 3);
  });

  test(
    'active booking adds a night after the 14:01 hotel-day cutoff',
    () async {
      final booking = await seedActiveBooking();

      final result = await calculator.calculateForBooking(
        booking,
        now: afterCutoff,
      );

      expect(result.bookingActive, isTrue);
      expect(result.checkout, afterCutoff);
      expect(result.financialSummary.totalNights, 4);
    },
  );

  // ═══════════════════════════════════════════════════════════════
  // قاعدة العمل (2026-11-01): تاريخ المغادرة المخطط checkout_date
  // اختياري ولا يجوز توليده أو تعديله من مسار التمديد (التمديد التلقائي
  // من فائض الدفعة، أو حوار «تمديد الإقامة» في شاشة الدفع). المسار
  // الشرعي الوحيد لتغييره هو شاشة تعديل بيانات النزيل (booking_edit).
  // الإيقاف المالي للحساب يتم عبر actual_checkout فقط (زر «تسجيل
  // المغادرة»)، وما دام NULL يستمر الحساب حتى «الآن» مع حد 14:01 —
  // مثبت في الاختبارين أعلاه.
  //
  // شاشة الدفع تستدعي بالضبط:
  //   bookingsRepo.update(id, expectedNights: N, notes: '...')
  // بلا checkoutDate — هذه الاختبارات تحرس هذا العقد على مستوى
  // المستودع/قاعدة البيانات: أي إعادة إدخال لكتابة checkout_date من
  // مسار التمديد ستفشل هنا.
  // ═══════════════════════════════════════════════════════════════
  group('قاعدة العمل: التمديد لا يغيّر checkout_date', () {
    test('تمديد لحجز مفتوح (checkout_date = NULL) لا يولّد تاريخاً', () async {
      final booking = await seedActiveOpenBooking();
      expect(
        booking.checkoutDate,
        isNull,
        reason: 'الافتراض: حجز بلا تاريخ مغادرة مخطط',
      );

      // نفس نداء شاشة الدفع بعد إزالة checkoutDate من مسار التمديد.
      await bookings.update(
        booking.id,
        expectedNights: booking.expectedNights + 4,
        notes: 'تمديد تلقائي: 4 ليالي',
      );

      final after = await (db.select(
        db.bookings,
      )..where((b) => b.id.equals(booking.id))).getSingle();
      expect(
        after.checkoutDate,
        isNull,
        reason: 'التمديد لا يولّد checkout_date — يبقى NULL',
      );
      expect(
        after.actualCheckout,
        isNull,
        reason: 'التمديد لا يسجّل مغادرة فعلية',
      );
      expect(after.status, 'نشط');
    });

    test('تمديد لحجز بتاريخ مخطط قديم لا يستبدله بتاريخ أحدث', () async {
      final booking = await seedActiveBooking();
      expect(booking.checkoutDate, plannedCheckout.toIso8601String());

      await bookings.update(
        booking.id,
        expectedNights: booking.expectedNights + 2,
        notes: 'تمديد: 2 ليلة',
      );

      final after = await (db.select(
        db.bookings,
      )..where((b) => b.id.equals(booking.id))).getSingle();
      expect(
        after.checkoutDate,
        plannedCheckout.toIso8601String(),
        reason:
            'التمديد لا يستبدل checkout_date حتى لو كان قديماً — '
            'تغييره من شاشة تعديل بيانات النزيل فقط',
      );
    });

    test(
      'تسجيل المغادرة الفعلية يوقف النمو — الحساب يتوقف عند actual_checkout',
      () async {
        final booking = await seedActiveOpenBooking();

        // قبل المغادرة: الحساب حتى اللحظة (3 ليالٍ حتى beforeCutoff).
        final before = await calculator.calculateForBooking(
          booking,
          now: beforeCutoff,
        );
        expect(before.financialSummary.totalNights, 3);

        // تسجيل المغادرة الفعلية (المسار الشرعي للإيقاف).
        final checkoutMoment = DateTime(2024, 3, 3, 12);
        await bookings.update(
          booking.id,
          actualCheckout: checkoutMoment.toIso8601String(),
          status: 'مكتمل',
        );

        // بعد المغادرة: الحساب يتوقف عند وقت المغادرة حتى لو مرّ وقت أطول.
        final checkedOut = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(booking.id))).getSingle();
        final after = await calculator.calculateForBooking(
          checkedOut,
          now: afterCutoff,
        );
        expect(after.bookingActive, isFalse);
        expect(after.checkout, checkoutMoment);
        expect(
          after.financialSummary.totalNights,
          2,
          reason: 'ليلة 1 + ليلة 2 حتى 3 مارس 12:00 — لا نمو بعد المغادرة',
        );
      },
    );
  });
}
