import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'local_db.dart';
import 'auto_backup_manager.dart';
import '../utils/time.dart';

class PriceAdjustmentService {

  PriceAdjustmentService(this.db);
  final AppDatabase db;
  static const _uuid = Uuid();

  Future<PriceAdjustmentResult> applyRoomPriceChange({
    required String roomNumber,
    required double oldPrice,
    required double newPrice,
    required String appliedBy,
    String? reason,
    DateTime? effectiveFrom,
  }) async {
    final now = DateTime.now();
    final effectiveDate = effectiveFrom ?? now;
    final effectiveHotelDay = Time.hotelDayKey(now: effectiveDate);

    final room = await (db.select(db.rooms)
          ..where((r) => r.roomNumber.equals(roomNumber)))
        .getSingleOrNull();

    if (room == null) {
      return PriceAdjustmentResult(
        success: false,
        error: 'الغرفة غير موجودة: $roomNumber',
      );
    }

    final adjustmentUuid = _uuid.v4();
    final adjustmentRecord = PriceAdjustmentsCompanion(
      localUuid: Value(adjustmentUuid),
      createdAt: Value(Time.nowEpoch()),
      updatedAt: Value(Time.nowEpoch()),
      lastModified: Value(Time.nowEpoch()),
      targetType: const Value('room'),
      targetUuid: Value(room.localUuid),
      adjustmentType: const Value('price_change'),
      previousValue: Value(oldPrice.round()),
      newValue: Value(newPrice.round()),
      reason: Value(reason),
      effectiveDate: Value(effectiveDate.toIso8601String()),
      appliedBy: Value(appliedBy),
      hotelDayKey: Value(effectiveHotelDay),
      isReversed: const Value(false),
    );

    await db.into(db.priceAdjustments).insert(adjustmentRecord);

    final activeBookings = await _getActiveBookingsForRoom(roomNumber);
    
    int nightsUpdated = 0;
    int bookingsAffected = 0;
    final auditEntries = <String>[];

    for (final booking in activeBookings) {
      final result = await _updateBookingNightsFromDate(
        booking: booking,
        newPrice: newPrice,
        effectiveHotelDay: effectiveHotelDay,
        adjustmentUuid: adjustmentUuid,
        appliedBy: appliedBy,
      );
      
      if (result.nightsUpdated > 0) {
        bookingsAffected++;
        nightsUpdated += result.nightsUpdated;
        auditEntries.addAll(result.auditEntries);

        await _recalculateBookingTotals(booking);
      }
    }

    for (final entry in auditEntries) {
      await _createAuditLog(
        action: 'price_adjustment_applied',
        details: entry,
        performedBy: appliedBy,
      );
    }

    await AutoBackupManager.instance.onDataChange(
      'price_adjustments',
      'INSERT',
      recordData: adjustmentRecord.toColumns(false),
    );

    return PriceAdjustmentResult(
      success: true,
      adjustmentUuid: adjustmentUuid,
      bookingsAffected: bookingsAffected,
      nightsUpdated: nightsUpdated,
      auditEntries: auditEntries,
    );
  }

  Future<List<Booking>> _getActiveBookingsForRoom(String roomNumber) async {
    final activeStatuses = ['مؤكد', 'confirmed', 'نشط', 'active', 'مسجل دخول', 'checked_in'];
    
    return (db.select(db.bookings)
          ..where((b) => b.roomNumber.equals(roomNumber))
          ..where((b) => b.deletedAt.isNull())
          ..where((b) => b.actualCheckout.isNull())
          ..where((b) => b.status.isIn(activeStatuses)))
        .get();
  }

  Future<_NightUpdateResult> _updateBookingNightsFromDate({
    required Booking booking,
    required double newPrice,
    required String effectiveHotelDay,
    required String adjustmentUuid,
    required String appliedBy,
  }) async {
    final nights = await (db.select(db.bookingNights)
          ..where((n) => n.bookingLocalId.equals(booking.id))
          ..where((n) => n.deletedAt.isNull())
          ..where((n) => n.hotelDayKey.isBiggerOrEqualValue(effectiveHotelDay)))
        .get();

    int updated = 0;
    final entries = <String>[];

    for (final night in nights) {
      final oldRate = night.nightlyRate;
      
      double adjustedRate = newPrice;
      if (booking.discount > 0 && booking.discountType != 'total') {
        final discountStartDate = booking.discountStartDate != null
            ? DateTime.tryParse(booking.discountStartDate!)
            : null;
        
        if (discountStartDate != null) {
          final discountHotelDay = Time.hotelDayKey(now: discountStartDate);
          if (night.hotelDayKey.compareTo(discountHotelDay) >= 0) {
            adjustedRate = (newPrice - booking.discount).clamp(0.0, newPrice);
          }
        } else {
          adjustedRate = (newPrice - booking.discount).clamp(0.0, newPrice);
        }
      }

      adjustedRate = double.parse(adjustedRate.toStringAsFixed(2));

      if ((oldRate - adjustedRate).abs() > 0.001) {
        await (db.update(db.bookingNights)
              ..where((n) => n.id.equals(night.id)))
            .write(BookingNightsCompanion(
              nightlyRate: Value(adjustedRate),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ));

        updated++;
        entries.add(
          'حجز ${booking.guestName} - ليلة ${night.hotelDayKey}: '
          '${oldRate.toStringAsFixed(0)} → ${adjustedRate.toStringAsFixed(0)}',
        );
      }
    }

    return _NightUpdateResult(nightsUpdated: updated, auditEntries: entries);
  }

  Future<void> _recalculateBookingTotals(Booking booking) async {
    final nights = await (db.select(db.bookingNights)
          ..where((n) => n.bookingLocalId.equals(booking.id))
          ..where((n) => n.deletedAt.isNull()))
        .get();

    final double totalNightAmount = nights.fold<double>(
      0.0,
      (sum, n) => sum + n.nightlyRate,
    );

    double totalDue = totalNightAmount;
    if (booking.discount > 0 && booking.discountType == 'total') {
      totalDue = (totalNightAmount - booking.discount).clamp(0.0, totalNightAmount);
    }
    totalDue = double.parse(totalDue.toStringAsFixed(2));

    final payments = await (db.select(db.payments)
          ..where((p) => p.bookingLocalId.equals(booking.id))
          ..where((p) => p.deletedAt.isNull()))
        .get();

    final totalPaid = payments.fold<double>(0.0, (sum, p) => sum + p.amount);
    final remaining = double.parse((totalDue - totalPaid).toStringAsFixed(2));

    await (db.update(db.bookings)..where((b) => b.id.equals(booking.id))).write(
      BookingsCompanion(
        totalNightsCached: Value(nights.length),
        totalDueCached: Value(totalDue),
        totalPaidCached: Value(totalPaid),
        remainingBalanceCached: Value(remaining),
        isFullyPaid: Value(remaining <= 0),
        updatedAt: Value(Time.nowEpoch()),
        lastModified: Value(Time.nowEpoch()),
      ),
    );
  }

  Future<void> _createAuditLog({
    required String action,
    required String details,
    required String performedBy,
  }) async {
    final now = DateTime.now();
    await db.into(db.auditLogs).insert(AuditLogsCompanion(
      localUuid: Value(_uuid.v4()),
      operationType: Value(action),
      entityType: const Value('booking_nights'),
      entityUuid: const Value(''),
      previousState: const Value(null),
      newState: Value(details),
      performedBy: Value(performedBy),
      deviceId: const Value('app'),
      hotelDayKey: Value(Time.hotelDayKey(now: now)),
      timestamp: Value(Time.nowEpoch()),
      timestampIso: Value(now.toIso8601String()),
      isFinancial: const Value(true),
      createdAt: Value(Time.nowEpoch()),
    ));
  }

  Future<List<PriceAdjustment>> getAdjustmentsForRoom(String roomUuid) async {
    return (db.select(db.priceAdjustments)
          ..where((p) => p.targetType.equals('room'))
          ..where((p) => p.targetUuid.equals(roomUuid))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .get();
  }

  Future<List<PriceAdjustment>> getAdjustmentsInDateRange(
    String startDate,
    String endDate,
  ) async {
    return (db.select(db.priceAdjustments)
          ..where((p) => p.hotelDayKey.isBiggerOrEqualValue(startDate))
          ..where((p) => p.hotelDayKey.isSmallerOrEqualValue(endDate))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .get();
  }

  Future<Map<String, dynamic>> previewPriceChange({
    required String roomNumber,
    required double newPrice,
    DateTime? effectiveFrom,
  }) async {
    final effectiveDate = effectiveFrom ?? DateTime.now();
    final effectiveHotelDay = Time.hotelDayKey(now: effectiveDate);

    final activeBookings = await _getActiveBookingsForRoom(roomNumber);
    
    int totalNightsAffected = 0;
    double totalOldAmount = 0;
    double totalNewAmount = 0;
    final bookingPreviews = <Map<String, dynamic>>[];

    for (final booking in activeBookings) {
      final nights = await (db.select(db.bookingNights)
            ..where((n) => n.bookingLocalId.equals(booking.id))
            ..where((n) => n.deletedAt.isNull())
            ..where((n) => n.hotelDayKey.isBiggerOrEqualValue(effectiveHotelDay)))
          .get();

      if (nights.isEmpty) continue;

      double bookingOldTotal = 0;
      double bookingNewTotal = 0;

      for (final night in nights) {
        bookingOldTotal += night.nightlyRate;
        
        double adjustedRate = newPrice;
        if (booking.discount > 0 && booking.discountType != 'total') {
          adjustedRate = (newPrice - booking.discount).clamp(0.0, newPrice);
        }
        bookingNewTotal += adjustedRate;
      }

      totalNightsAffected += nights.length;
      totalOldAmount += bookingOldTotal;
      totalNewAmount += bookingNewTotal;

      bookingPreviews.add({
        'guestName': booking.guestName,
        'bookingUuid': booking.localUuid,
        'nightsAffected': nights.length,
        'oldTotal': bookingOldTotal,
        'newTotal': bookingNewTotal,
        'difference': bookingNewTotal - bookingOldTotal,
      });
    }

    return {
      'roomNumber': roomNumber,
      'effectiveDate': effectiveDate.toIso8601String(),
      'effectiveHotelDay': effectiveHotelDay,
      'bookingsAffected': activeBookings.length,
      'totalNightsAffected': totalNightsAffected,
      'totalOldAmount': totalOldAmount,
      'totalNewAmount': totalNewAmount,
      'totalDifference': totalNewAmount - totalOldAmount,
      'bookings': bookingPreviews,
    };
  }
}

class PriceAdjustmentResult {

  PriceAdjustmentResult({
    required this.success,
    this.error,
    this.adjustmentUuid,
    this.bookingsAffected = 0,
    this.nightsUpdated = 0,
    this.auditEntries = const [],
  });
  final bool success;
  final String? error;
  final String? adjustmentUuid;
  final int bookingsAffected;
  final int nightsUpdated;
  final List<String> auditEntries;
}

class _NightUpdateResult {

  _NightUpdateResult({
    required this.nightsUpdated,
    required this.auditEntries,
  });
  final int nightsUpdated;
  final List<String> auditEntries;
}
