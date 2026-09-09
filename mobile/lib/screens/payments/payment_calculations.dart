/// Pure payment calculation utilities for booking payment screen.
///
/// Extracted from booking_payment_screen.dart (4,118 LOC)
/// This module handles all mathematical calculations without UI or side effects.

import 'package:intl/intl.dart';

import '../../services/local_db.dart' as db;

/// Payment calculation utilities
class PaymentCalculations {
  /// Currency formatter for display
  static final currencyFmt = NumberFormat('#,##0', 'en_US');

  /// Calculate total amount for a booking
  static double calculateTotalPrice({
    required double roomRate,
    required int nights,
    double discount = 0,
    String discountType = 'night', // 'night' or 'total'
  }) {
    final nightTotal = roomRate * nights;
    if (discount <= 0) return nightTotal;

    if (discountType == 'total') {
      return (nightTotal - discount).clamp(0, double.infinity);
    } else {
      // per-night discount
      return ((roomRate - discount) * nights).clamp(0, double.infinity);
    }
  }

  /// Calculate discounted amount
  static double calculateDiscount({
    required double roomRate,
    required int nights,
    required double discountPercent,
  }) {
    final nightTotal = roomRate * nights;
    return nightTotal * (discountPercent / 100);
  }

  /// Calculate tax on total amount
  static double calculateTax({
    required double totalAmount,
    double taxPercent = 5, // Default 5% tax
  }) {
    return totalAmount * (taxPercent / 100);
  }

  /// Calculate remaining amount after payment
  static double calculateRemaining({
    required double totalAmount,
    required double paidAmount,
  }) {
    return (totalAmount - paidAmount).clamp(0, double.infinity);
  }

  /// Validate price adjustments don't exceed total
  static bool validatePriceAdjustments({
    required double totalAmount,
    required double adjustedAmount,
  }) {
    return adjustedAmount <= totalAmount && adjustedAmount >= 0;
  }

  /// Count nights with discount applied
  static int countNightsWithDiscount({
    required int totalNights,
    required List<DateTime> datesWithDiscount,
  }) {
    return datesWithDiscount.length;
  }

  /// Format amount for display
  static String formatCurrency(double amount) {
    return currencyFmt.format(amount);
  }

  /// Format datetime for display
  static String formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }

  /// Calculate payment breakdown by date
  static Map<DateTime, double> calculateDailyPayments({
    required double totalAmount,
    required int nights,
    required DateTime startDate,
  }) {
    final result = <DateTime, double>{};
    final dailyAmount = totalAmount / nights;

    for (int i = 0; i < nights; i++) {
      final date = startDate.add(Duration(days: i));
      result[date] = dailyAmount;
    }

    return result;
  }

  /// Calculate settlement of debts
  static double calculateDebtSettlement({
    required List<db.Debt> debts,
    required double paymentAmount,
  }) {
    double settled = 0;
    double remaining = paymentAmount;

    for (final debt in debts) {
      if (remaining <= 0) break;

      final toSettle = remaining.clamp(0, debt.amount ?? 0);
      settled += toSettle;
      remaining -= toSettle;
    }

    return settled;
  }
}

/// Immutable payment totals data
class PaymentTotals {
  const PaymentTotals({
    required this.total,
    required this.remaining,
    this.paid = 0,
    this.discount = 0,
    this.tax = 0,
  });

  final double total;
  final double remaining;
  final double paid;
  final double discount;
  final double tax;

  /// Create a copy with modified values
  PaymentTotals copyWith({
    double? total,
    double? remaining,
    double? paid,
    double? discount,
    double? tax,
  }) {
    return PaymentTotals(
      total: total ?? this.total,
      remaining: remaining ?? this.remaining,
      paid: paid ?? this.paid,
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
    );
  }

  @override
  String toString() =>
      'PaymentTotals(total: $total, remaining: $remaining, paid: $paid, discount: $discount, tax: $tax)';
}
