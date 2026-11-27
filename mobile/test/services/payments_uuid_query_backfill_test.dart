// ============================================================================
//  Marina Hotel — توحيد الاستعلامات المالية بالـ UUID + الربط الرجعي
// ============================================================================
//  يغطي بنود الاختبار الإلزامي 8.3 من التدقيق:
//   ① دفعة مرتبطة بـ UUID فقط (بلا bookingLocalId — نمط سحب المزامنة
//      الموثق إنتاجياً 98/172 لغرفة 203) تدخل إجمالي قائمة الحجوزات
//      (watchTotalPaidForBooking) وتطابق قاعدة المحرك الموحد
//      (totalPaymentsForBooking) وشاشة التفاصيل.
//   ② الفلاتر الثلاثة (محذوفة/ملغاة/معلّقة) مطبقة في الاستعلام الموحد.
//   ③ صيغتا UUID (بشرطات/مطبّعة) كلتاهما محلولتان.
//   ④ الربط الرجعي (PaymentsBookingLinkBackfillService): يربط الدفعات ذات
//      bookingLocalId=NULL عبر UUID، ولا يلمس معرفاً موجوداً، idempotent.
//  لا mock — قاعدة SQLite حقيقية في الذاكرة.
// ============================================================================

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/enhanced_booking_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/payments_booking_link_backfill_service.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rate = 100.0;
  late AppDatabase db;
  late RoomsRepository roomsRepo;
  late BookingsRepository bookingsRepo;
  late PaymentsRepository paymentsRepo;

  final today = DateTime.now();
  DateTime day(int daysBack, [int hour = 15]) =>
      DateTime(today.year, today.month, today.day - daysBack, hour);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PaymentSessionContext.start(userId: 1, userName: 'اختبار');
    roomsRepo = RoomsRepository(db);
    bookingsRepo = BookingsRepository(db);
    paymentsRepo = PaymentsRepository(db);
    await roomsRepo.create(
      roomNumber: '101',
      type: 'عادية',
      price: rate,
      status: 'شاغرة',
    );
  });

  tearDown(() {
    PaymentSessionContext.clear();
    return db.close();
  });

  Future<Booking> fetchBooking(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  Future<int> seedBooking() => bookingsRepo.create(
        roomNumber: '101',
        guestName: 'طه فؤاد مسعد',
        guestPhone: '0500000000',
        guestNationality: 'يمني',
        checkinDate: day(4).toIso8601String(),
        status: 'نشط',
        expectedNights: 4,
      );

  /// إدراج دفعة كما تصل من السحب: UUID فقط بلا bookingLocalId.
  Future<void> insertUuidOnlyPayment(
    String bookingUuid,
    double amount, {
    String suffix = '',
    bool voided = false,
    bool pending = false,
    bool deleted = false,
    bool compactUuid = false,
  }) async {
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            localUuid: 'pay-$nowEpoch-${amount.round()}-$suffix',
            createdAt: nowEpoch,
            updatedAt: nowEpoch,
            lastModified: nowEpoch,
            amount: amount,
            paymentDate: Time.nowIso(),
            paymentMethod: 'نقدي',
            revenueType: 'room',
            bookingUuidCache: d.Value(
              compactUuid ? bookingUuid.replaceAll('-', '') : bookingUuid,
            ),
            roomNumber: const d.Value('101'),
            isVoided: d.Value(voided),
            isPendingBalance: d.Value(pending),
            deletedAt: d.Value(deleted ? nowEpoch : null),
          ),
        );
  }

  group('① watchTotalPaidForBooking يلتقط الدفعات ذات UUID فقط', () {
    test('تطابق تام مع قاعدة المحرك الموحد totalPaymentsForBooking',
        () async {
      final id = await seedBooking();
      final booking = await fetchBooking(id);

      // دفعة محلية عادية (بمعرف محلي) + دفعتان UUID فقط (نمط السحب)
      await paymentsRepo.create(
        amount: 50,
        paymentDate: Time.nowIso(),
        paymentMethod: 'نقدي',
        revenueType: 'room',
        bookingLocalId: id,
        roomNumber: '101',
      );
      await insertUuidOnlyPayment(booking.localUuid, 100, suffix: 'a');
      await insertUuidOnlyPayment(booking.localUuid, 200, suffix: 'b');

      final sqlTotal = await paymentsRepo
          .watchTotalPaidForBooking(id)
          .first;
      final engineTotal =
          await EnhancedBookingCalculationService(db).totalPaymentsForBooking(
        booking,
      );

      expect(sqlTotal, 350.0,
          reason: '50 محلية + 100 + 200 بالـ UUID — لا إخفاء بعد الآن');
      expect(sqlTotal, engineTotal.toDouble(),
          reason: 'نفس قاعدة المحرك حرفياً (localId OR uuid + الفلاتر)');
    });

    test('③ الصيغة المطبّعة (بلا شرطات) محلولة أيضاً', () async {
      final id = await seedBooking();
      final booking = await fetchBooking(id);
      await insertUuidOnlyPayment(
        booking.localUuid,
        75,
        suffix: 'compact',
        compactUuid: true,
      );
      final total = await paymentsRepo.watchTotalPaidForBooking(id).first;
      expect(total, 75.0);
    });
  });

  group('② الفلاتر الثلاثة في الاستعلام الموحد', () {
    test('الملغاة والمعلّقة والمحذوفة لا تدخل الإجمالي', () async {
      final id = await seedBooking();
      final booking = await fetchBooking(id);
      await insertUuidOnlyPayment(booking.localUuid, 100, suffix: 'ok');
      await insertUuidOnlyPayment(booking.localUuid, 999,
          suffix: 'voided', voided: true);
      await insertUuidOnlyPayment(booking.localUuid, 888,
          suffix: 'pending', pending: true);
      await insertUuidOnlyPayment(booking.localUuid, 777,
          suffix: 'deleted', deleted: true);

      final total = await paymentsRepo.watchTotalPaidForBooking(id).first;
      expect(total, 100.0);
    });
  });

  group('④ الربط الرجعي PaymentsBookingLinkBackfillService', () {
    test('يربط الدفعات غير المرتبطة عبر UUID ولا يلمس المعرفات الموجودة',
        () async {
      final id = await seedBooking();
      final booking = await fetchBooking(id);

      // دفعتان غير مرتبطتين محلياً (UUID فقط) + واحدة مرتبطة أصلاً
      await insertUuidOnlyPayment(booking.localUuid, 100, suffix: 'x');
      await insertUuidOnlyPayment(booking.localUuid, 200, suffix: 'y');
      final linkedPaymentId = await paymentsRepo.create(
        amount: 50,
        paymentDate: Time.nowIso(),
        paymentMethod: 'نقدي',
        revenueType: 'room',
        bookingLocalId: id,
        roomNumber: '101',
      );

      final linked = await paymentsRepo.dao.getById(linkedPaymentId);
      final linkedUuidBefore = linked!.localUuid;

      final linkedCount =
          await PaymentsBookingLinkBackfillService.instance.backfillPayments(
        db,
      );
      expect(linkedCount, 2, reason: 'دفعتا UUID فقط هما المرشحتان للربط');

      // الدفعتان ربطتا بالحجز الصحيح
      final unlinked = await (db.select(db.payments)
            ..where((p) => p.bookingLocalId.equals(id)))
          .get();
      expect(unlinked.length, 3);

      // الدفعة المرتبطة أصلاً لم تُلمس (نفس المعرف والـUUID)
      final after = await paymentsRepo.dao.getById(linkedPaymentId);
      expect(after!.localUuid, linkedUuidBefore);
      expect(after.bookingLocalId, id);

      // idempotent: تشغيل ثانٍ لا يغيّر شيئاً
      final second =
          await PaymentsBookingLinkBackfillService.instance.backfillPayments(
        db,
      );
      expect(second, 0);
    });

    test('صيغة UUID المطبّعة مربوطة أيضاً', () async {
      final id = await seedBooking();
      final booking = await fetchBooking(id);
      await insertUuidOnlyPayment(
        booking.localUuid,
        60,
        suffix: 'compact-bf',
        compactUuid: true,
      );
      final count =
          await PaymentsBookingLinkBackfillService.instance.backfillPayments(
        db,
      );
      expect(count, 1);
      final rows = await (db.select(db.payments)
            ..where((p) => p.bookingLocalId.equals(id)))
          .get();
      expect(rows.single.amount, 60);
    });
  });
}
