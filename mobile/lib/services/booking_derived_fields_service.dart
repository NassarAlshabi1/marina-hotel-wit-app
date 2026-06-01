import 'package:drift/drift.dart' as d;
import '../utils/app_logger.dart';

import '../utils/status_utils.dart';
import '../utils/hotel_date_helper.dart';
import '../utils/time.dart';
import 'enhanced_booking_calculation_service.dart';
import 'local_db.dart';
import 'remote_config_service.dart';

class BookingDerivedFieldsService {
  BookingDerivedFieldsService(this.db);

  final AppDatabase db;

  Future<void> refreshForBookingId(
    int bookingId, {
    DateTime? now,
    bool forceRebuild = false,
  }) async {
    final booking =
        await (db.select(db.bookings)
              ..where((b) => b.id.equals(bookingId))
              ..where((b) => b.deletedAt.isNull()))
            .getSingleOrNull();
    if (booking == null) {
      return;
    }

    await refreshForBooking(booking, now: now, forceRebuild: forceRebuild);
  }

  /// تحديث الحقول المشتقة مع التمديد التلقائي إذا تجاوز النزيل 14:00
  Future<void> refreshForBooking(
    Booking booking, {
    DateTime? now,
    bool forceRebuild = false,
  }) async {
    final moment = now ?? DateTime.now();
    final calcService = EnhancedBookingCalculationService(db);
    final calculation =
        await calcService.calculateForBooking(booking, now: moment);

    await calcService.updateNightlyRecords(
      booking,
      now: moment,
      forceRebuild: forceRebuild,
      breakdown: calculation.breakdown,
    );

    final plannedCheckout = _parseDateTime(booking.checkoutDate);
    final actualCheckout = _parseDateTime(booking.actualCheckout);
    final checkin = _parseDateTime(booking.checkinDate) ?? moment;
    final isActive = actualCheckout == null && StatusUtils.isBookingActive(booking);

    // ─── الحقول المحسوبة ───
    final calculated = calculation.financialSummary.totalNights;
    int extraAutoNights = 0;
    DateTime? newCheckoutDate;

    if (isActive && calculated > booking.expectedNights) {
      // ✅ تمديد تلقائي: النزيل تجاوز 14:00 دون مغادرة
      extraAutoNights = calculated - booking.expectedNights;

      if (plannedCheckout != null) {
        newCheckoutDate = plannedCheckout.add(Duration(days: extraAutoNights));
      } else {
        newCheckoutDate = checkin.add(Duration(days: calculated));
      }

      AppLogger.info(
        '🔄 تمديد تلقائي للحجز ${booking.id}: '
        'expectedNights ${booking.expectedNights} → ${booking.expectedNights + extraAutoNights}, '
        'checkoutDate → ${_formatDateTime(newCheckoutDate)}',
        tag: 'AUTO_EXTEND',
      );
    }

    // expectedNights ثابت (ما أدخله الموظف) + التمديد التلقائي فقط
    final newExpectedNights = booking.expectedNights + extraAutoNights;

    // تاريخ المغادرة المخطط الجديد
    final checkoutStr = newCheckoutDate != null
        ? _formatDateTime(newCheckoutDate)
        : booking.checkoutDate;

    // ملاحظة التمديد التلقائي
    String? notes = booking.notes;
    if (extraAutoNights > 0) {
      final extNote = '📌 تمديد تلقائي: $extraAutoNights ${extraAutoNights == 1 ? 'ليلة' : 'ليالي'} (${moment.day}/${moment.month}/${moment.year})';
      notes = notes != null && notes.isNotEmpty
          ? '$notes\n$extNote'
          : extNote;
    }

    final isOverdue =
        calculation.bookingActive &&
        plannedCheckout != null &&
        moment.isAfter(plannedCheckout) &&
        extraAutoNights == 0; // إذا مددنا تلقائياً فليس متأخراً
    final needsReview =
        isOverdue || calculation.financialSummary.remainingBalance > 0;

    final nowUtc = DateTime.now().toUtc();
    final stamp = nowUtc.millisecondsSinceEpoch ~/ 1000;
    final stampIso = nowUtc.toIso8601String();

    await db.transaction(() async {
      await (db.update(
        db.bookings,
      )..where((b) => b.id.equals(booking.id))).write(
        BookingsCompanion(
          expectedNights: d.Value(newExpectedNights),
          calculatedNights: d.Value(calculated),
          totalNightsCached: d.Value(calculated),
          checkoutDate: d.Value(checkoutStr),
          notes: d.Value(notes),
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
          updatedAtIso: d.Value(stampIso),
        ),
      );
    });
  }

  Future<int> refreshAllActiveBookings({DateTime? now}) async {
    final moment = now ?? DateTime.now();
    final activeBookings = await (db.select(db.bookings)
          ..where((b) => b.actualCheckout.isNull() | b.actualCheckout.equals(''))
          ..where((b) => b.deletedAt.isNull()))
        .get();

    final active = activeBookings
        .where(StatusUtils.isBookingActive)
        .toList();

    int refreshed = 0;
    int promoted = 0;
    final results = await Future.wait(active.map((booking) async {
      try {
        bool didPromote = false;
        final cutoffHour = RemoteConfigService.instance.checkoutHour;
        if (StatusUtils.isBookingProvisional(booking) && moment.hour >= cutoffHour) {
          await _promoteProvisionalBooking(booking.id);
          didPromote = true;
        }
        await refreshForBooking(booking, now: moment, forceRebuild: true);
        return (promoted: didPromote, refreshed: true);
      } catch (e) {
        AppLogger.warning('خطأ في تحديث حجز ${booking.id}: $e');
        return (promoted: false, refreshed: false);
      }
    }),);
    promoted = results.where((r) => r.promoted).length;
    refreshed = results.where((r) => r.refreshed).length;

    if (promoted > 0) {
      AppLogger.info('تم تثبيت $promoted حجز مؤقت → محجوزة');
    }
    if (refreshed > 0) {
      AppLogger.debug('تم تجديد إقامة $refreshed حجز نشط تلقائياً');
    }
    return refreshed;
  }

  Future<void> _promoteProvisionalBooking(int bookingId) async {
    await (db.update(db.bookings)..where((b) => b.id.equals(bookingId)))
        .write(const BookingsCompanion(status: d.Value('محجوزة')));
  }

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
      final segDay = DateTime(segmentStart.year, segmentStart.month, segmentStart.day);
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
    final withSeconds = normalized.length == 16
        ? '$normalized:00'
        : normalized;
    try {
      return DateTime.parse(withSeconds);
    } catch (_) {
      return null;
    }
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }

  List<_NightSegment> _buildNightSegments(
    DateTime checkin,
    DateTime checkout, {
    int? cutoffHour,
  }) {
    final int resolvedCutoffHour = cutoffHour ?? RemoteConfigService.instance.checkoutHour;
    final segments = <_NightSegment>[];

    final int totalNights = HotelDateHelper.calculateNights(checkIn: checkin, checkOut: checkout);

    DateTime startOfCheckinHotelDay = DateTime(
      checkin.year,
      checkin.month,
      checkin.day,
      resolvedCutoffHour,
    );
    if (checkin.isBefore(startOfCheckinHotelDay)) {
      startOfCheckinHotelDay = startOfCheckinHotelDay.subtract(const Duration(days: 1));
    }

    for (int i = 0; i < totalNights; i++) {
      final dayDate = startOfCheckinHotelDay.add(Duration(days: i));
      final dayKey = Time.dateToString(dayDate);
      
      final segStart = i == 0 ? checkin : dayDate;
      
      final nextHotelDay = dayDate.add(const Duration(days: 1));
      final segEnd = i == totalNights - 1
          ? (checkout.isAfter(segStart) ? checkout : segStart.add(const Duration(minutes: 1)))
          : nextHotelDay;

      segments.add(
        _NightSegment(
          hotelDayKey: dayKey,
          start: segStart,
          end: segEnd,
        ),
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
