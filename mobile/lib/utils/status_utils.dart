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
    'مؤقت',
    'provisional',
  }.map(_normalize).toSet();

  static final Set<String> _activeBookingStatuses = {
    'محجوزة',
    'محجوز',
    'نشط',
    'active',
    'confirmed',
    'قيد الحجز',
    'in_progress',
    'مؤقت',
    'provisional',
  }.map(_normalize).toSet();

  /// القائمة الخام للحالات النشطة (قبل التطبيع) - لاستخدامها في استعلامات SQL
  static const List<String> activeBookingStatuses = [
    'محجوزة',
    'محجوز',
    'نشط',
    'active',
    'confirmed',
    'قيد الحجز',
    'in_progress',
    'مؤقت',
    'provisional',
  ];

  static final Set<String> _provisionalStatuses = {
    'مؤقت',
    'provisional',
  }.map(_normalize).toSet();

  static String _normalize(String value) => value.trim().toLowerCase();

  static bool isRoomAvailable(String status) =>
      _availableRoomStatuses.contains(_normalize(status));

  static bool isRoomOccupied(String status) =>
      _occupiedRoomStatuses.contains(_normalize(status));

  static bool isActiveBooking(String status) =>
      _activeBookingStatuses.contains(_normalize(status));

  static bool isProvisional(String status) =>
      _provisionalStatuses.contains(_normalize(status));

  static bool isBookingProvisional(Booking booking) =>
      isProvisional(booking.status);

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
