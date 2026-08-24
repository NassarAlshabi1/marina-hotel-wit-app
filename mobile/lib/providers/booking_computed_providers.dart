import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/repository_providers.dart';
import '../services/booking_computed_stream_service.dart';

// ---------------------------------------------------------------------------
// Service Provider
// ---------------------------------------------------------------------------

/// Singleton provider for [BookingComputedStreamService].
final bookingComputedServiceProvider = Provider<BookingComputedStreamService>((
  ref,
) {
  final db = ref.read(databaseProvider);
  return BookingComputedStreamService(db);
});

// ---------------------------------------------------------------------------
// Booking Streams
// ---------------------------------------------------------------------------

/// Watches all active (checked-in) bookings with computed financial values.
///
/// Emits a new list whenever any booking or payment changes.
/// All financial values are computed client-side.
final activeBookingsWithPaymentsProvider =
    StreamProvider<List<BookingWithPayments>>((ref) {
      final service = ref.watch(bookingComputedServiceProvider);
      return service.watchActiveBookingsWithPayments();
    });

/// Watches bookings for a specific room number.
///
/// Usage:
/// ```dart
/// final bookings = ref.watch(bookingsWithPaymentsByRoomProvider('101'));
/// ```
final bookingsWithPaymentsByRoomProvider =
    StreamProvider.family<List<BookingWithPayments>, String>((ref, roomNumber) {
      final service = ref.watch(bookingComputedServiceProvider);
      return service.watchBookingsByRoom(roomNumber);
    });

/// Watches a single booking by local ID with computed financial values.
final bookingWithPaymentsProvider =
    StreamProvider.family<BookingWithPayments?, int>((ref, bookingId) {
      final service = ref.watch(bookingComputedServiceProvider);
      return service.watchBookingWithPayments(bookingId);
    });

// ---------------------------------------------------------------------------
// Hotel Day Ticker
// ---------------------------------------------------------------------------
