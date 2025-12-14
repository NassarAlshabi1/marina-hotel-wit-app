import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marina_hotel_mobile/screens/payments/booking_payment_screen.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  testWidgets('BookingPaymentScreen should render without errors', (WidgetTester tester) async {
    final booking = Booking(
      id: 1,
      localUuid: 'test-booking-uuid',
      guestName: 'محمد أحمد',
      guestPhone: '967777123456',
      guestIdType: 'بطاقة شخصية',
      guestIdNumber: '123456',
      guestNationality: 'يمني',
      roomNumber: '101',
      checkinDate: DateTime.now().toIso8601String(),
      expectedNights: 2,
      status: 'محجوزة',
      serverBookingId: null,
      lastSyncedAt: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      checkoutDate: null,
      actualCheckout: null,
      calculatedNights: null,
      notes: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: BookingPaymentScreen(booking: booking),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('معالجة المدفوعات'), findsOneWidget);
  });
}
