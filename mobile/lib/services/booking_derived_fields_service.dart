import 'package:drift/drift.dart' as d;

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

  Future<void> _ensureBookingNights({
    required Booking booking,
    required DateTime checkin,
    required DateTime checkout,
    required int nightlyRate,
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

  Future<void> _rebuildBookingNights({
    required Booking booking,
    required DateTime checkin,
    required DateTime checkout,
    required int nightlyRate,
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

  int _calculateNightlyRate(
    DateTime segmentStart,
    int baseRate,
    int discount,
    String discountType,
    DateTime? discountStartDate,
  ) {
    if (baseRate < 0) baseRate = 0;
    var rate = baseRate;
    if (discount > 0 && discountType != 'total') {
      final hotelDay = Time.hotelDayStart(segmentStart);
      final hotelDayDate = DateTime(hotelDay.year, hotelDay.month, hotelDay.day);
      if (discountStartDate == null) {
        rate = (baseRate - discount).clamp(0, baseRate);
      } else {
        final discountDay = DateTime(
          discountStartDate.year,
          discountStartDate.month,
          discountStartDate.day,
        );
        if (!hotelDayDate.isBefore(discountDay)) {
          rate = (baseRate - discount).clamp(0, baseRate);
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
    if (value == null) return null;
    final v = value.trim();
    if (v.isEmpty) return null;
    final normalized = v.contains('T') ? v : v.replaceFirst(' ', 'T');
    final withSeconds = normalized.length == 16
        ? '${normalized}:00'
        : normalized;
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
    var cursor = checkin;

    while (cursor.isBefore(checkout)) {
      final dayStart = Time.hotelDayStart(cursor, cutoffHour: cutoffHour);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final segmentEnd = checkout.isBefore(dayEnd) ? checkout : dayEnd;
      if (!segmentEnd.isAfter(cursor)) {
        break;
      }
      segments.add(
        _NightSegment(
          hotelDayKey: Time.dateToString(dayStart),
          start: cursor,
          end: segmentEnd,
        ),
      );
      cursor = segmentEnd;
    }

    if (segments.isEmpty) {
      segments.add(
        _NightSegment(
          hotelDayKey: Time.dateToString(
            Time.hotelDayStart(checkin, cutoffHour: cutoffHour),
          ),
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
