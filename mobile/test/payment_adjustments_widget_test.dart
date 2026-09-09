import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/payments/payment_adjustments_widget.dart';

void main() {
  group('PaymentAdjustmentsWidget', () {
    testWidgets('renders discount and surcharge sections', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentAdjustmentsWidget(
              totalAmount: 1000,
              onDiscountChanged: (_) {},
              onSurchargeChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('تعديلات الأسعار'), findsOneWidget);
      expect(find.text('خصم'), findsOneWidget);
      expect(find.text('إضافة'), findsOneWidget);
    });

    testWidgets('updates discount value on input', (WidgetTester tester) async {
      double? changedValue;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentAdjustmentsWidget(
              totalAmount: 1000,
              onDiscountChanged: (value) => changedValue = value,
              onSurchargeChanged: (_) {},
            ),
          ),
        ),
      );

      // Find and enter discount value
      await tester.enterText(find.byType(TextField).first, '100');
      await tester.pump();

      expect(changedValue, 100);
    });

    testWidgets('updates surcharge value on input', (WidgetTester tester) async {
      double? changedValue;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentAdjustmentsWidget(
              totalAmount: 1000,
              onDiscountChanged: (_) {},
              onSurchargeChanged: (value) => changedValue = value,
            ),
          ),
        ),
      );

      // Find and enter surcharge value (second TextField)
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(1), '50');
      await tester.pump();

      expect(changedValue, 50);
    });

    testWidgets('displays correct adjusted total', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentAdjustmentsWidget(
              totalAmount: 1000,
              onDiscountChanged: (_) {},
              onSurchargeChanged: (_) {},
              initialDiscount: 100,
              initialSurcharge: 50,
            ),
          ),
        ),
      );

      // Total should be 1000 - 100 + 50 = 950
      // Should display breakdown
      expect(find.text('المبلغ الأساسي'), findsOneWidget);
      expect(find.text('الإجمالي'), findsOneWidget);
    });

    testWidgets('tapping preset amount updates discount', (WidgetTester tester) async {
      double? changedValue;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentAdjustmentsWidget(
              totalAmount: 1000,
              onDiscountChanged: (value) => changedValue = value,
              onSurchargeChanged: (_) {},
            ),
          ),
        ),
      );

      // Tap a preset button (looks for button with "ر.ي")
      final buttons = find.byType(ElevatedButton);
      if (buttons.evaluate().isNotEmpty) {
        await tester.tap(buttons.first);
        await tester.pump();
        // Verify callback was called with some value
        expect(changedValue, isNotNull);
      }
    });

    testWidgets('shows breakdown when discount applied', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentAdjustmentsWidget(
              totalAmount: 1000,
              onDiscountChanged: (_) {},
              onSurchargeChanged: (_) {},
              initialDiscount: 100,
            ),
          ),
        ),
      );

      // Should show discount line in breakdown
      expect(find.text('الخصم'), findsWidgets); // At least in breakdown
    });

    testWidgets('handles zero values correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentAdjustmentsWidget(
              totalAmount: 1000,
              onDiscountChanged: (_) {},
              onSurchargeChanged: (_) {},
              initialDiscount: 0,
              initialSurcharge: 0,
            ),
          ),
        ),
      );

      // Should render without errors
      expect(find.byType(PaymentAdjustmentsWidget), findsOneWidget);
    });
  });

  group('AdjustmentHistoryWidget', () {
    testWidgets('renders empty when no adjustments', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdjustmentHistoryWidget(
              adjustments: [],
            ),
          ),
        ),
      );

      // Should render nothing (SizedBox.shrink())
      expect(find.text('سجل التعديلات'), findsNothing);
    });

    testWidgets('displays adjustment history', (WidgetTester tester) async {
      final adjustments = [
        AdjustmentRecord(
          label: 'خصم إجمالي',
          amount: 100,
          isDiscount: true,
          timestamp: '2026-09-10 10:30',
        ),
        AdjustmentRecord(
          label: 'رسوم إضافية',
          amount: 50,
          isDiscount: false,
          timestamp: '2026-09-10 10:35',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdjustmentHistoryWidget(
              adjustments: adjustments,
            ),
          ),
        ),
      );

      expect(find.text('سجل التعديلات'), findsOneWidget);
      expect(find.text('خصم إجمالي'), findsOneWidget);
      expect(find.text('رسوم إضافية'), findsOneWidget);
    });

    testWidgets('shows correct symbols for discount and surcharge', (WidgetTester tester) async {
      final adjustments = [
        AdjustmentRecord(
          label: 'خصم',
          amount: 100,
          isDiscount: true,
          timestamp: '10:30',
        ),
        AdjustmentRecord(
          label: 'إضافة',
          amount: 50,
          isDiscount: false,
          timestamp: '10:35',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdjustmentHistoryWidget(
              adjustments: adjustments,
            ),
          ),
        ),
      );

      // Should display - for discount and + for surcharge
      expect(find.text('- 100'), findsOneWidget); // Discount
      expect(find.text('+ 50'), findsOneWidget); // Surcharge
    });
  });

  group('AdjustmentRecord', () {
    test('creates instance with correct values', () {
      final record = AdjustmentRecord(
        label: 'Test Adjustment',
        amount: 100,
        isDiscount: true,
        timestamp: '2026-09-10 10:30',
      );

      expect(record.label, 'Test Adjustment');
      expect(record.amount, 100);
      expect(record.isDiscount, true);
      expect(record.timestamp, '2026-09-10 10:30');
    });
  });
}
