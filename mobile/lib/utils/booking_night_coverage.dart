import '../services/local_db.dart';
import 'time.dart';

/// Validates that cached nightly rows describe the complete current stay.
/// A stale subset must never be treated as the full bill for an active stay.
class BookingNightCoverage {
  BookingNightCoverage._();

  static List<BookingNight>? completeForStay({
    required List<BookingNight> nights,
    required int bookingLocalId,
    required String bookingUuid,
    required DateTime checkin,
    required int expectedNights,
  }) {
    if (expectedNights <= 0 || nights.length != expectedNights) return null;

    final rowsByHotelDay = <String, BookingNight>{};
    final normalizedBookingUuid = _normalizeUuid(bookingUuid);
    for (final night in nights) {
      if (night.deletedAt != null || night.bookingLocalId != bookingLocalId) {
        return null;
      }
      final rowBookingUuid = night.bookingUuidCache;
      if (rowBookingUuid != null && rowBookingUuid.isNotEmpty) {
        if (_normalizeUuid(rowBookingUuid) != normalizedBookingUuid) {
          return null;
        }
      }
      if (night.hotelDayKey.isEmpty ||
          rowsByHotelDay.containsKey(night.hotelDayKey)) {
        return null;
      }
      rowsByHotelDay[night.hotelDayKey] = night;
    }

    final startKey = DateTime.parse(Time.hotelDayKey(now: checkin));
    final ordered = <BookingNight>[];
    for (var i = 0; i < expectedNights; i++) {
      final expectedKey = Time.dateToString(startKey.add(Duration(days: i)));
      final row = rowsByHotelDay[expectedKey];
      if (row == null) return null;
      ordered.add(row);
    }
    return ordered;
  }

  static String _normalizeUuid(String uuid) =>
      uuid.trim().toLowerCase().replaceAll('-', '');
}
