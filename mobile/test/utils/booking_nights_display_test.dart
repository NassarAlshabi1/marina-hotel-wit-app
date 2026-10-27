// ============================================================================
//  Marina Hotel — Bookings List Nights Display (production-path tests)
// ============================================================================
//  إثبات إصلاح عرض الليالي في قائمة الحجوزات: العدد المعروض ينقطع عند
//  actualCheckout المسجّل ولا يتراكم حتى «الآن» بعد مغادرة الضيف فعلياً.
//
//    L1: العيب المرصود (legacy): مغادرة فعلية + لا مخطط + expectedNights=0
//        → القيم مجمدة عند المغادرة — كانت قبل الإصلاح تتراكم حتى «الآن».
//    L2: ثبات القيم بتقدم «الآن» بعد المغادرة (ثلاث لحظات متباعدة).
//    L3: توازن السلوك القائم — كل الفروع الأخرى بلا انحراف.
//    L4: مغادرة مستقبلية (شذوذ بيانات) → القصّ إلى «الآن» كشاشة الدفع.
//    L5: حدّ اليوم الفندقي بالثانية (14:00:59 / 14:01:00) عبر مسار القائمة.
// ============================================================================

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/utils/booking_nights_display.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── خط زمني حتمي ثابت (مستقل تماماً عن ساعة الجهاز) ───
  // دخول 2024-03-01 15:00 (بعد حد 14:01) → بداية يوم الفندق 03-01 14:01.
  // plannedCheckout = 2024-03-02 14:00 → ليلة مخططة واحدة (قبل الحد).
  // actualCheckout  = 2024-03-04 10:00 → 3 ليالٍ محسومة.
  // الآن (A/B/C)    = 2024-03-10 15:00 / 03-20 09:00 / 04-05 12:00.
  final checkin = DateTime(2024, 3, 1, 15);
  final plannedCheckout = DateTime(2024, 3, 2, 14);
  final actualCheckout = DateTime(2024, 3, 4, 10);
  final nowA = DateTime(2024, 3, 10, 15);
  final nowB = DateTime(2024, 3, 20, 9);
  final nowC = DateTime(2024, 4, 5, 12);

  /// نفس ما تفعله شاشة القائمة حرفياً: تحليل حقول الحجز من قاعدة
  /// البيانات ثم نداء القاعدة الموحّدة BookingNightsDisplay.forList.
  ({int expectedNights, int actualNights}) listNights(
    Booking booking, {
    DateTime? now,
  }) => BookingNightsDisplay.forList(
    status: booking.status,
    storedExpectedNights: booking.expectedNights,
    checkin: DateTime.tryParse(booking.checkinDate),
    plannedCheckout: booking.checkoutDate != null
        ? DateTime.tryParse(booking.checkoutDate!)
        : null,
    actualCheckout: booking.actualCheckout != null
        ? DateTime.tryParse(booking.actualCheckout!)
        : null,
    now: now,
  );

  late AppDatabase db;
  late BookingsRepository bookingsRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookingsRepo = BookingsRepository(db);
    await RoomsRepository(
      db,
    ).create(roomNumber: '101', type: 'عادية', price: 100, status: 'شاغرة');
  });

  tearDown(() async {
    await db.close();
  });

  Future<Booking> fetchBooking(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  /// حجز legacy كما يصل من مزامنة Appwrite: لا checkoutDate مخطط،
  /// expectedNights=0 (تبقى 0 — خدمة الحقول المشتقة تُبقيها للحجوزات
  /// المغلقة)، ومغادرة فعلية مسجّلة عند [actual].
  Future<Booking> seedLegacyCheckedOut({DateTime? actual}) async {
    final id = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'ضيف legacy بلا تاريخ خروج مخطط',
      guestPhone: '0500000003',
      guestNationality: 'يمني',
      checkinDate: checkin.toIso8601String(),
      status: 'مكتمل',
      actualCheckout: (actual ?? actualCheckout).toIso8601String(),
      expectedNights: 0,
    );
    final booking = await fetchBooking(id);
    // فرضية العيب: لا مخطط، والقيمة المحفوظة صفر.
    expect(booking.checkoutDate, isNull, reason: 'فرضية العيب: لا مخطط');
    expect(booking.expectedNights, 0, reason: 'فرضية العيب: القيمة المحفوظة 0');
    return booking;
  }

  group('L1 — العيب المرصود: مغادرة فعلية بلا مخطط وexpectedNights=0', () {
    test('العرض مجمد عند المغادرة الفعلية — لا تراكم حتى «الآن»', () async {
      // شاهد على حجم العيب: الحساب حتى «الآن» كان سيعطي 10 ليالٍ
      // لضيف غادر فعلياً في 03-04.
      expect(Time.nightsWithCutoff(checkin, checkout: nowA), 10);

      final booking = await seedLegacyCheckedOut();
      final nights = listNights(booking, now: nowA);

      // قبل الإصلاح: fallback المتوقعة كان يمرّر مخططاً فارغاً إلى
      // nightsWithCutoff فيُحسب حتى «الآن» = 10. بعد الإصلاح:
      // النهاية = المغادرة الفعلية المسجّلة = 3 ليالٍ.
      expect(
        nights.expectedNights,
        3,
        reason: 'fallback المتوقعة → حتى actualCheckout (لا حتى now=10)',
      );
      expect(
        nights.actualNights,
        3,
        reason: 'الفعلي حتى actualCheckout المسجّل',
      );
    });
  });

  group('L2 — بعد المغادرة تبقى القيم ثابتة مهما تقدّم «الآن»', () {
    test('نفس الليالي عبر ثلاث لحظات متباعدة (A/B/C)', () async {
      final booking = await seedLegacyCheckedOut();

      for (final moment in [nowA, nowB, nowC]) {
        final nights = listNights(booking, now: moment);
        expect(nights.expectedNights, 3, reason: 'المتوقعة عند $moment');
        expect(nights.actualNights, 3, reason: 'الفعلي عند $moment');
      }
    });
  });

  group('L3 — توازن السلوك القائم: كل الفروع الأخرى بلا انحراف', () {
    test(
      'مخطط + قيمة محفوظة (>0) + مغادرة → (المحفوظة، حتى المغادرة)',
      () async {
        final id = await bookingsRepo.create(
          roomNumber: '101',
          guestName: 'ضيف مخطط كامل',
          guestPhone: '0500000004',
          guestNationality: 'يمني',
          checkinDate: checkin.toIso8601String(),
          checkoutDate: plannedCheckout.toIso8601String(),
          status: 'مكتمل',
          actualCheckout: actualCheckout.toIso8601String(),
          expectedNights: 5,
        );
        final nights = listNights(await fetchBooking(id), now: nowA);

        expect(
          nights.expectedNights,
          5,
          reason: 'القيمة المحفوظة لها الأولوية',
        );
        expect(nights.actualNights, 3, reason: 'الفعلي حتى المغادرة');
      },
    );

    test(
      'مخطط + expectedNights=0 + مغادرة → (حتى المخطط، حتى المغادرة)',
      () async {
        final id = await bookingsRepo.create(
          roomNumber: '101',
          guestName: 'ضيف مخطط بلا قيمة محفوظة',
          guestPhone: '0500000005',
          guestNationality: 'يمني',
          checkinDate: checkin.toIso8601String(),
          checkoutDate: plannedCheckout.toIso8601String(),
          status: 'مكتمل',
          actualCheckout: actualCheckout.toIso8601String(),
          expectedNights: 0,
        );
        final nights = listNights(await fetchBooking(id), now: nowA);

        // 03-01 15:00 → 03-02 14:00 = ليلة واحدة (قبل حد 14:01).
        expect(nights.expectedNights, 1, reason: 'fallback → المخطط');
        expect(nights.actualNights, 3, reason: 'الفعلي حتى المغادرة');
      },
    );

    test('نشط بلا مغادرة + مخطط مضى → (المحفوظة، ديناميكي حتى «الآن»)', () {
      final nights = BookingNightsDisplay.forList(
        status: 'نشط',
        storedExpectedNights: 2,
        checkin: checkin,
        plannedCheckout: plannedCheckout,
        actualCheckout: null,
        now: nowA,
      );

      expect(nights.expectedNights, 2);
      expect(
        nights.actualNights,
        10,
        reason: 'المخطط المضى لا يوقف التراكم الديناميكي',
      );
    });

    test('نشط مفتوح بلا أي موعد → ديناميكي حتى «الآن» للقيمتين', () {
      final nights = BookingNightsDisplay.forList(
        status: 'نشط',
        storedExpectedNights: 0,
        checkin: checkin,
        plannedCheckout: null,
        actualCheckout: null,
        now: nowA,
      );

      expect(nights.expectedNights, 10);
      expect(nights.actualNights, 10);
    });

    test('ملغي بلا مغادرة + مخطط → العرض عند المخطط (سلوك قائم)', () {
      final nights = BookingNightsDisplay.forList(
        status: 'ملغي',
        storedExpectedNights: 0,
        checkin: checkin,
        plannedCheckout: plannedCheckout,
        actualCheckout: null,
        now: nowA,
      );

      expect(nights.expectedNights, 1, reason: 'fallback → المخطط');
      expect(nights.actualNights, 1, reason: 'غير نشط → نهاية العرض المخطط');
    });

    test('دخول غير قابل للتحليل → القيمة المحفوظة أو 1 (سلوك قائم)', () {
      final a = BookingNightsDisplay.forList(
        status: 'مكتمل',
        storedExpectedNights: 0,
        checkin: DateTime.tryParse('garbage'),
        plannedCheckout: null,
        actualCheckout: actualCheckout,
        now: nowA,
      );
      expect(a.expectedNights, 1);
      expect(a.actualNights, 1);

      final b = BookingNightsDisplay.forList(
        status: 'مكتمل',
        storedExpectedNights: 7,
        checkin: DateTime.tryParse('garbage'),
        plannedCheckout: null,
        actualCheckout: actualCheckout,
        now: nowA,
      );
      expect(b.expectedNights, 7);
      expect(b.actualNights, 7);
    });
  });

  group('L4 — مغادرة مستقبلية (شذوذ بيانات): القصّ إلى «الآن»', () {
    test('الفعلي لا يتجاوز «الآن» — نفس سياسة شاشة الدفع', () async {
      // مغادرة «مسجّلة» 03-20 10:00 وهي مستقبلية مقارنة بـ nowA=03-10.
      final booking = await seedLegacyCheckedOut(
        actual: DateTime(2024, 3, 20, 10),
      );
      final nights = listNights(booking, now: nowA);

      // الفعلي مقصوص إلى nowA → 10 ليالٍ (لا 19 حتى المغادرة المسجلة).
      expect(
        nights.actualNights,
        10,
        reason: 'المغادرة المستقبلية شذوذ بيانات → القصّ إلى «الآن»',
      );
      // المتوقعة تعكس نهاية الإقامة المسجّلة (لا مخطط ولا قيمة محفوظة).
      expect(nights.expectedNights, 19);
    });

    test('مع مخطط وقيمة محفوظة → (المحفوظة، مقصوص إلى «الآن»)', () {
      final nights = BookingNightsDisplay.forList(
        status: 'مكتمل',
        storedExpectedNights: 5,
        checkin: checkin,
        plannedCheckout: plannedCheckout,
        actualCheckout: DateTime(2024, 3, 20, 10),
        now: nowA,
      );

      expect(nights.expectedNights, 5);
      expect(nights.actualNights, 10, reason: 'القصّ إلى «الآن»');
    });
  });

  group('L5 — حدّ اليوم الفندقي بالثانية عبر مسار القائمة', () {
    test('actualCheckout عند 14:00:59 → 3 ليالٍ للقيمتين', () async {
      final booking = await seedLegacyCheckedOut(
        actual: DateTime(2024, 3, 4, 14, 0, 59),
      );
      final nights = listNights(booking, now: nowA);

      expect(nights.expectedNights, 3);
      expect(nights.actualNights, 3);
    });

    test('actualCheckout عند 14:01:00 → 4 ليالٍ للقيمتين', () async {
      final booking = await seedLegacyCheckedOut(
        actual: DateTime(2024, 3, 4, 14, 1, 0),
      );
      final nights = listNights(booking, now: nowA);

      expect(nights.expectedNights, 4);
      expect(nights.actualNights, 4);
    });
  });
}
