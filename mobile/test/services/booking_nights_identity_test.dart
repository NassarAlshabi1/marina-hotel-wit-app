// ============================================================================
//  Marina Hotel — استقرار هوية الليالي في إعادة البناء (بند 3.3 + 8.2)
// ============================================================================
//   ① إعادة حساب مرتين ⇒ نفس المعرفات (لا UUID جديدة لكل إعادة).
//   ② تغيّر السعر (تعديل) ⇒ تحديث في المكان بنفس المعرف.
//   ③ تقصير الإقامة (مغادرة فعلية أقدم) ⇒ الليالي الزائدة تُحذف حذفاً
//      ناعماً (deletedAt) + قبر مُزامَن في outbox (op=delete) — لا حذف
//      جذري صامت.
//   ④ لا تغيير ⇒ لا كتابة إطلاقاً (updatedAt كما هو).
//   ⑤ التعديل المحلي يدخل Outbox مرة واحدة ويزيد vectorClock.
//   ⑥ التحديث الوارد من المزامنة لا يُعاد إلى Outbox.
//  لا mock — قاعدة SQLite حقيقية في الذاكرة.
// ============================================================================

import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/enhanced_booking_calculation_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rate = 100.0;
  late AppDatabase db;
  late RoomsRepository roomsRepo;
  late BookingsRepository bookingsRepo;
  late EnhancedBookingCalculationService engine;

  final today = DateTime.now();
  DateTime day(int daysBack, [int hour = 15]) =>
      DateTime(today.year, today.month, today.day - daysBack, hour);

  setUp(() async {
    AppwriteSyncManager.updateStaticDeviceId('booking-nights-test-device');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    roomsRepo = RoomsRepository(db);
    bookingsRepo = BookingsRepository(db);
    engine = EnhancedBookingCalculationService(db);
    await roomsRepo.create(
      roomNumber: '101',
      type: 'عادية',
      price: rate,
      status: 'شاغرة',
    );
  });

  tearDown(() async {
    AppwriteSyncManager.updateStaticDeviceId(null);
    await db.close();
  });

  Future<Booking> fetchBooking(int id) =>
      (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingle();

  Future<List<BookingNight>> liveNights(int bookingId) =>
      (db.select(db.bookingNights)
            ..where((n) => n.bookingLocalId.equals(bookingId))
            ..where((n) => n.deletedAt.isNull())
            ..orderBy([(n) => d.OrderingTerm.asc(n.hotelDayKey)]))
          .get();

  Future<List<BookingNight>> allNights(int bookingId) =>
      (db.select(db.bookingNights)
            ..where((n) => n.bookingLocalId.equals(bookingId))
            ..orderBy([(n) => d.OrderingTerm.asc(n.hotelDayKey)]))
          .get();

  Future<int> seedActiveBooking() async {
    final id = await bookingsRepo.create(
      roomNumber: '101',
      guestName: 'نزيل هوية الليالي',
      guestPhone: '0500000000',
      guestNationality: 'يمني',
      checkinDate: day(4).toIso8601String(),
      status: 'نشط',
      expectedNights: 4,
    );
    // تنظيف ليالي الإنشاء التلقائي (تُولَّد حتى الساعة الحقيقية للجهاز —
    // غير حتمية عبر أوقات التشغيل) كي يكون مصدر الليالي updateNightlyRecords
    // وحده بلحظة `now` الحتمية التي يمررها كل اختبار.
    final generatedNights = await (db.select(
      db.bookingNights,
    )..where((n) => n.bookingLocalId.equals(id))).get();
    final generatedUuids = generatedNights
        .map((night) => night.localUuid)
        .toList();
    if (generatedUuids.isNotEmpty) {
      await (db.delete(db.outbox)..where(
            (entry) =>
                entry.entity.equals('booking_nights') &
                entry.localUuid.isIn(generatedUuids),
          ))
          .go();
      await (db.delete(db.bookingNights)
            ..where((n) => n.localUuid.isIn(generatedUuids)))
          .go();
    }
    return id;
  }

  test('① إعادة الحساب مرتين تحافظ على المعرفات (لا UUID جديدة)', () async {
    final id = await seedActiveBooking();
    final now = day(0, 10);

    await engine.updateNightlyRecords(await fetchBooking(id),
        now: now, forceRebuild: true);
    final first = await liveNights(id);
    expect(first.length, 4, reason: '4 ليالٍ حتى الآن (دخول بعد 14:01)');

    await engine.updateNightlyRecords(await fetchBooking(id),
        now: now, forceRebuild: true);
    final second = await liveNights(id);

    expect(
      second.map((n) => n.localUuid).toList(),
      first.map((n) => n.localUuid).toList(),
      reason: 'نفس المعرفات — التحديث في المكان لا إعادة إدراج',
    );
    expect((await allNights(id)).length, 4,
        reason: 'لا صفوف مكررة ولا قبور');
  });

  test('② تغيّر السعر ⇒ نفس المعرف بقيم جديدة', () async {
    final id = await seedActiveBooking();
    final booking = await fetchBooking(id);
    final now = day(0, 10);
    await engine.updateNightlyRecords(booking, now: now, forceRebuild: true);
    final before = await liveNights(id);

    // خصم ليلي 20 من أول ليلة → السعر الفعلي 80
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.into(db.bookingPriceAdjustments).insert(
          BookingPriceAdjustmentsCompanion.insert(
            localUuid: 'adj-identity-$nowEpoch',
            bookingLocalUuid: booking.localUuid,
            createdAt: nowEpoch,
            updatedAt: nowEpoch,
            lastModified: nowEpoch,
            bookingLocalId: d.Value(id),
            roomNumber: const d.Value('101'),
            amount: const d.Value(20.0),
            effectiveHotelDay: before.first.hotelDayKey,
            reason: const d.Value('خصم ليلي اختباري موثق'),
            adjustmentType: const d.Value(0),
            adjustmentMode: const d.Value('per_night'),
          ),
        );

    await engine.updateNightlyRecords(await fetchBooking(id),
        now: now, forceRebuild: true);
    final after = await liveNights(id);

    expect(after.map((n) => n.localUuid).toList(),
        before.map((n) => n.localUuid).toList(),
        reason: 'التعديل يحدّث في المكان — نفس الهوية');
    expect(after.first.finalRate, 80.0);
    expect(after.first.baseRate, 100.0);
  });

  test('③ تقصير الإقامة ⇒ حذف ناعم + قبر مُزامَن في outbox (لا حذف جذري)',
      () async {
    final id = await seedActiveBooking();
    final now = day(0, 10);
    await engine.updateNightlyRecords(await fetchBooking(id),
        now: now, forceRebuild: true);
    final before = await liveNights(id);
    expect(before.length, 4);

    // مغادرة فعلية بعد ليلتين فقط → ليلتان زائدتان يجب دفنهما
    await bookingsRepo.update(
      id,
      status: 'مكتمل',
      actualCheckout: day(2, 12).toIso8601String(),
    );
    await engine.updateNightlyRecords(await fetchBooking(id),
        now: now, forceRebuild: true);

    final live = await liveNights(id);
    expect(live.length, 2, reason: 'ليلتا الإقامة فقط تبقيان حيتين');
    // المعرفان الباقيان لم يتغيرا
    expect(
      live.map((n) => n.localUuid).toList(),
      before.take(2).map((n) => n.localUuid).toList(),
    );

    // القبر: الصفوف الزائدة موجودة بـ deletedAt — لم تُمحَ جذرياً
    final all = await allNights(id);
    expect(all.length, 4, reason: 'الصفوف الزائدة محفوظة (حذف ناعم)');
    final buried = all.where((n) => n.deletedAt != null).toList();
    expect(buried.length, 2);
    expect(
      buried.map((n) => n.localUuid).toList(),
      containsAll(before.skip(2).map((n) => n.localUuid).toList()),
    );

    // قبر مُزامَن: outbox يحمل op=delete لكل ليلة مدفونة
    final tombstones =
        await (db.select(db.outbox)
              ..where((o) => o.entity.equals('booking_nights'))
              ..where((o) => o.op.equals('delete')))
            .get();
    expect(tombstones.length, 2,
        reason: 'آلية tombstone القائمة (Wave 5) تتسلم القبور');
    expect(
      tombstones.map((o) => o.localUuid).toList(),
      containsAll(buried.map((n) => n.localUuid).toList()),
    );
  });

  test('④ لا تغيير ⇒ لا كتابة إطلاقاً', () async {
    final id = await seedActiveBooking();
    final now = day(0, 10);
    await engine.updateNightlyRecords(await fetchBooking(id),
        now: now, forceRebuild: true);
    final before = await liveNights(id);
    final updatedBefore = before.map((n) => n.updatedAt).toList();

    // إعادة حساب بلا forceRebuild وبلا أي تغيير
    await engine.updateNightlyRecords(await fetchBooking(id),
        now: now, forceRebuild: false);

    final after = await liveNights(id);
    expect(after.map((n) => n.updatedAt).toList(), updatedBefore,
        reason: 'لا كتابة عند عدم وجود فرق (كان الكود القديم يعيد الإدراج)');
  });

  test('⑤ الليالي المحلية تُزامَن دون تكرار وتُحدَّث vectorClock', () async {
    final id = await seedActiveBooking();
    final now = day(0, 10);

    await engine.updateNightlyRecords(
      await fetchBooking(id),
      now: now,
      forceRebuild: true,
    );
    final first = await liveNights(id);
    expect(first, hasLength(4));

    Future<List<OutboxData>> nightOutbox() =>
        (db.select(db.outbox)
              ..where((entry) => entry.entity.equals('booking_nights')))
            .get();

    var queued = await nightOutbox();
    expect(queued, hasLength(first.length));
    expect(
      queued.map((entry) => entry.localUuid).toSet(),
      first.map((night) => night.localUuid).toSet(),
    );
    for (final night in first) {
      final clock = jsonDecode(night.vectorClock) as Map<String, dynamic>;
      expect(clock['booking-nights-test-device'], 1);
    }

    // إعادة الحساب دون اختلاف لا تنشئ ليالي أو عناصر Outbox إضافية.
    await engine.updateNightlyRecords(
      await fetchBooking(id),
      now: now,
      forceRebuild: true,
    );
    final repeated = await liveNights(id);
    queued = await nightOutbox();
    expect(
      repeated.map((night) => night.localUuid).toList(),
      first.map((night) => night.localUuid).toList(),
    );
    expect((await allNights(id)), hasLength(first.length));
    expect(queued, hasLength(first.length));

    // تعديل السعر يدمج العملية تحت UUID نفسها، ولا يكرر الليلة أو الـOutbox.
    final booking = await fetchBooking(id);
    await db.into(db.bookingPriceAdjustments).insert(
          BookingPriceAdjustmentsCompanion.insert(
            localUuid: 'adj-outbox-${DateTime.now().millisecondsSinceEpoch}',
            bookingLocalUuid: booking.localUuid,
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            lastModified: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            bookingLocalId: d.Value(id),
            roomNumber: const d.Value('101'),
            amount: const d.Value(20.0),
            effectiveHotelDay: first.first.hotelDayKey,
            reason: const d.Value('خصم ليلي لاختبار المزامنة'),
            adjustmentType: const d.Value(0),
            adjustmentMode: const d.Value('per_night'),
          ),
        );
    await engine.updateNightlyRecords(
      await fetchBooking(id),
      now: now,
      forceRebuild: true,
    );

    final updated = await liveNights(id);
    queued = await nightOutbox();
    expect(
      updated.map((night) => night.localUuid).toList(),
      first.map((night) => night.localUuid).toList(),
    );
    expect((await allNights(id)), hasLength(first.length));
    expect(queued, hasLength(first.length));
    final adjusted = updated.first;
    final adjustedClock =
        jsonDecode(adjusted.vectorClock) as Map<String, dynamic>;
    expect(adjustedClock['booking-nights-test-device'], 2);
    final adjustedOutbox =
        queued.singleWhere((entry) => entry.localUuid == adjusted.localUuid);
    expect(adjustedOutbox.op, 'update');
  });

  test('⑥ إعادة الحساب الواردة من المزامنة لا تُعاد إلى Outbox', () async {
    final id = await seedActiveBooking();
    await engine.updateNightlyRecords(
      await fetchBooking(id),
      now: day(0, 10),
      forceRebuild: true,
      enqueueOutbox: false,
    );

    expect(
      await (db.select(db.outbox)
            ..where((entry) => entry.entity.equals('booking_nights')))
          .get(),
      isEmpty,
    );
    expect(
      (await liveNights(id)).every((night) => night.vectorClock == '{}'),
      isTrue,
    );
  });
}
