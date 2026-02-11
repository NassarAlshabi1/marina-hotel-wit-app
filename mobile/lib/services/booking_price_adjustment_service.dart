import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'local_db.dart';
import 'booking_derived_fields_service.dart';
import '../utils/time.dart';
import '../utils/id.dart';

enum AdjustmentType {
  discount(0),
  surcharge(1);

  const AdjustmentType(this.value);
  final int value;

  static AdjustmentType fromValue(int value) {
    return AdjustmentType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AdjustmentType.discount,
    );
  }
}

enum AdjustmentMode {
  perNight('per_night'),
  total('total'),
  percentage('percentage');

  const AdjustmentMode(this.value);
  final String value;

  static AdjustmentMode fromValue(String? value) {
    return AdjustmentMode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AdjustmentMode.perNight,
    );
  }
}

class AdjustmentPreview {
  final double originalTotal;
  final double adjustedTotal;
  final double difference;
  final int nightsAffected;
  final List<NightBreakdown> nightlyBreakdown;

  AdjustmentPreview({
    required this.originalTotal,
    required this.adjustedTotal,
    required this.difference,
    required this.nightsAffected,
    required this.nightlyBreakdown,
  });
}

class NightBreakdown {
  final String hotelDayKey;
  final double baseRate;
  final double adjustment;
  final double finalRate;
  final String? adjustmentUuid;

  NightBreakdown({
    required this.hotelDayKey,
    required this.baseRate,
    required this.adjustment,
    required this.finalRate,
    this.adjustmentUuid,
  });
}

class LostRevenueReport {
  final double totalPotentialRevenue;
  final double totalActualRevenue;
  final double totalLostRevenue;
  final double totalGainedRevenue;
  final List<BookingLostRevenue> bookingDetails;

  LostRevenueReport({
    required this.totalPotentialRevenue,
    required this.totalActualRevenue,
    required this.totalLostRevenue,
    required this.totalGainedRevenue,
    required this.bookingDetails,
  });
}

class BookingLostRevenue {
  final int bookingId;
  final String guestName;
  final String roomNumber;
  final double potentialRevenue;
  final double actualRevenue;
  final double lostRevenue;
  final double gainedRevenue;
  final List<AdjustmentSummary> adjustments;

  BookingLostRevenue({
    required this.bookingId,
    required this.guestName,
    required this.roomNumber,
    required this.potentialRevenue,
    required this.actualRevenue,
    required this.lostRevenue,
    required this.gainedRevenue,
    required this.adjustments,
  });
}

class AdjustmentSummary {
  final String uuid;
  final AdjustmentType type;
  final double amount;
  final String effectiveHotelDay;
  final String? endHotelDay;
  final int nightsAffected;
  final double totalImpact;

  AdjustmentSummary({
    required this.uuid,
    required this.type,
    required this.amount,
    required this.effectiveHotelDay,
    this.endHotelDay,
    required this.nightsAffected,
    required this.totalImpact,
  });
}

class BookingPriceAdjustmentService {
  final AppDatabase db;
  final BookingDerivedFieldsService? derivedFieldsService;

  BookingPriceAdjustmentService(this.db, {this.derivedFieldsService});

  Future<AdjustmentPreview> previewAdjustment({
    required int bookingId,
    required int amount,
    required AdjustmentType type,
    required String effectiveHotelDay,
    String? endHotelDay,
    AdjustmentMode mode = AdjustmentMode.perNight,
  }) async {
    final booking = await (db.select(db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .getSingleOrNull();
    if (booking == null) {
      throw StateError('Booking not found: $bookingId');
    }

    final room = await (db.select(db.rooms)
          ..where((r) => r.roomNumber.equals(booking.roomNumber)))
        .getSingleOrNull();
    if (room == null) {
      throw StateError('Room not found: ${booking.roomNumber}');
    }

    final nights = await (db.select(db.bookingNights)
          ..where((n) => n.bookingLocalId.equals(bookingId))
          ..where((n) => n.deletedAt.isNull())
          ..orderBy([(n) => OrderingTerm.asc(n.hotelDayKey)]))
        .get();

    final effectiveDate = DateTime.parse(effectiveHotelDay);
    final endDate = endHotelDay != null ? DateTime.parse(endHotelDay) : null;

    double originalTotal = 0;
    double adjustedTotal = 0;
    int nightsAffected = 0;
    final breakdown = <NightBreakdown>[];

    final nightsInRange = nights.where((night) {
      final nightDate = DateTime.parse(night.hotelDayKey);
      return !nightDate.isBefore(effectiveDate) &&
          (endDate == null || !nightDate.isAfter(endDate));
    }).toList();

    for (final night in nights) {
      final nightDate = DateTime.parse(night.hotelDayKey);
      final isInRange = !nightDate.isBefore(effectiveDate) &&
          (endDate == null || !nightDate.isAfter(endDate));

      final double baseRate = night.nightlyRate;
      double adjustmentAmount = 0;
      double finalRate = baseRate;

      if (isInRange) {
        adjustmentAmount = _calculateAdjustmentAmount(
          baseRate: baseRate,
          amount: amount,
          type: type,
          mode: mode,
          totalNights: nightsInRange.length,
        );
        finalRate = (baseRate + adjustmentAmount).clamp(0.0, baseRate * 3);
        nightsAffected++;
      }

      originalTotal += baseRate;
      adjustedTotal += finalRate;

      breakdown.add(NightBreakdown(
        hotelDayKey: night.hotelDayKey,
        baseRate: baseRate,
        adjustment: adjustmentAmount,
        finalRate: finalRate,
      ));
    }

    return AdjustmentPreview(
      originalTotal: originalTotal,
      adjustedTotal: adjustedTotal,
      difference: adjustedTotal - originalTotal,
      nightsAffected: nightsAffected,
      nightlyBreakdown: breakdown,
    );
  }

  double _calculateAdjustmentAmount({
    required double baseRate,
    required int amount,
    required AdjustmentType type,
    required AdjustmentMode mode,
    required int totalNights,
  }) {
    final sign = type == AdjustmentType.discount ? -1.0 : 1.0;
    
    switch (mode) {
      case AdjustmentMode.perNight:
        return sign * amount.toDouble();
      case AdjustmentMode.total:
        if (totalNights <= 0) return 0;
        return sign * (amount.toDouble() / totalNights);
      case AdjustmentMode.percentage:
        return sign * (baseRate * amount / 100);
    }
  }

  Future<BookingPriceAdjustment> applyTemporaryAdjustment({
    required String bookingLocalUuid,
    required int amount,
    required AdjustmentType type,
    required String effectiveHotelDay,
    String? endHotelDay,
    String? reason,
    String? appliedBy,
    AdjustmentMode mode = AdjustmentMode.perNight,
  }) async {
    final booking = await (db.select(db.bookings)
          ..where((b) => b.localUuid.equals(bookingLocalUuid)))
        .getSingleOrNull();
    if (booking == null) {
      throw StateError('Booking not found: $bookingLocalUuid');
    }

    final now = Time.nowEpoch();
    final uuid = IdGen.uuid();

    final adjustment = BookingPriceAdjustmentsCompanion(
      localUuid: Value(uuid),
      bookingLocalUuid: Value(bookingLocalUuid),
      bookingLocalId: Value(booking.id),
      adjustmentType: Value(type.value),
      adjustmentMode: Value(mode.value),
      amount: Value(amount.toDouble()),
      effectiveHotelDay: Value(effectiveHotelDay),
      endHotelDay: Value(endHotelDay),
      isActive: const Value(true),
      reason: Value(reason),
      appliedBy: Value(appliedBy),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
    );

    await db.into(db.bookingPriceAdjustments).insert(adjustment);

    await _recalculateBookingNights(booking.id);

    final result = await (db.select(db.bookingPriceAdjustments)
          ..where((a) => a.localUuid.equals(uuid)))
        .getSingle();

    debugPrint('✅ تم تطبيق تعديل السعر: $uuid للحجز $bookingLocalUuid');

    return result;
  }

  Future<void> cancelAdjustment({
    required String adjustmentUuid,
    String? cancelledBy,
  }) async {
    final adjustment = await (db.select(db.bookingPriceAdjustments)
          ..where((a) => a.localUuid.equals(adjustmentUuid)))
        .getSingleOrNull();
    if (adjustment == null) {
      throw StateError('Adjustment not found: $adjustmentUuid');
    }

    final now = Time.nowEpoch();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await (db.update(db.bookingPriceAdjustments)
          ..where((a) => a.localUuid.equals(adjustmentUuid)))
        .write(BookingPriceAdjustmentsCompanion(
      isActive: const Value(false),
      cancelledAt: Value(nowIso),
      cancelledBy: Value(cancelledBy),
      updatedAt: Value(now),
      lastModified: Value(now),
    ));

    if (adjustment.bookingLocalId != null) {
      await _recalculateBookingNights(adjustment.bookingLocalId!);
    }

    debugPrint('❌ تم إلغاء تعديل السعر: $adjustmentUuid');
  }

  Future<List<BookingPriceAdjustment>> getActiveAdjustments(
      String bookingLocalUuid) async {
    return await (db.select(db.bookingPriceAdjustments)
          ..where((a) => a.bookingLocalUuid.equals(bookingLocalUuid))
          ..where((a) => a.isActive.equals(true))
          ..where((a) => a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.effectiveHotelDay)]))
        .get();
  }

  Future<List<BookingPriceAdjustment>> getAllAdjustments(
      String bookingLocalUuid) async {
    return await (db.select(db.bookingPriceAdjustments)
          ..where((a) => a.bookingLocalUuid.equals(bookingLocalUuid))
          ..where((a) => a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
        .get();
  }

  Future<void> _recalculateBookingNights(int bookingId) async {
    final booking = await (db.select(db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .getSingleOrNull();
    if (booking == null) return;

    await BookingDerivedFieldsService(db).refreshForBooking(
      booking,
      forceRebuild: true,
    );

    debugPrint('🔄 تم إعادة حساب الحجز #$bookingId');
  }

  Future<void> recalculateAfterSync(int bookingId) async {
    await _recalculateBookingNights(bookingId);
  }

  Future<List<Booking>> getLongStayBookingsWithoutSurcharge({
    int minimumNights = 30,
  }) async {
    final now = DateTime.now();
    final cutoffDate = now.subtract(Duration(days: minimumNights));
    final cutoffStr = Time.dateToString(cutoffDate);

    final bookings = await (db.select(db.bookings)
          ..where((b) => b.deletedAt.isNull())
          ..where((b) => b.actualCheckout.isNull())
          ..where((b) => b.checkinDate.isSmallerOrEqualValue(cutoffStr)))
        .get();

    final result = <Booking>[];

    for (final booking in bookings) {
      final hasSurcharge = await (db.select(db.bookingPriceAdjustments)
            ..where((a) => a.bookingLocalId.equals(booking.id))
            ..where((a) => a.adjustmentType.equals(AdjustmentType.surcharge.value))
            ..where((a) => a.isActive.equals(true))
            ..where((a) => a.deletedAt.isNull()))
          .get();

      if (hasSurcharge.isEmpty) {
        result.add(booking);
      }
    }

    return result;
  }

  Future<LostRevenueReport> generateLostRevenueReport({
    String? fromHotelDay,
    String? toHotelDay,
  }) async {
    final query = db.select(db.bookingPriceAdjustments)
      ..where((a) => a.deletedAt.isNull());

    if (fromHotelDay != null) {
      query.where((a) => a.effectiveHotelDay.isBiggerOrEqualValue(fromHotelDay));
    }
    if (toHotelDay != null) {
      query.where((a) => a.effectiveHotelDay.isSmallerOrEqualValue(toHotelDay));
    }

    final adjustments = await query.get();

    final bookingIds = adjustments.map((a) => a.bookingLocalId).whereType<int>().toSet();

    double totalPotentialRevenue = 0;
    double totalActualRevenue = 0;
    double totalLostRevenue = 0;
    double totalGainedRevenue = 0;
    final bookingDetails = <BookingLostRevenue>[];

    for (final bookingId in bookingIds) {
      final booking = await (db.select(db.bookings)
            ..where((b) => b.id.equals(bookingId)))
          .getSingleOrNull();
      if (booking == null) continue;

      final room = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.equals(booking.roomNumber)))
          .getSingleOrNull();
      if (room == null) continue;

      final nights = await (db.select(db.bookingNights)
            ..where((n) => n.bookingLocalId.equals(bookingId))
            ..where((n) => n.deletedAt.isNull()))
          .get();

      final bookingAdjustments = adjustments
          .where((a) => a.bookingLocalId == bookingId)
          .toList();

      final double potentialRevenue = nights.length * room.price;
      final double actualRevenue = nights.fold<double>(
        0,
        (sum, n) => sum + n.nightlyRate,
      );
      double lostRevenue = 0;
      double gainedRevenue = 0;

      final adjustmentSummaries = <AdjustmentSummary>[];

      for (final adj in bookingAdjustments) {
        final effectiveDate = DateTime.parse(adj.effectiveHotelDay);
        final endDate =
            adj.endHotelDay != null ? DateTime.parse(adj.endHotelDay!) : null;

        int nightsAffected = 0;
        for (final night in nights) {
          final nightDate = DateTime.parse(night.hotelDayKey);
          if (!nightDate.isBefore(effectiveDate) &&
              (endDate == null || !nightDate.isAfter(endDate))) {
            nightsAffected++;
          }
        }

        final type = AdjustmentType.fromValue(adj.adjustmentType);
        final double signedAmount = adj.amount.toDouble();
        final double impact = type == AdjustmentType.discount
            ? -signedAmount * nightsAffected
            : signedAmount * nightsAffected;

        if (type == AdjustmentType.discount) {
          lostRevenue += signedAmount * nightsAffected;
        } else {
          gainedRevenue += signedAmount * nightsAffected;
        }

        adjustmentSummaries.add(AdjustmentSummary(
          uuid: adj.localUuid,
          type: type,
          amount: adj.amount.toDouble(),
          effectiveHotelDay: adj.effectiveHotelDay,
          endHotelDay: adj.endHotelDay,
          nightsAffected: nightsAffected,
          totalImpact: impact,
        ));
      }

      totalPotentialRevenue += potentialRevenue;
      totalActualRevenue += actualRevenue;
      totalLostRevenue += lostRevenue;
      totalGainedRevenue += gainedRevenue;

      bookingDetails.add(BookingLostRevenue(
        bookingId: bookingId,
        guestName: booking.guestName,
        roomNumber: booking.roomNumber,
        potentialRevenue: potentialRevenue,
        actualRevenue: actualRevenue,
        lostRevenue: lostRevenue,
        gainedRevenue: gainedRevenue,
        adjustments: adjustmentSummaries,
      ));
    }

    return LostRevenueReport(
      totalPotentialRevenue: totalPotentialRevenue,
      totalActualRevenue: totalActualRevenue,
      totalLostRevenue: totalLostRevenue,
      totalGainedRevenue: totalGainedRevenue,
      bookingDetails: bookingDetails,
    );
  }

  Stream<List<BookingPriceAdjustment>> watchActiveAdjustments(
      String bookingLocalUuid) {
    return (db.select(db.bookingPriceAdjustments)
          ..where((a) => a.bookingLocalUuid.equals(bookingLocalUuid))
          ..where((a) => a.isActive.equals(true))
          ..where((a) => a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.effectiveHotelDay)]))
        .watch();
  }
}
