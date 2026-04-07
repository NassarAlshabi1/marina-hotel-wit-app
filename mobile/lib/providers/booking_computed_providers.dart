import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/repository_providers.dart';
import '../services/booking_computed_stream_service.dart';
import '../services/hotel_time_engine.dart';

// ---------------------------------------------------------------------------
// Service Provider
// ---------------------------------------------------------------------------

/// Singleton provider for [BookingComputedStreamService].
final bookingComputedServiceProvider =
    Provider<BookingComputedStreamService>((ref) {
  final db = ref.watch(databaseProvider);
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

/// A stream provider that emits the current hotel day every time the clock
/// crosses the 14:00 boundary.
///
/// This allows the UI to react when a new hotel day starts (e.g., increment
/// the displayed day count for active bookings automatically).
///
/// Example:
/// ```dart
/// final hotelDay = ref.watch(hotelDayTickerProvider);
/// // emits '2022-01-05' then '2022-01-06' when clock passes 14:00
/// ```
final hotelDayTickerProvider = StreamProvider<String>((ref) {
  final controller = StreamController<String>.broadcast();

  // Emit immediately
  controller.add(HotelTimeEngine.formatHotelDay(DateTime.now()));

  // Check every 30 seconds
  const checkInterval = Duration(seconds: 30);
  String lastEmitted = HotelTimeEngine.formatHotelDay(DateTime.now());

  final timer = Timer.periodic(checkInterval, (_) {
    final current = HotelTimeEngine.formatHotelDay(DateTime.now());
    if (current != lastEmitted) {
      lastEmitted = current;
      controller.add(current);
    }
  });

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});
