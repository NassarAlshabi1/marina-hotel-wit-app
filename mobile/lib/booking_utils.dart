/// Booking utilities for marina and hotel services

/// Validates a booking date range
/// Returns true if valid, false otherwise
bool validateDateRange(DateTime? checkIn, DateTime? checkOut) {
  if (checkIn == null || checkOut == null) {
    return false;
  }
  
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final checkInDate = DateTime(checkIn.year, checkIn.month, checkIn.day);
  final checkOutDate = DateTime(checkOut.year, checkOut.month, checkOut.day);
  
  if (checkInDate.isBefore(today)) {
    return false;
  }
  
  if (checkOutDate.isBefore(checkInDate) || checkOutDate.isAtSameMomentAs(checkInDate)) {
    return false;
  }
  
  return true;
}

/// Calculates the total price for a booking
/// Returns total price, or -1 on invalid input
double calculateBookingPrice({
  required double nightlyRate,
  required DateTime checkIn,
  required DateTime checkOut,
  double serviceFee = 0,
}) {
  if (nightlyRate < 0 || serviceFee < 0) {
    return -1;
  }
  
  final checkInDate = DateTime(checkIn.year, checkIn.month, checkIn.day);
  final checkOutDate = DateTime(checkOut.year, checkOut.month, checkOut.day);
  
  if (checkOutDate.isBefore(checkInDate)) {
    return -1;
  }
  
  final nights = checkOutDate.difference(checkInDate).inDays;
  
  if (nights <= 0) {
    return -1;
  }
  
  return (nightlyRate * nights) + serviceFee;
}

/// Checks if a dock slip is available
/// Returns true if available
bool isSlipAvailable(List<String>? bookedSlips, String slipId) {
  if (bookedSlips == null) {
    return true;
  }
  return !bookedSlips.contains(slipId);
}

/// Formats a date for display
/// Returns formatted date string
String formatDate(DateTime? date, {String locale = 'en_US'}) {
  if (date == null) {
    return '';
  }
  
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Model class for a booking
class Booking {
  final String id;
  final String guestName;
  final DateTime checkIn;
  final DateTime checkOut;
  final double nightlyRate;
  final String roomType;
  final List<String> bookedSlips;
  
  const Booking({
    required this.id,
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
    required this.nightlyRate,
    required this.roomType,
    this.bookedSlips = const [],
  });
  
  /// Calculate total price for this booking
  double get totalPrice => calculateBookingPrice(
    nightlyRate: nightlyRate,
    checkIn: checkIn,
    checkOut: checkOut,
  );
  
  /// Check if booking dates are valid
  bool get isValid => validateDateRange(checkIn, checkOut);
  
  /// Get number of nights
  int get nights => checkOut.difference(checkIn).inDays;
  
  @override
  String toString() {
    return 'Booking(id: $id, guestName: $guestName, checkIn: $checkIn, checkOut: $checkOut)';
  }
}