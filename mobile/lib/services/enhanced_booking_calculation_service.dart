import 'dart:convert';
import 'package:drift/drift.dart' as d;
import '../models/financial_models.dart';
import '../utils/id.dart';
import '../utils/status_utils.dart';
import '../utils/time.dart';
import 'local_db.dart';

class BookingCalculationResult {
  final List<NightlyBreakdown> breakdown;
  final FinancialSummary financialSummary;
  final DateTime checkin;
  final DateTime checkout;
  final bool bookingActive;
  final String stayDurationIso;
  final int? lastNightEpoch;
  final String hotelDayCheckin;
  final String hotelDayCheckout;

  const BookingCalculationResult({
    required this.breakdown,
    required this.financialSummary,
    required this.checkin,
    required this.checkout,
    required this.bookingActive,
    required this.stayDurationIso,
    required this.lastNightEpoch,
    required this.hotelDayCheckin,
    required this.hotelDayCheckout,
  });
}

class EnhancedBookingCalculationService {
  EnhancedBookingCalculationService(this.db);

  final AppDatabase db;

  Future<BookingCalculationResult> calculateForBooking(
    Booking booking, {
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();
    final context = _resolveDateRange(booking, moment);
    final breakdown = await _buildNightlyBreakdown(
      booking,
      context: context,
    );

    final summary = await _buildFinancialSummary(
      booking,
      breakdown: breakdown,
      totalNights: breakdown.length,
    );

    final stayDurationIso =
        '${context.checkin.toIso8601String()}/${context.checkout.toIso8601String()}';
    final lastNightEpoch = _resolveLastNightEpoch(breakdown, context.checkout);

    return BookingCalculationResult(
      breakdown: breakdown,
      financialSummary: summary,
      checkin: context.checkin,
      checkout: context.checkout,
      bookingActive: context.bookingActive,
      stayDurationIso: stayDurationIso,
      lastNightEpoch: lastNightEpoch,
      hotelDayCheckin: Time.hotelDayKey(now: context.checkin),
      hotelDayCheckout: Time.hotelDayKey(now: context.checkout),
    );
  }

  Future<List<NightlyBreakdown>> calculateNightlyBreakdown(
    Booking booking, {
    DateTime? now,
  }) async {
    final context = _resolveDateRange(booking, now ?? DateTime.now());
    return _buildNightlyBreakdown(booking, context: context);
  }

  Future<FinancialSummary> calculateFinancials(
    Booking booking, {
    DateTime? now,
    List<NightlyBreakdown>? breakdown,
  }) async {
    final resolvedBreakdown =
        breakdown ?? await calculateNightlyBreakdown(booking, now: now);
    return _buildFinancialSummary(
      booking,
      breakdown: resolvedBreakdown,
      totalNights: resolvedBreakdown.length,
    );
  }

  Future<void> updateNightlyRecords(
    Booking booking, {
    DateTime? now,
    bool forceRebuild = true,
    List<NightlyBreakdown>? breakdown,
  }) async {
    final context = _resolveDateRange(booking, now ?? DateTime.now());
    final resolvedBreakdown = breakdown ??
        await _buildNightlyBreakdown(
          booking,
          context: context,
        );
    await _replaceBookingNights(
      booking: booking,
      breakdown: resolvedBreakdown,
      forceRebuild: forceRebuild,
    );
  }

  Future<void> recalculateAfterSync(
    int bookingId, {
    DateTime? now,
  }) async {
    final booking =
        await (db.select(db.bookings)..where((b) => b.id.equals(bookingId)))
            .getSingleOrNull();
    if (booking == null) return;

    final calculation = await calculateForBooking(booking, now: now);
    await _replaceBookingNights(
      booking: booking,
      breakdown: calculation.breakdown,
      forceRebuild: true,
    );

    final summary = calculation.financialSummary;
    final remaining = summary.remainingBalance;
    final isFullyPaid = remaining <= 0;

    final int stamp = Time.nowEpoch();
    final String stampIso = DateTime.now().toUtc().toIso8601String();

    await (db.update(db.bookings)..where((b) => b.id.equals(booking.id))).write(
      BookingsCompanion(
        totalDueCached: d.Value(summary.totalDue.toDouble()),
        totalPaidCached: d.Value(summary.totalPaid.toDouble()),
        remainingBalanceCached: d.Value(remaining.toDouble()),
        isFullyPaid: d.Value(isFullyPaid),
        calculatedNights: d.Value(summary.totalNights),
        totalNightsCached: d.Value(summary.totalNights),
        stayDurationIso: d.Value(calculation.stayDurationIso),
        lastNightEpoch: d.Value(calculation.lastNightEpoch),
        hotelDayCheckin: d.Value(calculation.hotelDayCheckin),
        hotelDayCheckout: d.Value(calculation.hotelDayCheckout),
        updatedAt: d.Value(stamp),
        lastModified: d.Value(stamp),
        updatedAtIso: d.Value(stampIso),
        lastModifiedEpoch: d.Value(stamp),
      ),
    );
  }

  Future<List<NightlyBreakdown>> _buildNightlyBreakdown(
    Booking booking, {
    required _BookingDateRange context,
  }) async {
    final room =
        await (db.select(db.rooms)
              ..where((r) => r.roomNumber.equals(booking.roomNumber))
              ..where((r) => r.deletedAt.isNull()))
            .getSingleOrNull();
    final int baseRate = _asInt(room?.price ?? 0);

    final adjustments = await _fetchActiveAdjustments(booking);
    final legacyDiscount =
        booking.discountType == 'total' ? 0 : _asInt(booking.discount);
    final legacyDiscountStart = _parseDateTime(booking.discountStartDate);

    final segments = _buildNightSegments(context.checkin, context.checkout);
    final breakdown = <NightlyBreakdown>[];

    for (final segment in segments) {
      final nightKey = segment.hotelDayKey;
      final nightDate = DateTime.parse(nightKey);

      final applied = <AppliedAdjustment>[];
      int adjustmentTotal = 0;

      for (final adj in adjustments) {
        final effectiveDate = DateTime.parse(adj.effectiveHotelDay);
        final endDate = adj.endHotelDay != null
            ? DateTime.parse(adj.endHotelDay!)
            : null;
        if (!_isWithinRange(nightDate, effectiveDate, endDate)) {
          continue;
        }
        final rawAmount = _asInt(adj.amount);
        final isDiscount = adj.adjustmentType == 0;
        
        int adjAmount = rawAmount;
        if (adj.adjustmentMode == 'total') {
          final nightsInRange = _countNightsInRange(
            segments,
            effectiveDate,
            endDate,
          );
          if (nightsInRange > 0) {
            adjAmount = (rawAmount / nightsInRange).round();
          }
        }
        
        final signedAmount = isDiscount ? -adjAmount : adjAmount;
        adjustmentTotal += signedAmount;
        applied.add(
          AppliedAdjustment(
            uuid: adj.localUuid,
            type: isDiscount ? 'discount' : 'surcharge',
            amount: signedAmount,
            reason: adj.reason,
            appliedBy: adj.appliedBy,
          ),
        );
      }

      if (legacyDiscount > 0) {
        if (_isLegacyDiscountApplicable(nightDate, legacyDiscountStart)) {
          final signed = -legacyDiscount;
          adjustmentTotal += signed;
          applied.add(
            AppliedAdjustment(
              uuid: 'legacy_discount',
              type: 'legacy_discount',
              amount: signed,
              reason: null,
              appliedBy: null,
            ),
          );
        }
      }

      final int finalRate = (baseRate + adjustmentTotal).clamp(0, baseRate * 3);

      breakdown.add(
        NightlyBreakdown(
          hotelDayKey: nightKey,
          nightStart: segment.start,
          nightEnd: segment.end,
          baseRate: baseRate,
          adjustmentAmount: adjustmentTotal,
          finalRate: finalRate,
          appliedAdjustments: applied,
        ),
      );
    }

    if (breakdown.isEmpty) {
      breakdown.add(
        NightlyBreakdown(
          hotelDayKey: Time.dateToString(
            DateTime(context.checkin.year, context.checkin.month, context.checkin.day),
          ),
          nightStart: context.checkin,
          nightEnd: context.checkout,
          baseRate: baseRate,
          adjustmentAmount: 0,
          finalRate: baseRate,
          appliedAdjustments: const [],
        ),
      );
    }

    return breakdown;
  }

  Future<FinancialSummary> _buildFinancialSummary(
    Booking booking, {
    required List<NightlyBreakdown> breakdown,
    required int totalNights,
  }) async {
    final subtotal = breakdown.fold<int>(
      0,
      (sum, night) => sum + night.baseRate,
    );
    int totalAdjustments = breakdown.fold<int>(
      0,
      (sum, night) => sum + night.adjustmentAmount,
    );

    int totalDue = breakdown.fold<int>(
      0,
      (sum, night) => sum + night.finalRate,
    );

    final totalDiscount =
        booking.discountType == 'total' ? _asInt(booking.discount) : 0;
    if (totalDiscount > 0) {
      totalDue = (totalDue - totalDiscount).clamp(0, totalDue);
      totalAdjustments -= totalDiscount;
    }

    final totalPaid = await _getTotalPayments(booking);
    final remaining = (totalDue - totalPaid).clamp(0, totalDue);

    return FinancialSummary(
      subtotal: subtotal,
      totalAdjustments: totalAdjustments,
      totalDue: totalDue,
      totalPaid: totalPaid,
      remainingBalance: remaining,
      totalNights: totalNights,
      isFullyPaid: remaining <= 0,
    );
  }

  Future<int> _getTotalPayments(Booking booking) async {
    final payments =
        await (db.select(db.payments)
              ..where(
                (p) =>
                    (p.bookingLocalId.equals(booking.id) |
                    p.bookingUuidCache.equals(booking.localUuid)),
              )
              ..where((p) => p.deletedAt.isNull())
              ..where((p) => p.isPendingBalance.equals(false))
              ..where(
                (p) =>
                    p.revenueType.equals('room') |
                    p.revenueType.equals('') |
                    p.revenueType.isNull(),
              ))
            .get();

    return payments.fold<int>(0, (sum, p) => sum + _asInt(p.amount));
  }

  Future<List<BookingPriceAdjustment>> _fetchActiveAdjustments(
    Booking booking,
  ) async {
    final raw = await (db.select(db.bookingPriceAdjustments)
          ..where(
            (a) =>
                (a.bookingLocalId.equals(booking.id) |
                a.bookingLocalUuid.equals(booking.localUuid)),
          )
          ..where((a) => a.isActive.equals(true))
          ..where((a) => a.deletedAt.isNull()))
        .get();

    // ─── حماية متعددة الطبقات ضد التعديلات الوهمية ───

    final bookingDiscount = _asInt(booking.discount);
    final isDiscountTotal = booking.discountType == 'total';

    return raw.where((adj) {
      // ① استبعاد سجلات legacy_discount دائماً
      //    يتم تطبيق التخفيض القديم عبر المسار المخصص في
      //    _buildNightlyBreakdown (سطور 218-232).
      //    تمرير هذه السجلات هنا يُسبب تخفيضاً مزدوجاً (BUG #2).
      if (adj.reason == 'legacy_discount') {
        return false;
      }

      // ② التحقق من roomNumber — تجنب تطبيق تخفيض من حجز آخر
      final adjRoom = adj.roomNumber?.trim();
      if (adjRoom == null || adjRoom.isEmpty) return false;
      final room = booking.roomNumber.trim();
      if (adjRoom != room) return false;

      // ③ حماية: إذا لم يكن هناك تخفيض على الحجز (discount = 0)
      //    فتجنب تطبيق أي تعديل بـ amount سلبي بدون سبب واضح
      if (bookingDiscount <= 0 &&
          adj.adjustmentType == 0 &&
          adj.reason == null) {
        // سجل تخفيض يدوي بدون سبب + لا يوجد تخفيض على الحجز
        // = سجل يتيم محتمل → تجاهله للحماية
        return false;
      }

      return true;
    }).toList();
  }

  Future<void> _replaceBookingNights({
    required Booking booking,
    required List<NightlyBreakdown> breakdown,
    required bool forceRebuild,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final stamp = nowUtc.millisecondsSinceEpoch ~/ 1000;
    final stampIso = nowUtc.toIso8601String();

    var shouldRebuild = forceRebuild;
    if (!shouldRebuild) {
      final existing =
          await (db.select(db.bookingNights)
                ..where((n) => n.bookingLocalId.equals(booking.id))
                ..where((n) => n.deletedAt.isNull()))
              .get();
      if (existing.length != breakdown.length) {
        shouldRebuild = true;
      } else {
        final byDay = {
          for (final night in existing) night.hotelDayKey: night,
        };
        for (final night in breakdown) {
          final current = byDay[night.hotelDayKey];
          if (current == null) {
            shouldRebuild = true;
            break;
          }
          final appliedJson = night.appliedAdjustments.isEmpty
              ? null
              : jsonEncode(
                  night.appliedAdjustments.map((a) => a.toJson()).toList(),
                );
          final appliedUuid = night.appliedAdjustments.length == 1
              ? night.appliedAdjustments.first.uuid
              : null;
          if (current.nightlyRate != night.finalRate.toDouble() ||
              current.baseRate != night.baseRate.toDouble() ||
              current.adjustment != night.adjustmentAmount.toDouble() ||
              current.finalRate != night.finalRate.toDouble() ||
              current.appliedAdjustmentUuid != appliedUuid ||
              current.appliedAdjustmentsJson != appliedJson) {
            shouldRebuild = true;
            break;
          }
        }
      }
    }

    await db.transaction(() async {
      if (shouldRebuild) {
        await (db.delete(db.bookingNights)
              ..where((n) => n.bookingLocalId.equals(booking.id)))
            .go();
      }

      int sequence = 0;
      await db.batch((batch) {
        for (final night in breakdown) {
          sequence += 1;
          final appliedJson = night.appliedAdjustments.isEmpty
              ? null
              : jsonEncode(
                  night.appliedAdjustments.map((a) => a.toJson()).toList(),
                );
          final appliedUuid = night.appliedAdjustments.length == 1
              ? night.appliedAdjustments.first.uuid
              : null;

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
              hotelDayKey: d.Value(night.hotelDayKey),
              nightStart: d.Value(night.nightStart.toIso8601String()),
              nightEnd: d.Value(night.nightEnd.toIso8601String()),
              nightlyRate: d.Value(night.finalRate.toDouble()),
              baseRate: d.Value(night.baseRate.toDouble()),
              adjustment: d.Value(night.adjustmentAmount.toDouble()),
              finalRate: d.Value(night.finalRate.toDouble()),
              appliedAdjustmentUuid: d.Value(appliedUuid),
              appliedAdjustmentsJson: d.Value(appliedJson),
              sequence: d.Value(sequence),
              isProcessedByAutoFix: const d.Value(false),
            ),
            mode: d.InsertMode.insertOrReplace,
          );
        }
      });
    });
  }

  _BookingDateRange _resolveDateRange(Booking booking, DateTime moment) {
    final checkin = _parseDateTime(booking.checkinDate) ?? moment;
    final plannedCheckout = _parseDateTime(booking.checkoutDate);
    final actualCheckout = _parseDateTime(booking.actualCheckout);
    final bookingActive =
        actualCheckout == null && StatusUtils.isBookingActive(booking);

    // Resolve effective checkout:
    // 1. Actual checkout exists → use it (unless it's in the future, then use moment)
    // 2. Active booking (no actual checkout) → ALWAYS use moment to ensure dynamic calculation
    // 3. Otherwise (e.g. cancelled/provisional) → use planned checkout if in the past, else moment
    DateTime checkout;
    if (actualCheckout != null) {
      checkout = actualCheckout.isBefore(moment) ? actualCheckout : moment;
    } else if (bookingActive) {
      // For active guests, always calculate up to the current moment
      // This ensures that if they stay past 14:00, a new night is added automatically
      checkout = moment;
    } else if (plannedCheckout != null && plannedCheckout.isBefore(moment)) {
      checkout = plannedCheckout;
    } else {
      checkout = moment;
    }

    if (!checkout.isAfter(checkin)) {
      checkout = checkin.add(const Duration(minutes: 1));
    }

    return _BookingDateRange(
      checkin: checkin,
      checkout: checkout,
      bookingActive: bookingActive,
    );
  }

  bool _isLegacyDiscountApplicable(
    DateTime nightDate,
    DateTime? discountStartDate,
  ) {
    if (discountStartDate == null) return true;
    final nightDay = DateTime(nightDate.year, nightDate.month, nightDate.day);
    final discountDay = DateTime(discountStartDate.year, discountStartDate.month, discountStartDate.day);
    return !nightDay.isBefore(discountDay);
  }

  bool _isWithinRange(
    DateTime nightDate,
    DateTime effectiveDate,
    DateTime? endDate,
  ) {
    if (nightDate.isBefore(effectiveDate)) return false;
    if (endDate != null && nightDate.isAfter(endDate)) return false;
    return true;
  }

  int _countNightsInRange(
    List<_NightSegment> segments,
    DateTime effectiveDate,
    DateTime? endDate,
  ) {
    int count = 0;
    for (final segment in segments) {
      final nightDate = DateTime.parse(segment.hotelDayKey);
      if (_isWithinRange(nightDate, effectiveDate, endDate)) {
        count++;
      }
    }
    return count;
  }

  int? _resolveLastNightEpoch(
    List<NightlyBreakdown> nights,
    DateTime fallback,
  ) {
    if (nights.isEmpty) {
      return fallback.millisecondsSinceEpoch ~/ 1000;
    }
    DateTime? latest;
    for (final night in nights) {
      if (latest == null || night.nightEnd.isAfter(latest)) {
        latest = night.nightEnd;
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
    final withSeconds =
        normalized.length == 16 ? '${normalized}:00' : normalized;
    try {
      return DateTime.parse(withSeconds);
    } catch (_) {
      return null;
    }
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  List<_NightSegment> _buildNightSegments(
    DateTime checkin,
    DateTime checkout, {
    int cutoffHour = 14,
  }) {
    final segments = <_NightSegment>[];

    // استخدام المنطق الموحد لحساب عدد الليالي بناءً على الساعة 14:00
    int totalNights = Time.nightsWithCutoff(checkin, checkout: checkout, cutoffHour: cutoffHour);

    // حساب بداية "يوم الفندق" لعملية تسجيل الدخول
    DateTime startOfCheckinHotelDay = DateTime(
      checkin.year,
      checkin.month,
      checkin.day,
      cutoffHour,
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

class _BookingDateRange {
  const _BookingDateRange({
    required this.checkin,
    required this.checkout,
    required this.bookingActive,
  });

  final DateTime checkin;
  final DateTime checkout;
  final bool bookingActive;
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
