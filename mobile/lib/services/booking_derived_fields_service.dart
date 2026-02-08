import 'package:drift/drift.dart' as d;

import '../utils/id.dart';
import '../utils/status_utils.dart';
import '../utils/time.dart';
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

    final checkin = _parseDateTime(booking.checkinDate);
    if (checkin == null) {
      return;
    }

    final plannedCheckout = _parseDateTime(booking.checkoutDate);
    final actualCheckout = _parseDateTime(booking.actualCheckout);

    final bookingActive =
        actualCheckout == null && StatusUtils.isBookingActive(booking);

    DateTime checkout = actualCheckout ?? plannedCheckout ?? moment;
    if (bookingActive &&
        (plannedCheckout == null || moment.isAfter(plannedCheckout))) {
      checkout = moment;
    }

    if (!checkout.isAfter(checkin)) {
      checkout = checkin.add(const Duration(minutes: 1));
    }

    final room =
        await (db.select(db.rooms)
              ..where((r) => r.roomNumber.equals(booking.roomNumber))
              ..where((r) => r.deletedAt.isNull()))
            .getSingleOrNull();

    final nightlyRate = room?.price ?? 0.0;
    final discount = booking.discount;
    final discountType = booking.discountType;
    final discountStartDate = _parseDateTime(booking.discountStartDate);

    if (forceRebuild) {
      await _rebuildBookingNights(
        booking: booking,
        checkin: checkin,
        checkout: checkout,
        nightlyRate: nightlyRate,
        discount: discount,
        discountType: discountType,
        discountStartDate: discountStartDate,
      );
    } else {
      await _ensureBookingNights(
        booking: booking,
        checkin: checkin,
        checkout: checkout,
        nightlyRate: nightlyRate,
        discount: discount,
        discountType: discountType,
        discountStartDate: discountStartDate,
      );
    }

    final nights =
        await (db.select(db.bookingNights)
              ..where((n) => n.bookingLocalId.equals(booking.id))
              ..where((n) => n.deletedAt.isNull()))
            .get();

    final totalNights = nights.length;
    final totalNightAmount = nights.fold<double>(
      0,
      (sum, night) => sum + night.nightlyRate,
    );

    double totalDue = totalNightAmount;
    if (discount > 0 && discountType == 'total') {
      totalDue = double.parse(
        (totalNightAmount - discount)
            .clamp(0.0, totalNightAmount)
            .toStringAsFixed(2),
      );
    } else {
      totalDue = double.parse(totalNightAmount.toStringAsFixed(2));
    }

    final expectedNightsValue =
        plannedCheckout != null && actualCheckout == null
        ? totalNights
        : booking.expectedNights;

    final payments =
        await (db.select(db.payments)
              ..where(
                (p) =>
                    (p.bookingLocalId.equals(booking.id) |
                    p.bookingUuidCache.equals(booking.localUuid)),
              )
              ..where((p) => p.revenueType.equals('room'))
              ..where((p) => p.deletedAt.isNull()))
            .get();

    final totalPaid = double.parse(
      payments.fold<double>(0.0, (sum, p) => sum + p.amount).toStringAsFixed(2),
    );

    final remainingRaw = double.parse(
      (totalDue - totalPaid).toStringAsFixed(2),
    );
    final remaining = remainingRaw < 0 ? 0.0 : remainingRaw;

    final isFullyPaid = remaining <= 0.009;
    final isOverdue =
        bookingActive &&
        plannedCheckout != null &&
        moment.isAfter(plannedCheckout);
    final needsReview = isOverdue || remaining > 0.009;

    final stayDurationIso =
        '${checkin.toIso8601String()}/${checkout.toIso8601String()}';
    final lastNightEpoch = _resolveLastNightEpoch(nights, checkout);

    final hotelDayCheckin = Time.hotelDayKey(now: checkin);
    final hotelDayCheckout = Time.hotelDayKey(now: checkout);

    final nowUtc = DateTime.now().toUtc();
    final stamp = nowUtc.millisecondsSinceEpoch ~/ 1000;
    final stampIso = nowUtc.toIso8601String();

    await db.transaction(() async {
      await (db.update(
        db.bookings,
      )..where((b) => b.id.equals(booking.id))).write(
        BookingsCompanion(
          expectedNights: d.Value(expectedNightsValue),
          calculatedNights: d.Value(totalNights),
          totalNightsCached: d.Value(totalNights),
          stayDurationIso: d.Value(stayDurationIso),
          lastNightEpoch: d.Value(lastNightEpoch),
          isOverdue: d.Value(isOverdue),
          needsCheckoutReview: d.Value(needsReview),
          totalDueCached: d.Value(totalDue),
          totalPaidCached: d.Value(totalPaid),
          remainingBalanceCached: d.Value(remaining),
          isFullyPaid: d.Value(isFullyPaid),
          hotelDayCheckin: d.Value(hotelDayCheckin),
          hotelDayCheckout: d.Value(hotelDayCheckout),
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
    required double nightlyRate,
    required double discount,
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
    required double nightlyRate,
    required double discount,
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

  double _calculateNightlyRate(
    DateTime date,
    double baseRate,
    double discount,
    String discountType,
    DateTime? discountStartDate,
  ) {
    var rate = baseRate;
    if (discount > 0 && discountType != 'total') {
      final bookingDay = DateTime(date.year, date.month, date.day);
      if (discountStartDate == null) {
        rate = (baseRate - discount).clamp(0.0, baseRate);
      } else {
        final discountDay = DateTime(
          discountStartDate.year,
          discountStartDate.month,
          discountStartDate.day,
        );
        if (!bookingDay.isBefore(discountDay)) {
          rate = (baseRate - discount).clamp(0.0, baseRate);
        }
      }
    }
    return double.parse(rate.toStringAsFixed(2));
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
