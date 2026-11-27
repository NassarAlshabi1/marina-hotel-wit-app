// ============================================================================
//  Marina Hotel — مسارات الاستعادة لا تقصّ الرصيد الدائن ولا تكتب lastModified
// ============================================================================
//  يغطي (بناء على مراجعة 2026-11-23 وتدقيق 4.2 + إصلاح هذا الالتزام):
//   ① المسار النشط (_recalculateBookingFinancials): حجز مدفوع زيادة يحفظ
//      المتبقي سالباً — لا تصفير.
//   ② مسار إعادة البناء بعد الاستعادة (_rebuildBookingStructures —
//      المعالَج المكتمل): نفس الثابت — المتبقي السالف يُكتب كما هو
//      (كان يُصفَّر هنا فقط: `if (remaining < 0) remaining = 0`).
//   ③ لا كتابة lastModified في أي مسار اشتقاق (وإلا بدت نتائج إعادة
//      الحساب تعديلات مستخدم قابلة للرفع).
//   ④ عند غياب الليالي المخزنة يُشتق المستحق بالمحرك الموحد (يشمل
//      تعديلات الأسعار) — لا بتقدير «السعر الحالي × الليالي».
//  لا mock — قاعدة SQLite حقيقية في الذاكرة.
// ============================================================================

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/enhanced_booking_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/restore_fix_service.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rate = 100.0;
  late AppDatabase db;
  late RoomsRepository roomsRepo;
  late BookingsRepository bookingsRepo;
  late RestoreFixService restoreFix;

  final today = DateTime.now();
  DateTime day(int daysBack, [int hour = 15]) =>
      DateTime(today.year, today.month, today.day - daysBack, hour);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    roomsRepo = RoomsRepository(db);
    bookingsRepo = BookingsRepository(db);
    restoreFix = RestoreFixService(db);
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

  Future<Booking> fetchBooking(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  Future<void> insertRawPayment(
    int bookingId,
    String bookingUuid,
    double amount,
  ) async {
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            localUuid: 'pay-$nowEpoch-${amount.round()}-$bookingId',
            createdAt: nowEpoch,
            updatedAt: nowEpoch,
            lastModified: nowEpoch,
            amount: amount,
            paymentDate: Time.nowIso(),
            paymentMethod: 'نقدي',
            revenueType: 'room',
            bookingLocalId: d.Value(bookingId),
            bookingUuidCache: d.Value(bookingUuid),
            roomNumber: const d.Value('101'),
          ),
        );
  }

  test(
      '①+②+③ الحجز النشط والمكتمل المدفوعان زيادة يحفظان رصيداً دائناً سالباً '
      'ودون كتابة lastModified', () async {
    // ── حجز نشط: 3 ليالٍ حتى الآن × 100 = 300 مستحق، مدفوع 500 (دائن 200)
    final activeId = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'نزيل نشط دائن',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: day(3).toIso8601String(),
      status: 'نشط',
      expectedNights: 3,
    );
    final activeBooking = await fetchBooking(activeId);
    final activeLastModifiedBefore = activeBooking.lastModified;
    await insertRawPayment(activeId, activeBooking.localUuid, 500);

    // ── حجز مكتمل: 5 ليالٍ × 100 = 500 مستحق، مدفوع 600 (دائن 100)
    // (يمر بمسار إعادة البناء — القصّ الذي رصدته المراجعة)
    final doneId = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'نزيل مكتمل دائن',
      guestPhone: '0500000001',
      guestNationality: 'يمني',
      checkinDate: day(8).toIso8601String(),
      checkoutDate: day(3, 12).toIso8601String(),
      status: 'مكتمل',
      expectedNights: 5,
      actualCheckout: day(3, 12).toIso8601String(),
    );
    final doneBooking = await fetchBooking(doneId);
    final doneLastModifiedBefore = doneBooking.lastModified;
    await insertRawPayment(doneId, doneBooking.localUuid, 600);

    await restoreFix.runAutoFixAfterRestore();

    // ① المسار النشط: −200 محفوظة لا مصفّرة
    final activeAfter = await fetchBooking(activeId);
    expect(activeAfter.totalPaidCached, 500.0);
    expect(activeAfter.totalDueCached, greaterThan(0));
    expect(
      activeAfter.remainingBalanceCached,
      activeAfter.totalDueCached - 500.0,
      reason: 'الثابت المالي remaining = due − paid بلا قصّ',
    );
    expect(activeAfter.remainingBalanceCached, lessThan(0),
        reason: 'الدائن يظهر سالباً في مسار الاستعادة النشط');

    // ② مسار إعادة البناء (المكتمل): المتبقي السالف يُكتب كما هو
    final doneAfter = await fetchBooking(doneId);
    expect(doneAfter.totalPaidCached, 600.0);
    expect(
      doneAfter.remainingBalanceCached,
      doneAfter.totalDueCached - 600.0,
      reason: 'كان هذا المسار يصفّر السالب (`if (remaining < 0) 0`)',
    );
    expect(doneAfter.remainingBalanceCached, lessThan(0),
        reason: 'دائن المكتمل لم يعد يُقصّ في مسار إعادة البناء');

    // ③ لا كتابة lastModified في مسارات الاشتقاق
    expect(activeAfter.lastModified, activeLastModifiedBefore,
        reason: 'إعادة الحساب ليست تعديل مستخدم ولا تُرفع كذلك');
    expect(doneAfter.lastModified, doneLastModifiedBefore);
  });

  test('④ عند غياب الليالي: الاشتقاق بالمحرك الموحد (يشمل التعديلات)', () async {
    // حجز نشط بلا ليالي مخزنة، سعر الغرفة 100، خصم ليلي 20 من أول ليلة
    final id = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'نزيل تقدير المحرك',
      guestPhone: '0500000002',
      guestNationality: 'يمني',
      checkinDate: day(4).toIso8601String(),
      status: 'نشط',
      expectedNights: 4,
    );
    final booking = await fetchBooking(id);
    // سيناريو «غياب الليالي المخزنة» (فقدان جهاز/استعادة): نزيل ما ولّده
    // الإنشاء التلقائي كي يشتق المستحق من المحرك (السعر + التعديلات).
    await (db.delete(
      db.bookingNights,
    )..where((n) => n.bookingLocalId.equals(id))).go();
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.into(db.bookingPriceAdjustments).insert(
          BookingPriceAdjustmentsCompanion.insert(
            localUuid: 'adj-engine-$nowEpoch',
            bookingLocalUuid: booking.localUuid,
            createdAt: nowEpoch,
            updatedAt: nowEpoch,
            lastModified: nowEpoch,
            bookingLocalId: d.Value(id),
            roomNumber: const d.Value('101'),
            amount: const d.Value(20.0),
            effectiveHotelDay: booking.checkinDate.substring(0, 10),
            reason: const d.Value('خصم ليلي موثق للاختبار'),
            adjustmentType: const d.Value(0),
            adjustmentMode: const d.Value('per_night'),
          ),
        );
    await insertRawPayment(id, booking.localUuid, 320);

    // المرجع: المحرك الموحد نفسه
    final engineDue = await EnhancedBookingCalculationService(db)
        .calculateFinancials(booking);

    await restoreFix.runAutoFixAfterRestore();
    final after = await fetchBooking(id);

    expect(after.totalDueCached, engineDue.totalDue.toDouble(),
        reason: 'المستحق من المحرك الموحد (يشمل الخصم الليلي 20) — '
            'لا من تقدير السعر الحالي × الليالي');
    // حتمي عبر أوقات التشغيل: كل ليلة = 100 − 20 = 80 بعد تطبيق الخصم
    expect(engineDue.totalNights, greaterThanOrEqualTo(4));
    expect(engineDue.totalDue, engineDue.totalNights * 80,
        reason: 'الخصم الليلي مطبق على كل ليلة (100−20=80) — '
            'لا تقدير السعر الحالي × الليالي');
    expect(after.remainingBalanceCached, engineDue.totalDue - 320.0);
    expect(after.lastModified, booking.lastModified,
        reason: 'لا lastModified في مسار الاشتقاق');
  });
}
