import 'package:drift/drift.dart' as d;

import '../services/daos/bookings_dao.dart';
import '../services/daos/outbox_dao.dart';
import '../utils/debug_log.dart';
import '../utils/hotel_time_engine.dart';
import '../utils/status_utils.dart';
import '../utils/time.dart';
import 'enhanced_booking_calculation_service.dart';
import 'local_db.dart';

class BookingDerivedFieldsService {
  BookingDerivedFieldsService(this.db, [OutboxDao? outboxDao])
    : _outboxDao = outboxDao ?? OutboxDao(db);

  final AppDatabase db;
  final OutboxDao _outboxDao;

  Future<void> refreshForBookingId(
    int bookingId, {
    DateTime? now,
    bool forceRebuild = false,
    bool enqueueOutbox = true,
  }) async {
    final booking =
        await (db.select(db.bookings)
              ..where((b) => b.id.equals(bookingId))
              ..where((b) => b.deletedAt.isNull()))
            .getSingleOrNull();
    if (booking == null) {
      return;
    }

    await refreshForBooking(
      booking,
      now: now,
      forceRebuild: forceRebuild,
      enqueueOutbox: enqueueOutbox,
    );
  }

  /// Refresh derived fields for a single booking (opens its own transaction).
  /// Use this for single-booking updates. For batch updates, use
  /// [refreshAllActiveBookings] which batches all writes in one transaction.
  Future<void> refreshForBooking(
    Booking booking, {
    DateTime? now,
    bool forceRebuild = false,
    bool enqueueOutbox = true,
  }) async {
    await db.transaction(() async {
      await _refreshForBookingInTransaction(
        booking,
        now: now,
        forceRebuild: forceRebuild,
        enqueueOutbox: enqueueOutbox,
      );
    });
  }

  /// Core logic that runs inside an existing transaction.
  /// Does NOT open its own transaction — must only be called from within
  /// a `db.transaction` block or `refreshAllActiveBookings`.
  Future<void> _refreshForBookingInTransaction(
    Booking booking, {
    DateTime? now,
    bool forceRebuild = false,
    bool enqueueOutbox = true,
  }) async {
    final moment = now ?? DateTime.now();
    final calcService = EnhancedBookingCalculationService(db);
    final calculation = await calcService.calculateForBooking(
      booking,
      now: moment,
    );

    await calcService.updateNightlyRecords(
      booking,
      now: moment,
      forceRebuild: forceRebuild,
      breakdown: calculation.breakdown,
      inTransaction: true, // we are already inside a transaction
      enqueueOutbox: enqueueOutbox,
    );

    final plannedCheckout = _parseDateTime(booking.checkoutDate);
    final actualCheckout = _parseDateTime(booking.actualCheckout);

    // For active bookings (no actual checkout), expectedNights should dynamically
    // grow with the current time (totalNights from calculation which uses moment).
    // This ensures payment screens show the correct number of nights if they stay past 14:00.
    final expectedNightsValue =
        (actualCheckout == null && StatusUtils.isBookingActive(booking))
        ? calculation.financialSummary.totalNights
        : (plannedCheckout != null && actualCheckout == null
              ? calculation.financialSummary.totalNights
              : booking.expectedNights);

    final isOverdue =
        calculation.bookingActive &&
        plannedCheckout != null &&
        moment.isAfter(plannedCheckout);
    final needsReview =
        isOverdue || calculation.financialSummary.remainingBalance > 0;

    final nowUtc = DateTime.now().toUtc();
    final stamp = nowUtc.millisecondsSinceEpoch ~/ 1000;
    final stampIso = nowUtc.toIso8601String();

    // Direct write — no nested transaction because caller already holds one.
    await (db.update(db.bookings)..where((b) => b.id.equals(booking.id))).write(
      BookingsCompanion(
        expectedNights: d.Value(expectedNightsValue),
        calculatedNights: d.Value(calculation.financialSummary.totalNights),
        totalNightsCached: d.Value(calculation.financialSummary.totalNights),
        stayDurationIso: d.Value(calculation.stayDurationIso),
        lastNightEpoch: d.Value(calculation.lastNightEpoch),
        isOverdue: d.Value(isOverdue),
        needsCheckoutReview: d.Value(needsReview),
        totalDueCached: d.Value(
          calculation.financialSummary.totalDue.toDouble(),
        ),
        totalPaidCached: d.Value(
          calculation.financialSummary.totalPaid.toDouble(),
        ),
        remainingBalanceCached: d.Value(
          calculation.financialSummary.remainingBalance.toDouble(),
        ),
        isFullyPaid: d.Value(calculation.financialSummary.isFullyPaid),
        hotelDayCheckin: d.Value(calculation.hotelDayCheckin),
        hotelDayCheckout: d.Value(calculation.hotelDayCheckout),
        updatedAt: d.Value(stamp),
        // ✅ لا نحدّث lastModified للحقول المشتقة لأنها تُحسب محلياً
        // وليست تغييراً من المستخدم. تحديث lastModified يجعل البيانات
        // المحلية تبدو "أحدث" مما يمنع السحب من تحديثها في المزامنة القادمة.
        updatedAtIso: d.Value(stampIso),
      ),
    );

    // الحقول المشتقة تُعاد حسابها أثناء السحب أيضاً. لا يجوز أن تتحول
    // كتابة بيانات Appwrite إلى تعديل مستخدم محلي قابل للرفع.
    if (!enqueueOutbox) {
      return;
    }

    final updated = await (db.select(
      db.bookings,
    )..where((b) => b.id.equals(booking.id))).getSingleOrNull();
    if (updated != null) {
      final bookingsDao = BookingsDao(db, _outboxDao);
      final payload = await bookingsDao.payloadForLocalUuid(updated.localUuid);
      if (payload != null) {
        await _outboxDao.merge(
          entity: 'bookings',
          op: 'update',
          localUuid: updated.localUuid,
          payload: payload,
          clientTs: stamp,
        );
      }
    }
  }

  Future<int> refreshAllActiveBookings({
    DateTime? now,
    bool enqueueOutbox = true,
  }) async {
    final moment = now ?? DateTime.now();
    final activeBookings =
        await (db.select(db.bookings)
              ..where(
                (b) => b.actualCheckout.isNull() | b.actualCheckout.equals(''),
              )
              ..where((b) => b.deletedAt.isNull()))
            .get();

    final active = activeBookings.where(StatusUtils.isBookingActive).toList();

    int refreshed = 0;
    int promoted = 0;

    // ✅ معالجة جميع الحجوزات داخل معاملة واحدة لتجنب تنازع أقفال SQLite
    // بدلاً من Future.wait الذي يفتح معاملة لكل حجز على حدة ويسبب SQLITE_BUSY
    await db.transaction(() async {
      for (final booking in active) {
        try {
          if (StatusUtils.isBookingProvisional(booking) &&
              HotelTimeEngine.isAfterCutoff(moment)) {
            await _promoteProvisionalBooking(booking.id);
            promoted++;
          }
          await _refreshForBookingInTransaction(
            booking,
            now: moment,
            forceRebuild: true,
            enqueueOutbox: enqueueOutbox,
          );
          refreshed++;
        } catch (e) {
          dlog(() => '⚠️ خطأ في تحديث حجز ${booking.id}: $e');
        }
      }
    });

    if (promoted > 0) {
      dlog(() => '✅ تم تثبيت $promoted حجز مؤقت → محجوزة');
    }
    if (refreshed > 0) {
      dlog(() => '🔄 تم تجديد إقامة $refreshed حجز نشط تلقائياً');
    }
    return refreshed;
  }

  Future<void> _promoteProvisionalBooking(int bookingId) async {
    final booking = await (db.select(
      db.bookings,
    )..where((b) => b.id.equals(bookingId))).getSingleOrNull();
    if (booking == null) return;

    await (db.update(db.bookings)..where((b) => b.id.equals(bookingId))).write(
      const BookingsCompanion(status: d.Value('محجوزة')),
    );

    final updated = await (db.select(
      db.bookings,
    )..where((b) => b.id.equals(bookingId))).getSingleOrNull();
    if (updated == null) return;

    final bookingsDao = BookingsDao(db, _outboxDao);
    final payload = await bookingsDao.payloadForLocalUuid(updated.localUuid);
    if (payload == null) return;

    await _outboxDao.merge(
      entity: 'bookings',
      op: 'update',
      localUuid: updated.localUuid,
      payload: payload,
      clientTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  // ignore: unused_element
  double _calculateNightlyRate(
    DateTime segmentStart,
    double baseRate,
    int discount,
    String discountType,
    DateTime? discountStartDate,
  ) {
    if (baseRate < 0) {
      baseRate = 0;
    }
    var rate = baseRate;
    if (discount > 0 && discountType != 'total') {
      final segDay = DateTime(
        segmentStart.year,
        segmentStart.month,
        segmentStart.day,
      );
      if (discountStartDate == null) {
        rate = (baseRate - discount).clamp(0.0, baseRate);
      } else {
        final discountDay = DateTime(
          discountStartDate.year,
          discountStartDate.month,
          discountStartDate.day,
        );
        if (!segDay.isBefore(discountDay)) {
          rate = (baseRate - discount).clamp(0.0, baseRate);
        }
      }
    }
    return rate;
  }

  // ignore: unused_element
  int _resolveLastNightEpoch(List<BookingNight> nights, DateTime fallback) {
    if (nights.isEmpty) {
      return fallback.millisecondsSinceEpoch ~/ 1000;
    }
    DateTime? latest;
    for (final night in nights) {
      final parsed = _parseDateTime(night.nightEnd);
      if (parsed != null) {
        if (latest == null || parsed.isAfter(latest)) {
          latest = parsed;
        }
      }
    }
    final end = latest ?? fallback;
    return end.millisecondsSinceEpoch ~/ 1000;
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null) {
      return null;
    }
    final v = value.trim();
    if (v.isEmpty) {
      return null;
    }
    final normalized = v.contains('T') ? v : v.replaceFirst(' ', 'T');
    final withSeconds = normalized.length == 16 ? '$normalized:00' : normalized;
    try {
      return DateTime.parse(withSeconds);
    } catch (_) {
      return null;
    }
  }

  // ignore: unused_element
  List<_NightSegment> _buildNightSegments(DateTime checkin, DateTime checkout) {
    final segments = <_NightSegment>[];
    final totalNights = HotelTimeEngine.calculateDays(
      checkin,
      checkOut: checkout,
    );

    final hotelDay = HotelTimeEngine.getHotelDay(checkin);
    final startOfCheckinHotelDay = DateTime(
      hotelDay.year,
      hotelDay.month,
      hotelDay.day,
      HotelTimeEngine.boundaryHour,
      HotelTimeEngine.boundaryMinute,
    );

    for (int i = 0; i < totalNights; i++) {
      final dayDate = startOfCheckinHotelDay.add(Duration(days: i));
      final dayKey = Time.dateToString(dayDate);

      // بداية الشريحة: وقت الوصول الفعلي لأول شريحة، أو بداية يوم الفندق للشرائح التالية
      final segStart = i == 0 ? checkin : dayDate;

      // نهاية الشريحة: وقت المغادرة الفعلي لآخر شريحة، أو بداية يوم الفندق التالي للشرائح البينية
      final nextHotelDay = dayDate.add(const Duration(days: 1));
      final segEnd = i == totalNights - 1
          ? (checkout.isAfter(segStart)
                ? checkout
                : segStart.add(const Duration(minutes: 1)))
          : nextHotelDay;

      segments.add(
        _NightSegment(hotelDayKey: dayKey, start: segStart, end: segEnd),
      );
    }

    return segments;
  }
}

class _NightSegment {
  const _NightSegment({
    required this.hotelDayKey,
    required this.start,
    required this.end,
  });

  final String hotelDayKey;
  final DateTime start;
  final DateTime end;
}
