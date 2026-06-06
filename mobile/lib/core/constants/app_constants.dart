/// App-wide constants
class AppConstants {
  // Pricing
  static const double minNightlyRate = 50;
  static const double maxNightlyRate = 500;
  static const double defaultNightlyRate = 150;
  
  // Booking
  static const int maxBookingDays = 365;
  static const int minGuestNameLength = 3;
  static const int maxGuestNameLength = 50;
  
  // Animation
  static const Duration animationDuration = Duration(milliseconds: 300);
  
  // Marina slips
  static const List<String> defaultSlips = [
    'slip-1',
    'slip-2',
    'slip-3',
    'slip-4',
    'slip-5',
  ];
  
  // Room types
  static const List<String> roomTypes = [
    'Standard',
    'Deluxe',
    'Suite',
    'Marina View',
  ];
  
  // Storage keys
  static const String themeKey = 'theme_mode';
  static const String bookingsKey = 'bookings';
  static const String bookedSlipsKey = 'booked_slips';
}