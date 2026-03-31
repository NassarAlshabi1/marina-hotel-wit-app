import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';

import '../utils/id.dart';
import '../utils/status_utils.dart';
import '../utils/time.dart';
import 'enhanced_booking_calculation_service.dart';
import 'local_db.dart';

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
    final calculation = await calcService.calculateForBooking(
      booking,
      now: moment,
    );

    await calcService.updateNightlyRecords(
      booking,
      now: moment,
      forceRebuild: forceRebuild,
      breakdown: calculation.breakdown,
    );

    final plannedCheckout = _parseDateTime(booking.checkoutDate);
    final actualCheckout = _parseDateTime(booking.actualCheckout);
    final expectedNightsValue =
        plannedCheckout != null && actualCheckout == null
        ? calculation.financialSummary.totalNights
        : booking.expectedNights;

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
          lastModified: d.Value(stamp),
          updatedAtIso: d.Value(stampIso),
          lastModifiedEpoch: d.Value(stamp),
        ),
      );
    });
  }

  Future<int> refreshAllActiveBookings({DateTime? now}) async {
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
    for (final booking in active) {
      try {
        if (StatusUtils.isBookingProvisional(booking) && moment.hour >= 14) {
          await _promoteProvisionalBooking(booking.id);
          promoted++;
        }
        await refreshForBooking(booking, now: moment, forceRebuild: true);
        refreshed++;
      } catch (e) {
        debugPrint('⚠️ خطأ في تحديث حجز ${booking.id}: $e');
      }
    }

    if (promoted > 0) {
      debugPrint('✅ تم تثبيت $promoted حجز مؤقت → محجوزة');
    }
    if (refreshed > 0) {
      debugPrint('🔄 تم تجديد إقامة $refreshed حجز نشط تلقائياً');
    }
    return refreshed;
  }

  Future<void> _promoteProvisionalBooking(int bookingId) async {
    await (db.update(db.bookings)..where((b) => b.id.equals(bookingId))).write(
      const BookingsCompanion(status: d.Value('محجوزة')),
    );
  }

  // ignore: unused_element
  Future<void> _ensureBookingNights({
    required Booking booking,
    required DateTime checkin,
    required DateTime checkout,
    required double nightlyRate,
    required int discount,
    required String discountType,
    required DateTime? discountStartDate,
  }) async {
    final lastNight =
        await (db.select(db.bookingNights)
              ..where((n) => n.bookingLocalId.equals(booking.id))
              ..where((n) => n.deletedAt.isNull())
              ..orderBy([
                (n) => d.OrderingTerm(
                  expression: n.nightEnd,
                  mode: d.OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();

    DateTime start = checkin;
    if (lastNight != null) {
      final parsed = _parseDateTime(lastNight.nightEnd);
      if (parsed != null) {
        start = parsed;
      }
    }

    if (start.isBefore(checkin)) {
      start = checkin;
    }

    if (!checkout.isAfter(start)) {
      return;
    }

    final segments = _buildNightSegments(start, checkout);
    if (segments.isEmpty) {
      return;
    }

    final nowUtc = DateTime.now().toUtc();
    final stamp = nowUtc.millisecondsSinceEpoch ~/ 1000;
    final stampIso = nowUtc.toIso8601String();

    await db.batch((batch) {
      int sequence = lastNight?.sequence ?? 0;
      for (final segment in segments) {
        sequence += 1;
        final rate = _calculateNightlyRate(
          segment.start,
          nightlyRate,
          discount,
          discountType,
          discountStartDate,
        );
        batch.insert(
          db.bookingNights,
          BookingNightsCompanion(
            localUuid: d.Value(IdGen.uuid()),
            createdAt: d.Value(stamp),
            updatedAt: d.Value(stamp),
            lastModified: d.Value(stamp),
            createdAtIso: d.Value(stampIso),
            updatedAtIso: d.Value(stampIso),
            createdAtEpoch: d.Value(stamp),
            lastModifiedEpoch: d.Value(stamp),
            origin: const d.Value('derived'),
            bookingLocalId: d.Value(booking.id),
            hotelDayKey: d.Value(segment.hotelDayKey),
            nightStart: d.Value(segment.start.toIso8601String()),
            nightEnd: d.Value(segment.end.toIso8601String()),
            nightlyRate: d.Value(rate),
            sequence: d.Value(sequence),
            isProcessedByAutoFix: const d.Value(false),
          ),
          mode: d.InsertMode.insertOrIgnore,
        );
      }
    });
  }

  // ignore: unused_element
  Future<void> _rebuildBookingNights({
    required Booking booking,
    required DateTime checkin,
    required DateTime checkout,
    required double nightlyRate,
    required int discount,
    required String discountType,
    required DateTime? discountStartDate,
  }) async {
    final segments = _buildNightSegments(checkin, checkout);

    final nowUtc = DateTime.now().toUtc();
    final stamp = nowUtc.millisecondsSinceEpoch ~/ 1000;
    final stampIso = nowUtc.toIso8601String();

    await db.transaction(() async {
      await (db.delete(
        db.bookingNights,
      )..where((t) => t.bookingLocalId.equals(booking.id))).go();

      await db.batch((batch) {
        int sequence = 0;
        for (final segment in segments) {
          sequence += 1;
          final rate = _calculateNightlyRate(
            segment.start,
            nightlyRate,
            discount,
            discountType,
            discountStartDate,
          );
          batch.insert(
            db.bookingNights,
            BookingNightsCompanion(
              localUuid: d.Value(IdGen.uuid()),
              createdAt: d.Value(stamp),
              updatedAt: d.Value(stamp),
              lastModified: d.Value(stamp),
              createdAtIso: d.Value(stampIso),
              updatedAtIso: d.Value(stampIso),
              createdAtEpoch: d.Value(stamp),
              lastModifiedEpoch: d.Value(stamp),
              origin: const d.Value('derived'),
              bookingLocalId: d.Value(booking.id),
              hotelDayKey: d.Value(segment.hotelDayKey),
              nightStart: d.Value(segment.start.toIso8601String()),
              nightEnd: d.Value(segment.end.toIso8601String()),
              nightlyRate: d.Value(rate),
              sequence: d.Value(sequence),
              isProcessedByAutoFix: const d.Value(false),
            ),
            mode: d.InsertMode.insertOrReplace,
          );
        }
      });
    });
  }

  /// ✅ تم إصلاح هذه الدالة لدعم أنواع التخفيض المختلفة بشكل صحيح
  double _calculateNightlyRate(
    DateTime segmentStart,
    double baseRate,
    int discount,
    String discountType,
    DateTime? discountStartDate,
  ) {
    if (baseRate < 0) baseRate = 0;
    var rate = baseRate;

    if (discount > 0) {
      // التحقق من تاريخ بدء التخفيض
      final segDay = DateTime(
        segmentStart.year,
        segmentStart.month,
        segmentStart.day,
      );

      bool shouldApplyDiscount = true;
      if (discountStartDate != null) {
        final discountDay = DateTime(
          discountStartDate.year,
          discountStartDate.month,
          discountStartDate.day,
        );
        shouldApplyDiscount = !segDay.isBefore(discountDay);
      }

      if (shouldApplyDiscount) {
        // تحويل نوع التخفيض إلى lowercase للمقارنة الآمنة
        final normalizedType = discountType.toLowerCase().trim();

        switch (normalizedType) {
          case 'percentage':
          case 'percent':
          case '%':
          case 'نسبة':
          case 'نسبة مئوية':
            // ✅ خصم نسبي: مثلاً 20% من 15,000 = 3,000
            final discountAmount = baseRate * (discount / 100);
            rate = (baseRate - discountAmount).clamp(0.0, baseRate);

          case 'fixed':
          case 'amount':
          case 'value':
          case 'ثابت':
          case 'مبلغ':
          case 'مبلغ ثابت':
            // ✅ خصم ثابت: مثلاً 3,000 من 15,000 = 12,000
            rate = (baseRate - discount.toDouble()).clamp(0.0, baseRate);

          case 'total':
          case 'المجموع':
          case 'اجمالي':
            // خصم من المجموع الكلي (يتم حسابه في مكان آخر، لا نطبق هنا)
            break;

          default:
            // ✅ افتراضياً: خصم ثابت للتوافق مع البيانات القديمة
            rate = (baseRate - discount.toDouble()).clamp(0.0, baseRate);
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
    if (value == null) return null;
    final v = value.trim();
    if (v.isEmpty) return null;
    final normalized = v.contains('T') ? v : v.replaceFirst(' ', 'T');
    final withSeconds = normalized.length == 16 ? '$normalized:00' : normalized;
    try {
      return DateTime.parse(withSeconds);
    } catch (_) {
      return null;
    }
  }

  List<_NightSegment> _buildNightSegments(
    DateTime checkin,
    DateTime checkout, {
    int cutoffHour = 14,
  }) {
    final segments = <_NightSegment>[];

    final checkinDate = DateTime(checkin.year, checkin.month, checkin.day);

    // ═══════════════════════════════════════════════════════════════
    // FIX: Use hotel day keys for accurate night counting.
    // See enhanced_booking_calculation_service.dart for details.
    // ═══════════════════════════════════════════════════════════════
    final checkinHotelDay = Time.hotelDayKey(now: checkin, cutoffHour: cutoffHour);
    final checkoutHotelDay = Time.hotelDayKey(now: checkout, cutoffHour: cutoffHour);

    final startHotelDay = DateTime.parse(checkinHotelDay);
    final endHotelDay = DateTime.parse(checkoutHotelDay);
    int days = endHotelDay.difference(startHotelDay).inDays + 1; // +1 for inclusive count
    if (days < 1) days = 1;

    for (int i = 0; i < days; i++) {
      final dayDate = checkinDate.add(Duration(days: i));
      final dayKey = Time.dateToString(dayDate);

      final segStart = i == 0 ? checkin : dayDate;
      final nextDay = dayDate.add(const Duration(days: 1));
      final segEnd = i == days - 1
          ? (checkout.isAfter(segStart)
                ? checkout
                : segStart.add(const Duration(minutes: 1)))
          : nextDay;

      segments.add(
        _NightSegment(hotelDayKey: dayKey, start: segStart, end: segEnd),
      );
    }

    if (segments.isEmpty) {
      segments.add(
        _NightSegment(
          hotelDayKey: Time.dateToString(checkin),
          start: checkin,
          end: checkout.isAfter(checkin)
              ? checkout
              : checkin.add(const Duration(minutes: 1)),
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
