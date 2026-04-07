import 'dart:async';

import 'package:drift/drift.dart' as d;
import 'hotel_time_engine.dart';
import 'local_db.dart';
import 'status_utils.dart';

/// Reactive model combining raw booking data with computed financial values.
///
/// All computed fields (days, total, paid, remaining) are derived at read time
/// from raw stored data. They are NEVER persisted to the database.
class BookingWithPayments {
  final Booking booking;
  final int days;
  final int pricePerNight;
  final int totalDue;
  final int totalPaid;
  final int remainingBalance;
  final bool isFullyPaid;
  final bool isActive;
  final DateTime computedCheckIn;
  final DateTime? computedCheckOut;

  const BookingWithPayments({
    required this.booking,
    required this.days,
    required this.pricePerNight,
    required this.totalDue,
    required this.totalPaid,
    required this.remainingBalance,
    required this.isFullyPaid,
    required this.isActive,
    required this.computedCheckIn,
    this.computedCheckOut,
  });

  /// Is the booking overdue (past expected checkout with remaining balance)?
  bool get isOverdue {
    if (!isActive) return false;
    if (remainingBalance <= 0) return false;
    final now = DateTime.now();
    final plannedCheckout = _parseDate(booking.checkoutDate);
    if (plannedCheckout == null) return false;
    return now.isAfter(plannedCheckout);
  }
}

/// Service that provides reactive streams for bookings with computed payments.
///
/// All financial values are computed client-side from raw data.
/// This service does NOT store any computed values.
class BookingComputedStreamService {
  BookingComputedStreamService(this.db);

  final AppDatabase db;

  /// Watches a single booking by local ID and emits updated [BookingWithPayments].
  ///
  /// The stream re-emits whenever the booking row or any related payment changes.
  Stream<BookingWithPayments?> watchBookingWithPayments(int bookingId) {
    // Use a combined query approach - watch the booking directly
    final bookingQuery = (db.select(db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .watchSingleOrNull();

    return bookingQuery.asyncMap((booking) async {
      if (booking == null) return null;
      return await _buildBookingWithPayments(booking);
    });
  }

  /// Watches a single booking by UUID and emits updated [BookingWithPayments].
  Stream<BookingWithPayments?> watchBookingByUuid(String uuid) {
    final bookingQuery = (db.select(db.bookings)
          ..where((b) => b.localUuid.equals(uuid)))
        .watchSingleOrNull();

    return bookingQuery.asyncMap((booking) async {
      if (booking == null) return null;
      return await _buildBookingWithPayments(booking);
    });
  }

  /// Watches all active bookings with computed payments.
  ///
  /// Active = checked-in and not checked out.
  Stream<List<BookingWithPayments>> watchActiveBookingsWithPayments() {
    final activeQuery = (db.select(db.bookings)
          ..where((b) => b.status.equals('checked_in'))
          ..where((b) => b.actualCheckout.isNull())
          ..where((b) => b.deletedAt.isNull())
          ..orderBy([(b) => d.OrderingTerm.asc(b.id)]))
        .watch();

    return activeQuery.asyncMap((bookings) async {
      final results = <BookingWithPayments>[];
      for (final booking in bookings) {
        final computed = await _buildBookingWithPayments(booking);
        if (computed != null) results.add(computed);
      }
      return results;
    });
  }

  /// Watches all bookings for a specific room number.
  Stream<List<BookingWithPayments>> watchBookingsByRoom(String roomNumber) {
    final query = (db.select(db.bookings)
          ..where((b) => b.roomNumber.equals(roomNumber))
          ..where((b) => b.deletedAt.isNull())
          ..orderBy([(b) => d.OrderingTerm.desc(b.id)]))
        .watch();

    return query.asyncMap((bookings) async {
      final results = <BookingWithPayments>[];
      for (final booking in bookings) {
        final computed = await _buildBookingWithPayments(booking);
        if (computed != null) results.add(computed);
      }
      return results;
    });
  }

  /// Builds a [BookingWithPayments] from raw data (non-streaming, one-shot).
  Future<BookingWithPayments?> buildBookingWithPayments(int bookingId) async {
    final booking = await (db.select(db.bookings)
          ..where((b) => b.id.equals(bookingId)))
        .getSingleOrNull();
    if (booking == null) return null;
    return _buildBookingWithPayments(booking);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<BookingWithPayments> _buildBookingWithPayments(
    Booking booking,
  ) async {
    final checkIn = _parseDate(booking.checkinDate) ?? DateTime.now();
    final plannedCheckOut = _parseDate(booking.checkoutDate);
    final actualCheckOut = _parseDate(booking.actualCheckout);
    final isActive = actualCheckOut == null &&
        StatusUtils.isBookingActive(booking);

    final effectiveCheckOut = actualCheckOut ?? plannedCheckOut;
    final days = HotelTimeEngine.calculateDays(
      checkIn,
      checkOut: isActive ? null : effectiveCheckOut,
    );

    // Get room price
    final room = await (db.select(db.rooms)
          ..where((r) => r.roomNumber.equals(booking.roomNumber))
          ..where((r) => r.deletedAt.isNull()))
        .getSingleOrNull();
    final pricePerNight = (room?.price ?? 0).round();

    // Calculate total due (days * price, minus total-type discount)
    int totalDue = days * pricePerNight;
    final discount = (booking.discount ?? 0).round();
    if (booking.discountType == 'total' && discount > 0) {
      totalDue = (totalDue - discount).clamp(0, totalDue);
    }

    // Sum payments
    final totalPaid = await _sumPaymentsForBooking(booking);
    final remaining = (totalDue - totalPaid).clamp(0, totalDue);

    return BookingWithPayments(
      booking: booking,
      days: days,
      pricePerNight: pricePerNight,
      totalDue: totalDue,
      totalPaid: totalPaid,
      remainingBalance: remaining,
      isFullyPaid: remaining <= 0,
      isActive: isActive,
      computedCheckIn: checkIn,
      computedCheckOut: effectiveCheckOut,
    );
  }

  Future<int> _sumPaymentsForBooking(Booking booking) async {
    final payments = await (db.select(db.payments)
          ..where(
            (p) =>
                (p.bookingLocalId.equals(booking.id) |
                p.bookingUuidCache.equals(booking.localUuid)),
          )
          ..where((p) => p.deletedAt.isNull())
          ..where((p) => p.isVoided.equals(false))
          ..where((p) => p.isPendingBalance.equals(false))
          ..where(
            (p) =>
                p.revenueType.equals('room') |
                p.revenueType.equals('') |
                p.revenueType.isNull(),
          ))
        .get();

    return payments.fold<int>(0, (sum, p) => sum + p.amount.round());
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final v = value.trim();
    final normalized = v.contains('T') ? v : v.replaceFirst(' ', 'T');
    final withSeconds =
        normalized.length == 16 ? '${normalized}:00' : normalized;
    try {
      return DateTime.parse(withSeconds);
    } catch (_) {
      return null;
    }
  }
}
