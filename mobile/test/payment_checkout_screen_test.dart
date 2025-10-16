import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:marina_hotel_mobile/models/booking.dart';
import 'package:marina_hotel_mobile/screens/payment_checkout_screen.dart';

void main() {
  final NumberFormat numberFormat = NumberFormat.decimalPattern('en');

  Widget _wrapWithMaterial(Booking booking) {
    return MaterialApp(
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [Locale('ar', 'SA')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: PaymentCheckoutScreen(booking: booking),
    );
  }

  Finder _summaryCard() {
    return find.byWidgetPredicate(
      (widget) => widget is Card && widget.color == Colors.blue.shade50,
    );
  }

  group('PaymentCheckoutScreen add/edit/delete flow', () {
    testWidgets('adding a payment validates amount and updates totals', (tester) async {
      final booking = Booking(
        id: 'ADD-001',
        guestName: 'ضيف',
        roomNumber: '101',
        checkIn: DateTime(2025, 1, 10, 10, 0),
        plannedCheckout: DateTime(2025, 1, 13, 12, 0),
        nightlyRate: 200,
        payments: const [
          BookingPaymentEntry(amount: 200, paymentDate: DateTime(2025, 1, 10, 18)),
        ],
      );

      await tester.pumpWidget(_wrapWithMaterial(booking));
      await tester.pumpAndSettle();

      final addButtonFinder = find.widgetWithText(OutlinedButton, 'إضافة دفعة');
      expect(tester.widget<OutlinedButton>(addButtonFinder).onPressed, isNotNull);

      final summaryCard = _summaryCard();
      expect(find.descendant(of: summaryCard, matching: find.text(numberFormat.format(200))), findsOneWidget);
      expect(find.descendant(of: summaryCard, matching: find.text(numberFormat.format(400))), findsOneWidget);

      await tester.tap(addButtonFinder);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      final amountField = find.byType(TextFormField).first;
      await tester.enterText(amountField, '450');
      await tester.tap(find.text('حفظ'));
      await tester.pump();

      // Validation error keeps dialog open
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(amountField, '400');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);

      expect(find.descendant(of: summaryCard, matching: find.text(numberFormat.format(200))), findsNothing);
      expect(find.descendant(of: summaryCard, matching: find.text(numberFormat.format(0))), findsOneWidget);

      final addButtonAfter = tester.widget<OutlinedButton>(addButtonFinder);
      expect(addButtonAfter.onPressed, isNull);

      final checkoutButtonFinder = find.widgetWithText(ElevatedButton, 'تسجيل المغادرة');
      final checkoutButton = tester.widget<ElevatedButton>(checkoutButtonFinder);
      expect(checkoutButton.onPressed, isNotNull);
    });

    testWidgets('editing a payment enforces remaining limit and recalculates totals', (tester) async {
      final booking = Booking(
        id: 'EDIT-001',
        guestName: 'ضيف',
        roomNumber: '201',
        checkIn: DateTime(2025, 2, 1, 9, 0),
        plannedCheckout: DateTime(2025, 2, 4, 9, 0),
        nightlyRate: 200,
        payments: const [
          BookingPaymentEntry(amount: 200, paymentDate: DateTime(2025, 2, 1, 18)),
          BookingPaymentEntry(amount: 150, paymentDate: DateTime(2025, 2, 2, 18)),
        ],
      );

      await tester.pumpWidget(_wrapWithMaterial(booking));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('تعديل').first);
      await tester.pumpAndSettle();

      final amountField = find.byType(TextFormField).first;
      await tester.enterText(amountField, '500');
      await tester.tap(find.text('حفظ'));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(amountField, '400');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      final summaryCard = _summaryCard();
      expect(find.descendant(of: summaryCard, matching: find.text(numberFormat.format(550))), findsOneWidget);
      expect(find.descendant(of: summaryCard, matching: find.text(numberFormat.format(50))), findsOneWidget);

      final addButton = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'إضافة دفعة'));
      expect(addButton.onPressed, isNotNull);
    });

    testWidgets('deleting a payment frees remaining balance and re-enables add button', (tester) async {
      final booking = Booking(
        id: 'DEL-001',
        guestName: 'ضيف',
        roomNumber: '301',
        checkIn: DateTime(2025, 3, 5, 9, 0),
        plannedCheckout: DateTime(2025, 3, 8, 9, 0),
        nightlyRate: 200,
        payments: const [
          BookingPaymentEntry(amount: 200, paymentDate: DateTime(2025, 3, 5, 18)),
          BookingPaymentEntry(amount: 200, paymentDate: DateTime(2025, 3, 6, 18)),
          BookingPaymentEntry(amount: 200, paymentDate: DateTime(2025, 3, 7, 18)),
        ],
      );

      await tester.pumpWidget(_wrapWithMaterial(booking));
      await tester.pumpAndSettle();

      final addButtonFinder = find.widgetWithText(OutlinedButton, 'إضافة دفعة');
      expect(tester.widget<OutlinedButton>(addButtonFinder).onPressed, isNull);

      await tester.tap(find.byTooltip('حذف').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف'));
      await tester.pumpAndSettle();

      final summaryCard = _summaryCard();
      expect(find.descendant(of: summaryCard, matching: find.text(numberFormat.format(400))), findsOneWidget);
      expect(find.descendant(of: summaryCard, matching: find.text(numberFormat.format(200))), findsOneWidget);

      final addButton = tester.widget<OutlinedButton>(addButtonFinder);
      expect(addButton.onPressed, isNotNull);
    });
  });
}
