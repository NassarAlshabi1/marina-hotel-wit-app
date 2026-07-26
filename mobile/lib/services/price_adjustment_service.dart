import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../utils/hotel_time_engine.dart';
import '../utils/time.dart';
import 'auto_backup_manager.dart';
import 'booking_derived_fields_service.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';

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
    final effectiveHotelDay = HotelTimeEngine.getHotelDayKey(dateTime: effectiveDate);

    final room = await (db.select(db.rooms)..where((r) => r.roomNumber.equals(roomNumber))).getSingleOrNull();

    if (room == null) {
      return PriceAdjustmentResult(success: false, error: 'الغرفة غير موجودة: $roomNumber');
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

    // ─── إنشاء outbox entry لمزامنة price_adjustments ───
    // بدون هذا الإدخال، تغييرات سعر الغرفة لا تُرفع إلى Appwrite
    final outboxDao = OutboxDao(db);
    await outboxDao.merge(
      entity: 'price_adjustments',
      op: 'create',
      localUuid: adjustmentUuid,
      payload: {
        'targetType': 'room',
        'targetUuid': room.localUuid,
        'adjustmentType': 'price_change',
        'previousValue': oldPrice.round(),
        'newValue': newPrice.round(),
        'reason': reason,
        'effectiveDate': effectiveDate.toIso8601String(),
        'appliedBy': appliedBy,
        'hotelDayKey': effectiveHotelDay,
        'isReversed': false,
      },
      clientTs: Time.nowEpoch(),
    );

    // ─── إصلاح BUG #1: تحديث سعر الغرفة في جدول rooms ───
    // كان الخطأ: لم يُحدَّث room.price، فأي إعادة حساب عبر
    // EnhancedBookingCalculationService كانت تقرأ السعر القديم
    // وتمسح تعديلات nightlyRate اليدوية.
    //
    // ─── إصلاح BUG المزامنة: إنشاء outbox entry لتحديث الغرفة ───
    // التحديث المباشر لـ rooms يتجاوز RoomsDao ولا يُنشئ outbox entry،
    // لذلك نُنشئه يدوياً لضمان مزامنة السعر الجديد.
    // ✅ bump version لتفعيل OCC عند الدفع لاحقاً
    await (db.update(db.rooms)..where((r) => r.roomNumber.equals(roomNumber))).write(
      RoomsCompanion(
        price: Value(newPrice),
        updatedAt: Value(Time.nowEpoch()),
        lastModified: Value(Time.nowEpoch()),
        version: Value(room.version + 1),
      ),
    );

    // إنشاء outbox entry لتحديث سعر الغرفة
    await outboxDao.merge(
      entity: 'rooms',
      op: 'update',
      localUuid: room.localUuid,
      serverId: room.serverId,
      payload: {'room_number': roomNumber, 'price': newPrice},
      clientTs: Time.nowEpoch(),
    );

    final activeBookings = await _getActiveBookingsForRoom(roomNumber);

    int nightsUpdated = 0;
    int bookingsAffected = 0;
    final auditEntries = <String>[];

    for (final booking in activeBookings) {
      // حساب عدد الليالي المتأثرة (قبل إعادة الحساب)
      final nightsBefore =
          await (db.select(db.bookingNights)
                ..where((n) => n.bookingLocalId.equals(booking.id))
                ..where((n) => n.deletedAt.isNull())
                ..where((n) => n.hotelDayKey.isBiggerOrEqualValue(effectiveHotelDay)))
              .get();

      final oldTotal = nightsBefore.fold<double>(0, (sum, n) => sum + n.nightlyRate);

      // ─── إعادة حساب عبر EnhancedBookingCalculationService ───
      // هذه الدالة تستخدم room.price الجديد كـ baseRate وتطبق
      // التخفيضات (legacy + booking_price_adjustments) بشكل صحيح
      // وتُحدّث جميع حقول booking_nights (baseRate, adjustment, finalRate, ...)
      try {
        await BookingDerivedFieldsService(db).refreshForBookingId(booking.id, forceRebuild: true);
      } catch (e) {
        debugPrint('⚠️ خطأ في إعادة حساب حجز ${booking.id}: $e');
      }

      // حساب النتيجة بعد إعادة الحساب
      final nightsAfter =
          await (db.select(db.bookingNights)
                ..where((n) => n.bookingLocalId.equals(booking.id))
                ..where((n) => n.deletedAt.isNull()))
              .get();

      final newTotal = nightsAfter.fold<double>(0, (sum, n) => sum + n.nightlyRate);
      final nightsAffected = nightsBefore.length;

      if (nightsAffected > 0 && (oldTotal - newTotal).abs() > 0.01) {
        bookingsAffected++;
        nightsUpdated += nightsAffected;
        auditEntries.add(
          'حجز ${booking.guestName}: ${oldTotal.toStringAsFixed(0)} → ${newTotal.toStringAsFixed(0)} ($nightsAffected ليلة)',
        );
      }
    }

    for (final entry in auditEntries) {
      await _createAuditLog(action: 'price_adjustment_applied', details: entry, performedBy: appliedBy);
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

  Future<void> _createAuditLog({required String action, required String details, required String performedBy}) async {
    final now = DateTime.now();
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion(
            localUuid: Value(_uuid.v4()),
            operationType: Value(action),
            entityType: const Value('booking_nights'),
            entityUuid: const Value(''),
            previousState: const Value(null),
            newState: Value(details),
            performedBy: Value(performedBy),
            deviceId: const Value('app'),
            hotelDayKey: Value(HotelTimeEngine.getHotelDayKey(dateTime: now)),
            timestamp: Value(Time.nowEpoch()),
            timestampIso: Value(now.toIso8601String()),
            isFinancial: const Value(true),
            createdAt: Value(Time.nowEpoch()),
          ),
        );
  }

  Future<List<PriceAdjustment>> getAdjustmentsForRoom(String roomUuid) async {
    return (db.select(db.priceAdjustments)
          ..where((p) => p.targetType.equals('room'))
          ..where((p) => p.targetUuid.equals(roomUuid))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .get();
  }

  Future<List<PriceAdjustment>> getAdjustmentsInDateRange(String startDate, String endDate) async {
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
    final effectiveHotelDay = HotelTimeEngine.getHotelDayKey(dateTime: effectiveDate);

    final activeBookings = await _getActiveBookingsForRoom(roomNumber);

    int totalNightsAffected = 0;
    double totalOldAmount = 0;
    double totalNewAmount = 0;
    final bookingPreviews = <Map<String, dynamic>>[];

    for (final booking in activeBookings) {
      final nights =
          await (db.select(db.bookingNights)
                ..where((n) => n.bookingLocalId.equals(booking.id))
                ..where((n) => n.deletedAt.isNull())
                ..where((n) => n.hotelDayKey.isBiggerOrEqualValue(effectiveHotelDay)))
              .get();

      if (nights.isEmpty) {
        continue;
      }

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
