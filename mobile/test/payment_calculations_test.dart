import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/payments/payment_calculations.dart';

void main() {
  group('PaymentCalculations', () {
    test('calculateTotalPrice with no discount', () {
      final result = PaymentCalculations.calculateTotalPrice(
        roomRate: 100,
        nights: 5,
      );
      expect(result, 500);
    });

    test('calculateTotalPrice with per-night discount', () {
      final result = PaymentCalculations.calculateTotalPrice(
        roomRate: 100,
        nights: 5,
        discount: 10,
        discountType: 'night',
      );
      expect(result, 450); // (100-10)*5
    });

    test('calculateTotalPrice with total discount', () {
      final result = PaymentCalculations.calculateTotalPrice(
        roomRate: 100,
        nights: 5,
        discount: 50,
        discountType: 'total',
      );
      expect(result, 450); // 500-50
    });

    test('calculateDiscount', () {
      final result = PaymentCalculations.calculateDiscount(
        roomRate: 100,
        nights: 5,
        discountPercent: 10,
      );
      expect(result, 50); // 500 * 0.10
    });

    test('calculateTax', () {
      final result = PaymentCalculations.calculateTax(
        totalAmount: 1000,
        taxPercent: 5,
      );
      expect(result, 50); // 1000 * 0.05
    });

    test('calculateRemaining', () {
      final result = PaymentCalculations.calculateRemaining(
        totalAmount: 1000,
        paidAmount: 600,
      );
      expect(result, 400);
    });

    test('calculateRemaining clamps to zero', () {
      final result = PaymentCalculations.calculateRemaining(
        totalAmount: 1000,
        paidAmount: 1500,
      );
      expect(result, 0);
    });

    test('validatePriceAdjustments with valid amount', () {
      final result = PaymentCalculations.validatePriceAdjustments(
        totalAmount: 1000,
        adjustedAmount: 800,
      );
      expect(result, true);
    });

    test('validatePriceAdjustments with invalid amount', () {
      final result = PaymentCalculations.validatePriceAdjustments(
        totalAmount: 1000,
        adjustedAmount: 1200,
      );
      expect(result, false);
    });

    test('formatCurrency', () {
      final result = PaymentCalculations.formatCurrency(1500);
      expect(result, '1,500');
    });

    test('formatDateTime', () {
      final dt = DateTime(2026, 9, 10, 14, 30, 45);
      final result = PaymentCalculations.formatDateTime(dt);
      expect(result, '2026-09-10 14:30:45');
    });

    test('calculateDailyPayments', () {
      final result = PaymentCalculations.calculateDailyPayments(
        totalAmount: 500,
        nights: 5,
        startDate: DateTime(2026, 9, 1),
      );
      expect(result.length, 5);
      expect(result[DateTime(2026, 9, 1)], 100);
      expect(result[DateTime(2026, 9, 2)], 100);
    });
  });

  group('PaymentTotals', () {
    test('create with all values', () {
      final totals = PaymentTotals(
        total: 1000,
        remaining: 400,
        paid: 600,
        discount: 100,
        tax: 50,
      );

      expect(totals.total, 1000);
      expect(totals.remaining, 400);
      expect(totals.paid, 600);
      expect(totals.discount, 100);
      expect(totals.tax, 50);
    });

    test('copyWith updates values', () {
      final original = PaymentTotals(
        total: 1000,
        remaining: 400,
        paid: 600,
      );

      final updated = original.copyWith(paid: 750);

      expect(original.paid, 600); // Original unchanged
      expect(updated.paid, 750); // Updated value
      expect(updated.total, 1000); // Other values preserved
    });

    test('toString output', () {
      final totals = PaymentTotals(
        total: 1000,
        remaining: 400,
      );

      expect(totals.toString(), contains('PaymentTotals'));
      expect(totals.toString(), contains('1000'));
      expect(totals.toString(), contains('400'));
    });
  });
}
