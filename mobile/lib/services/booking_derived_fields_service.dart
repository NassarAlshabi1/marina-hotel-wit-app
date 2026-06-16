import 'package:drift/drift.dart' as d;
import 'package:marina_hotel_mobile/utils/app_logger.dart';

import '../utils/status_utils.dart';
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

    await db.transaction(() async {
      await (db.update(
        db.bookings,
      )..where((b) => b.id.equals(booking.id))).write(
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
    // معالجة الحجوزات بالتوازي باستخدام Future.wait بدلاً من التسلسل
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
        AppLogger.warning('⚠️ خطأ في تحديث حجز ${booking.id}: $e');
        return (promoted: false, refreshed: false);
      }
    }),);
    promoted = results.where((r) => r.promoted).length;
    refreshed = results.where((r) => r.refreshed).length;

    if (promoted > 0) {
      AppLogger.info('✅ تم تثبيت $promoted حجز مؤقت → محجوزة');
    }
    if (refreshed > 0) {
      AppLogger.info('🔄 تم تجديد إقامة $refreshed حجز نشط تلقائياً');
    }
    return refreshed;
  }

  Future<void> _promoteProvisionalBooking(int bookingId) async {
    await (db.update(db.bookings)..where((b) => b.id.equals(bookingId)))
        .write(const BookingsCompanion(status: d.Value('محجوزة')));
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
    final withSeconds = normalized.length == 16
        ? '$normalized:00'
        : normalized;
    try {
      return DateTime.parse(withSeconds);
    } catch (_) {
      return null;
    }
  }

  // ignore: unused_element
  List<_NightSegment> _buildNightSegments(
    DateTime checkin,
    DateTime checkout, {
    int? cutoffHour,
  }) {
    final int resolvedCutoffHour = cutoffHour ?? RemoteConfigService.instance.checkoutHour;
    final segments = <_NightSegment>[];

    // استخدام المنطق الموحد لحساب عدد الليالي بناءً على الساعة 14:00
    final int totalNights = Time.nightsWithCutoff(checkin, checkout: checkout, cutoffHour: resolvedCutoffHour);

    // حساب بداية "يوم الفندق" لعملية تسجيل الدخول
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
      
      // بداية الشريحة: وقت الوصول الفعلي لأول شريحة، أو بداية يوم الفندق للشرائح التالية
      final segStart = i == 0 ? checkin : dayDate;
      
      // نهاية الشريحة: وقت المغادرة الفعلي لآخر شريحة، أو بداية يوم الفندق التالي للشرائح البينية
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
