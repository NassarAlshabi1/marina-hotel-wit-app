import 'package:intl/intl.dart';

class BookingPaymentEntry {
  final double amount;
  final DateTime paymentDate;
  final String method;
  final String? notes;

  const BookingPaymentEntry({
    required this.amount,
    required this.paymentDate,
    this.method = 'نقدي',
    this.notes,
  });
}

class Booking {
  final String id;
  final String guestName;
  final String roomNumber;
  final DateTime checkIn;
  final DateTime? plannedCheckout;
  final DateTime? actualCheckout;
  final double nightlyRate;
  final List<BookingPaymentEntry> payments;

  const Booking({
    required this.id,
    required this.guestName,
    required this.roomNumber,
    required this.checkIn,
    this.plannedCheckout,
    this.actualCheckout,
    required this.nightlyRate,
    this.payments = const [],
  });

  // Currency formatter (Arabic/Saudi)
  static final NumberFormat _number = NumberFormat.decimalPattern('en');

  // Sum of payments (raw)
  double get paidTotal => payments.fold(0.0, (sum, p) => sum + p.amount);

  // Nights as shown in list.php
  // PHP logic reference:
  // - If actual_checkout IS NULL: nights = DATEDIFF(CURRENT_DATE(), checkin_date)
  //   + (TIME(NOW()) > '13:00:00' ? 1 : 0)
  // - Else: nights = DATEDIFF(actual_checkout, checkin_date)
  // - Then display max(1, nights)
  int nightsForDisplay({DateTime? now}) {
    final DateTime nowLocal = now ?? DateTime.now();
    if (actualCheckout != null) {
      final days = _dateDiffInDays(checkIn, actualCheckout!);
      return days < 1 ? 1 : days;
    }
    final int days = _dateDiffInDays(checkIn, DateTime(nowLocal.year, nowLocal.month, nowLocal.day));
    final bool pastCutoff = nowLocal.hour > 13 || (nowLocal.hour == 13 && (nowLocal.minute > 0 || nowLocal.second > 0));
    final int computed = days + (pastCutoff ? 1 : 0);
    return computed < 1 ? 1 : computed;
  }

  // Nights used for billing (payment.php and checkout.php behavior)
  // Assumptions documented:
  // - If actualCheckout is present, bill using DATEDIFF(actual_checkout, checkin_date) with min 1.
  // - Else if plannedCheckout exists, bill using DATEDIFF(planned_checkout, checkin_date) with min 1 (payment.php).
  // - Else fall back to in-house cutoff logic (list.php) to estimate due amount today.
  int nightsForBilling({DateTime? now}) {
    if (actualCheckout != null) {
      final days = _dateDiffInDays(checkIn, actualCheckout!);
      return days < 1 ? 1 : days;
    }
    if (plannedCheckout != null) {
      final days = _dateDiffInDays(checkIn, plannedCheckout!);
      return days < 1 ? 1 : days;
    }
    return nightsForDisplay(now: now);
  }

  double totalDue({DateTime? now}) => nightsForBilling(now: now) * nightlyRate;

  // Remaining never goes negative (clamped to 0) per PHP views
  double remaining({DateTime? now}) {
    final due = totalDue(now: now);
    final rem = due - paidTotal;
    return rem <= 0 ? 0 : rem;
  }

  // Formatted currency helpers
  String formatAmount(double amount) => _number.format(amount);
  String get formattedTotalDue => formatAmount(totalDue());
  String get formattedPaid => formatAmount(paidTotal);
  String get formattedRemaining => formatAmount(remaining());

  Booking copyWith({
    String? id,
    String? guestName,
    String? roomNumber,
    DateTime? checkIn,
    DateTime? plannedCheckout,
    DateTime? actualCheckout,
    double? nightlyRate,
    List<BookingPaymentEntry>? payments,
  }) {
    return Booking(
      id: id ?? this.id,
      guestName: guestName ?? this.guestName,
      roomNumber: roomNumber ?? this.roomNumber,
      checkIn: checkIn ?? this.checkIn,
      plannedCheckout: plannedCheckout ?? this.plannedCheckout,
      actualCheckout: actualCheckout ?? this.actualCheckout,
      nightlyRate: nightlyRate ?? this.nightlyRate,
      payments: payments ?? this.payments,
    );
  }
}

// Helper: MySQL DATEDIFF style (date precision)
int _dateDiffInDays(DateTime start, DateTime end) {
  final a = DateTime(start.year, start.month, start.day);
  final b = DateTime(end.year, end.month, end.day);
  return b.difference(a).inDays;
}
