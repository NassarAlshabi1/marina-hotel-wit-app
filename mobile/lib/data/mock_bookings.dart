import '../models/booking.dart';

final DateTime _now = DateTime.now();

final List<Booking> mockBookings = [
  // Fully paid, still in-house (planned checkout in future)
  Booking(
    id: 'BKG-1001',
    guestName: 'أحمد علي',
    roomNumber: '201',
    checkIn: _now.subtract(const Duration(days: 2)),
    plannedCheckout: _now.add(const Duration(days: 1)),
    nightlyRate: 200,
    payments: [
      BookingPaymentEntry(amount: 200, paymentDate: DateTime(2025, 1, 10, 16, 0)),
      BookingPaymentEntry(amount: 200, paymentDate: DateTime(2025, 1, 11, 12, 30)),
    ],
  ),

  // In-house guest past cutoff (no planned checkout)
  Booking(
    id: 'BKG-1002',
    guestName: 'سارة محمد',
    roomNumber: '305',
    checkIn: DateTime(_now.year, _now.month, _now.day).subtract(const Duration(days: 1)),
    plannedCheckout: null,
    nightlyRate: 180,
    payments: [
      BookingPaymentEntry(amount: 100, paymentDate: DateTime(2025, 1, 10, 9, 15)),
    ],
  ),

  // Completed departure (actual checkout set)
  Booking(
    id: 'BKG-1003',
    guestName: 'خالد حسين',
    roomNumber: '110',
    checkIn: DateTime(_now.year, _now.month, _now.day).subtract(const Duration(days: 3)),
    plannedCheckout: _now.subtract(const Duration(days: 1)),
    actualCheckout: _now.subtract(const Duration(days: 1)),
    nightlyRate: 150,
    payments: [
      BookingPaymentEntry(amount: 300, paymentDate: DateTime(2025, 1, 9, 18, 0)),
      BookingPaymentEntry(amount: 150, paymentDate: DateTime(2025, 1, 10, 18, 0)),
    ],
  ),
];
