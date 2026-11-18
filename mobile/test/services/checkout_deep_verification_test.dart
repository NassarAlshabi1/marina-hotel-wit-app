// ============================================================================
//  Marina Hotel — Deep Checkout Verification (production-path audit)
// ============================================================================
//  يتحقق من مسار تسجيل مغادرة النزيل عبر طبقات الإنتاج الحقيقية
//  (BookingsRepository / PaymentsRepository / BookingDerivedFieldsService /
//  EnhancedBookingCalculationService) — لا mock، نفس الكود الذي يعمل في
//  التطبيق عند ضغط «تسجيل المغادرة».
//
//  الفروق المدروسة:
//    C1: مغادرة عادية — قصّ الليالي + إعادة حساب الخزائن + outbox.
//    C2: مغادرة مبكرة + دفعة مردود سالبة — صحة الرياضيات المالية.
//    C3: حرس المغادرة المزدوجة (إصلاح P1) — محاولة مغادرة ثانية بوقت
//        أحدث تُرفض بStateError من BookingsRepository.update ولا تتغير
//        الحالة (الليالي/الفاتورة/actualCheckout)، والمسارات الشرعية
//        (booking_edit بنمط null وidempotent بنفس القيمة) لا تتأثر.
//    C4: تحرير الغرفة عبر refreshAllRoomOccupancy (مسار booking_checkout_screen).
//    C5: طبقة السحب — BookingsAdapter.fromJson (Source.appwrite) تتجاهل
//        الحقول المالية المخبأة (توثيق تضارب الأجهزة).
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/bookings_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/adapters/resolve_result.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const double rate = 100.0; // سعر الليلة
  late AppDatabase db;
  late BookingsRepository bookingsRepo;
  late PaymentsRepository paymentsRepo;
  late RoomsRepository roomsRepo;
  late OutboxDao outboxDao;

  // ─── خط زمني حتمي (كل التواريخ في الماضي العميق، مستقلة عن ساعة الجهاز) ───
  // الدخول بعد حد 14:01 حتى يبدأ يوم الفندق من يوم الدخول نفسه.
  // nightsWithCutoff = floor((checkout − بداية يوم فندق الدخول)/24h) + 1.
  final today = DateTime.now();
  DateTime day(int daysBack, [int hour = 15, int minute = 0]) =>
      DateTime(today.year, today.month, today.day - daysBack, hour, minute);

  final checkin = day(10); // d-10 @15:00 → بداية يوم الفندق d-10@14:01
  final plannedCheckout = day(6); // d-6 @15:00 → 5 ليالٍ مخططة
  final firstCheckout = day(8); // d-8 @15:00 → 3 ليالٍ فعلية
  final secondCheckout = day(7); // d-7 @15:00 → 4 ليالٍ (مغادرة مزدوجة)

  Future<int> seedBooking() => bookingsRepo.create(
    roomNumber: '101',
    guestName: 'أحمد محمد',
    guestPhone: '0501234567',
    guestNationality: 'يمني',
    checkinDate: checkin.toIso8601String(),
    checkoutDate: plannedCheckout.toIso8601String(),
    status: 'نشط',
    expectedNights: 5,
  );

  /// ليالي الحجز الحية من DB (غير المحذوفة).
  Future<List<BookingNight>> liveNights(int bookingId) =>
      (db.select(db.bookingNights)
            ..where((n) => n.bookingLocalId.equals(bookingId))
            ..where((n) => n.deletedAt.isNull())
            ..orderBy([(n) => d.OrderingTerm.asc(n.sequence)]))
          .get();

  /// عدد عناصر outbox المعلقة لكيان معيّن (قراءة مباشرة بلا تغيير حالة).
  Future<int> pendingOutbox(String entity) async {
    final rows =
        await (db.select(db.outbox)
              ..where((t) => t.entity.equals(entity))
              ..where((t) => t.processingStatus.equals('pending')))
            .get();
    return rows.length;
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookingsRepo = BookingsRepository(db);
    paymentsRepo = PaymentsRepository(db);
    roomsRepo = RoomsRepository(db);
    outboxDao = OutboxDao(db);

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

  group('C1 — مغادرة عادية عبر BookingsRepository (مسار الإنتاج)', () {
    test(
      'تقصّ الليالي إلى actualNights وتعيد حساب الخزائن وتُدرج outbox',
      () async {
        final bookingId = await seedBooking();

        // دفعة تغطي 5 ليالٍ.
        await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: rate * 5,
          paymentDate: checkin.toIso8601String(),
          paymentMethod: 'نقدي',
          revenueType: 'room',
        );

        // قبل المغادرة: الحجز نشط → ليالي ديناميكية تنمو مع الوقت الحقيقي.
        final expectedBefore = Time.nightsWithCutoff(
          checkin,
          checkout: DateTime.now(),
        );
        final before = await liveNights(bookingId);
        expect(
          before.length,
          expectedBefore,
          reason: 'حجز نشط: الليالي تنمو ديناميكياً حتى اللحظة الحالية',
        );

        // ⬇️ نفس استدعاء _processCheckout الإنتاجي.
        await bookingsRepo.update(
          bookingId,
          status: 'مكتمل',
          actualCheckout: firstCheckout.toIso8601String(),
          calculatedNights: 3,
        );

        final booking = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(bookingId))).getSingle();

        // 1) الحالة والتواريخ.
        expect(booking.status, 'مكتمل');
        expect(booking.actualCheckout, isNotNull);

        // 2) ⭐ القصّ: الليالي تنحصر عند وقت المغادرة الفعلي (3 لا 5).
        final after = await liveNights(bookingId);
        expect(
          after.length,
          3,
          reason: 'المغادرة تُقصّ الليالي غير المستخدمة عند actualCheckout',
        );

        // 3) ⭐ الخزائن المالية أُعيد حسابها من المسار المقطوع.
        expect(booking.totalDueCached, rate * 3);
        expect(booking.totalPaidCached, rate * 5);
        expect(
          booking.remainingBalanceCached,
          0.0,
          reason: 'مدفوع 5×rate مقابل مستحق 3×rate → لا متبقٍ',
        );
        expect(booking.isFullyPaid, true);
        expect(booking.calculatedNights, 3);

        // 4) ⭐ outbox: تحديث الحجز قابل للرفع (سطر المزامنة).
        expect(
          await pendingOutbox('bookings'),
          greaterThanOrEqualTo(1),
          reason: 'المغادرة يجب أن تُدرج تحديث الحجز في outbox للرفع',
        );
      },
    );
  });

  group('C2 — مغادرة مبكرة + مردود سالب (مسار _processEarlyCheckout)', () {
    test(
      'دفعة سالبة مقبولة والرياضيات تُغلق الحساب على قيمته الفعلية',
      () async {
        final bookingId = await seedBooking();

        // الضيف دفع كامل الإقامة المخططة مقدماً.
        await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: rate * 5,
          paymentDate: checkin.toIso8601String(),
          paymentMethod: 'نقدي',
          revenueType: 'room',
        );

        // ⬇️ تسلسل _processEarlyCheckout الإنتاجي:
        // (1) تسجيل المغادرة بالليالي الفعلية (3).
        await bookingsRepo.update(
          bookingId,
          status: 'مكتمل',
          actualCheckout: firstCheckout.toIso8601String(),
          calculatedNights: 3,
        );

        // (2) المردود: paid(500) - actualCost(300) = 200 → دفعة سالبة -200.
        final refund = (rate * 5) - (rate * 3);
        final refundPaymentId = await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: -refund,
          paymentDate: firstCheckout.toIso8601String(),
          notes: 'مردود مغادرة مبكرة - 2 ليالي غير مستخدمة',
          paymentMethod: 'نقدي',
          revenueType: 'room',
        );
        expect(
          refundPaymentId,
          greaterThan(0),
          reason: 'PaymentsRepository.create يجب أن يقبل مبالغ سالبة (المردود)',
        );

        // ⭐ الحساب الختامي: مدفوع صافٍ 300 = مستحق 300.
        final booking = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(bookingId))).getSingle();
        expect(booking.totalDueCached, rate * 3);
        expect(
          booking.totalPaidCached,
          rate * 3,
          reason: '500 - 200 مردود = 300',
        );
        expect(booking.remainingBalanceCached, 0.0);
        expect(booking.isFullyPaid, true);

        // المدفوعات الفعلية المسجلة: دفعة موجبة + مردود سالب.
        final payments = await (db.select(
          db.payments,
        )..where((p) => p.bookingLocalId.equals(bookingId))).get();
        expect(payments.length, 2);
        expect(payments.map((p) => p.amount).contains(-refund), isTrue);
      },
    );
  });

  group('C3 — حرس المغادرة المزدوجة (تحقق الإصلاح P1)', () {
    test(
      'محاولة مغادرة ثانية بوقت أحدث تُرفض بStateError والحالة لا تتغير',
      () async {
        final bookingId = await seedBooking();

        // الضيف سدد قيمة 3 ليالٍ بالضبط (الفاتورة بعد المغادرة الأولى = صفر).
        await paymentsRepo.create(
          bookingLocalId: bookingId,
          roomNumber: '101',
          amount: rate * 3,
          paymentDate: checkin.toIso8601String(),
          paymentMethod: 'نقدي',
          revenueType: 'room',
        );

        // مغادرة أولى (3 ليالٍ فعلية) — كاستدعاء _processCheckout الإنتاجي.
        await bookingsRepo.update(
          bookingId,
          status: 'مكتمل',
          actualCheckout: firstCheckout.toIso8601String(),
          calculatedNights: 3,
        );

        final afterFirst = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(bookingId))).getSingle();
        expect(afterFirst.remainingBalanceCached, 0.0);
        expect(afterFirst.isFullyPaid, true);

        // ⬇️ مغادرة ثانية بوقت أحدث — كانت تمدد الليالي وتضخّم الفاتورة؛
        // الآن يرفضها حرس BookingsRepository.update (إصلاح P1).
        await expectLater(
          bookingsRepo.update(
            bookingId,
            status: 'مكتمل',
            actualCheckout: secondCheckout.toIso8601String(),
            calculatedNights: 4,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('لا يمكن تسجيل المغادرة مرتين'),
            ),
          ),
        );

        // ⭐ الحالة لم تتغير قط: الليالي 3، الفاتورة مغلقة، actualCheckout الأصلي.
        final afterRejected = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(bookingId))).getSingle();
        expect(DateTime.parse(afterRejected.actualCheckout!), firstCheckout);
        expect(
          (await liveNights(bookingId)).length,
          3,
          reason: 'الرفض يحمي الليالي المقصوصة من التمدد',
        );
        expect(afterRejected.totalDueCached, rate * 3);
        expect(
          afterRejected.remainingBalanceCached,
          0.0,
          reason: 'الفاتورة المغلقة لا تعود «متبقية» بعد الرفض',
        );
        expect(afterRejected.isFullyPaid, true);
      },
    );

    test(
      'المسارات الشرعية لا تتأثر بالحرس (booking_edit وidempotent)',
      () async {
        final bookingId = await seedBooking();

        // مغادرة أولى.
        await bookingsRepo.update(
          bookingId,
          status: 'مكتمل',
          actualCheckout: firstCheckout.toIso8601String(),
          calculatedNights: 3,
        );

        // (أ) نمط booking_edit: تحديث حقول أخرى مع غياب actualCheckout
        // (null = لا تغيير) — لا يُرفض ولا يمحو المغادرة المسجلة.
        await bookingsRepo.update(
          bookingId,
          guestPhone: '0509998887',
          notes: 'تعديل إداري بعد المغادرة',
          status: 'مكتمل',
        );
        final afterEdit = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(bookingId))).getSingle();
        expect(
          DateTime.parse(afterEdit.actualCheckout!),
          firstCheckout,
          reason: 'تحديث بلا actualCheckout لا يمحو المغادرة',
        );
        expect(afterEdit.guestPhone, '0509998887');

        // (ب) إعادة نفس القيمة (idempotent) — مسموحة ولا ترفض.
        await bookingsRepo.update(
          bookingId,
          status: 'مكتمل',
          actualCheckout: firstCheckout.toIso8601String(),
          calculatedNights: 3,
        );
        final afterIdempotent = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(bookingId))).getSingle();
        expect(DateTime.parse(afterIdempotent.actualCheckout!), firstCheckout);
        expect((await liveNights(bookingId)).length, 3);
      },
    );
  });

  group(
    'C4 — تحرير الغرفة عبر refreshAllRoomOccupancy (مسار checkout screen)',
    () {
      test(
        'الغرفة المحجوزة تتحول إلى شاغرة بعد مغادرة حجزها النشط الوحيد',
        () async {
          final bookingId = await seedBooking();

          // الغرفة محجوزة (كما يحدث عند تسجيل الدخول).
          final room = await roomsRepo.watchByNumber('101').first;
          await roomsRepo.update(room!.id, status: 'محجوزة');
          expect(
            (await roomsRepo.watchByNumber('101').first)!.status,
            'محجوزة',
          );

          // ⬇️ نفس تسلسل BookingCheckoutScreen._completeCheckout.
          await bookingsRepo.update(
            bookingId,
            status: 'مكتمل',
            actualCheckout: firstCheckout.toIso8601String(),
            calculatedNights: 3,
          );
          await roomsRepo.refreshAllRoomOccupancy();

          final updated = await roomsRepo.watchByNumber('101').first;
          expect(updated!.status, 'شاغرة');
        },
      );
    },
  );

  group('C5 — طبقة السحب: الحقول المالية المخبأة لا تعبر الأجهزة', () {
    test(
      'BookingsAdapter.fromJson (appwrite) يتجاهل الخزائن المالية',
      () async {
        final adapter = BookingsAdapter(IdResolver(db));
        // حمولة بعيدة كما تصل من Appwrite لجهاز آخر بعد المغادرة.
        final json = <String, dynamic>{
          'localUuid': 'remote-completed-uuid',
          'roomNumber': '101',
          'guestName': 'أحمد',
          'guestPhone': '0501234567',
          'guestNationality': 'يمني',
          'checkinDate': DateTime.now().toIso8601String(),
          'status': 'مكتمل',
          'actualCheckout': DateTime.now().toIso8601String(),
          'expectedNights': 5,
          'calculatedNights': 3,
          'totalDueCached': 300.0,
          'totalPaidCached': 300.0,
          'remainingBalanceCached': 0.0,
          'isFullyPaid': true,
          'lastModified': 1,
        };
        final refs = ResolveResult(bookingLocalId: null, lastModifiedEpoch: 1);
        final companion = adapter.fromJson(
          json,
          src: Source.appwrite,
          refs: refs,
        );

        // ⭐ توثيق السلوك المقصود (bookings_adapter.dart:190-193):
        // القيم تُحمل لكن الحقول المالية تُترك غائبة → لا تُخزَّن محلياً
        // → تعتمد الأجهزة الأخرى على refreshForBookingId، وهو متخطَّى
        // للحجوزات المكتملة (appwrite_sync_manager.dart:2259-2276).
        expect(companion.totalDueCached, const d.Value<double>.absent());
        expect(companion.totalPaidCached, const d.Value<double>.absent());
        expect(
          companion.remainingBalanceCached,
          const d.Value<double>.absent(),
        );
        expect(companion.isFullyPaid, const d.Value<bool>.absent());
        // في المقابل calculatedNights و actualCheckout و status يعبرون.
        expect(companion.calculatedNights, const d.Value(3));
        expect(companion.status, const d.Value('مكتمل'));
        expect(companion.actualCheckout, isNotNull);
      },
    );
  });
}
