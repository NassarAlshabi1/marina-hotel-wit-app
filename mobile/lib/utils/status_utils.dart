import '../services/local_db.dart';

class StatusUtils {
  static final Set<String> _availableRoomStatuses = {
    'شاغرة',
    'شاغره',
    'متاحة',
    'متاح',
    'available',
    'vacant',
    'empty',
  }.map(_normalize).toSet();

  static final Set<String> _occupiedRoomStatuses = {
    'محجوزة',
    'محجوز',
    'مشغولة',
    'occupied',
    'محجوز temporarily',
    'نشط',
    'active',
  }.map(_normalize).toSet();

  static final Set<String> _activeBookingStatuses = {
    'محجوزة',
    'محجوز',
    'نشط',
    'active',
    'confirmed',
    'قيد الحجز',
    'in_progress',
  }.map(_normalize).toSet();

  static String _normalize(String value) => value.trim().toLowerCase();

  static bool isRoomAvailable(String status) =>
      _availableRoomStatuses.contains(_normalize(status));

  static bool isRoomOccupied(String status) =>
      _occupiedRoomStatuses.contains(_normalize(status));

  static bool isActiveBooking(String status) =>
      _activeBookingStatuses.contains(_normalize(status));

  static String roomStatusForOccupancy(
    bool occupied, {
    String fallbackAvailable = 'شاغرة',
    String fallbackOccupied = 'محجوزة',
  }) {
    return occupied ? fallbackOccupied : fallbackAvailable;
  }

  static bool isBookingActive(Booking booking) =>
      isActiveBooking(booking.status);
}
