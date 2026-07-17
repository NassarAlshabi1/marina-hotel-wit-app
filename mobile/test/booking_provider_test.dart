import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marina_hotel_wit_app/providers/booking_provider.dart';

void main() {
  group('BookingProvider Tests', () {
    late ProviderContainer container;
    late BookingNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(bookingProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has correct defaults', () {
      final state = container.read(bookingProvider);
      
      expect(state.guestName, '');
      expect(state.checkIn, isNull);
      expect(state.checkOut, isNull);
      expect(state.nightlyRate, 150.0);
      expect(state.roomType, 'Standard');
      expect(state.selectedSlip, isNull);
      expect(state.bookedSlips, ['slip-2']);
      expect(state.isSubmitting, false);
      expect(state.errorMessage, isNull);
    });

    test('updateGuestName updates state', () {
      notifier.updateGuestName('Ahmed Ali');
      
      final state = container.read(bookingProvider);
      expect(state.guestName, 'Ahmed Ali');
    });

    test('updateCheckIn updates state', () {
      final date = DateTime(2026, 6, 15);
      notifier.updateCheckIn(date);
      
      final state = container.read(bookingProvider);
      expect(state.checkIn, date);
    });

    test('updateCheckOut updates state', () {
      final date = DateTime(2026, 6, 20);
      notifier.updateCheckOut(date);
      
      final state = container.read(bookingProvider);
      expect(state.checkOut, date);
    });

    test('updateNightlyRate updates state', () {
      notifier.updateNightlyRate(200.0);
      
      final state = container.read(bookingProvider);
      expect(state.nightlyRate, 200.0);
    });

    test('updateRoomType updates state', () {
      notifier.updateRoomType('Suite');
      
      final state = container.read(bookingProvider);
      expect(state.roomType, 'Suite');
    });

    test('updateSelectedSlip updates state', () {
      notifier.updateSelectedSlip('slip-3');
      
      final state = container.read(bookingProvider);
      expect(state.selectedSlip, 'slip-3');
    });

    test('clearSelectedSlip works', () {
      notifier.updateSelectedSlip('slip-3');
      notifier.updateSelectedSlip(null);
      
      final state = container.read(bookingProvider);
      expect(state.selectedSlip, isNull);
    });

    test('totalPrice returns 0 when no dates', () {
      final state = container.read(bookingProvider);
      expect(state.totalPrice, 0);
    });

    test('totalPrice calculates correctly', () {
      notifier.updateCheckIn(DateTime(2026, 6, 10));
      notifier.updateCheckOut(DateTime(2026, 6, 15));
      
      final state = container.read(bookingProvider);
      expect(state.totalPrice, 750.0); // 5 nights * $150
    });

    test('nights returns 0 when no dates', () {
      final state = container.read(bookingProvider);
      expect(state.nights, 0);
    });

    test('nights calculates correctly', () {
      notifier.updateCheckIn(DateTime(2026, 6, 10));
      notifier.updateCheckOut(DateTime(2026, 6, 15));
      
      final state = container.read(bookingProvider);
      expect(state.nights, 5);
    });

    test('isValid returns false when guestName is empty', () {
      notifier.updateCheckIn(DateTime(2026, 6, 10));
      notifier.updateCheckOut(DateTime(2026, 6, 15));
      
      final state = container.read(bookingProvider);
      expect(state.isValid, false);
    });

    test('isValid returns true when all fields are valid', () {
      notifier.updateGuestName('Ahmed Ali');
      notifier.updateCheckIn(DateTime(2026, 6, 10));
      notifier.updateCheckOut(DateTime(2026, 6, 15));
      
      final state = container.read(bookingProvider);
      expect(state.isValid, true);
    });

    test('guestNameError returns null for valid name', () {
      notifier.updateGuestName('Ahmed');
      
      final state = container.read(bookingProvider);
      expect(state.guestNameError, isNull);
    });

    test('guestNameError returns error for short name', () {
      notifier.updateGuestName('Ah');
      
      final state = container.read(bookingProvider);
      expect(state.guestNameError, 'Name must be at least 3 characters');
    });

    test('guestNameError returns error for long name', () {
      notifier.updateGuestName('A' * 51);
      
      final state = container.read(bookingProvider);
      expect(state.guestNameError, 'Name must be less than 50 characters');
    });

    test('availableSlips returns all slips', () {
      final state = container.read(bookingProvider);
      expect(state.availableSlips, ['slip-1', 'slip-2', 'slip-3', 'slip-4', 'slip-5']);
    });

    test('isSlipBooked returns true for booked slip', () {
      final state = container.read(bookingProvider);
      expect(state.isSlipBooked('slip-2'), true);
    });

    test('isSlipBooked returns false for available slip', () {
      final state = container.read(bookingProvider);
      expect(state.isSlipBooked('slip-1'), false);
    });

    test('clearError clears error message', () {
      notifier.updateGuestName('Ah');
      notifier.clearError();
      
      final state = container.read(bookingProvider);
      expect(state.errorMessage, isNull);
    });

    test('resetForm resets all fields except bookedSlips', () {
      notifier.updateGuestName('Ahmed');
      notifier.updateCheckIn(DateTime(2026, 6, 10));
      notifier.updateCheckOut(DateTime(2026, 6, 15));
      notifier.updateSelectedSlip('slip-3');
      
      notifier.resetForm();
      
      final state = container.read(bookingProvider);
      expect(state.guestName, '');
      expect(state.checkIn, isNull);
      expect(state.checkOut, isNull);
      expect(state.selectedSlip, isNull);
      expect(state.bookedSlips, ['slip-2']); // Original bookedSlips preserved
    });

    test('submitBooking returns null when invalid', () async {
      final booking = await notifier.submitBooking();
      expect(booking, isNull);
      
      final state = container.read(bookingProvider);
      expect(state.errorMessage, 'Please fill in all required fields');
    });

    test('submitBooking returns booking when valid', () async {
      notifier.updateGuestName('Ahmed Ali');
      notifier.updateCheckIn(DateTime(2026, 6, 10));
      notifier.updateCheckOut(DateTime(2026, 6, 15));
      
      final booking = await notifier.submitBooking();
      
      expect(booking, isNotNull);
      expect(booking!.guestName, 'Ahmed Ali');
      expect(booking.nightlyRate, 150.0);
      expect(booking.roomType, 'Standard');
    });

    test('isSubmitting is true during submission', () async {
      notifier.updateGuestName('Ahmed Ali');
      notifier.updateCheckIn(DateTime(2026, 6, 10));
      notifier.updateCheckOut(DateTime(2026, 6, 15));
      
      // Start submission (don't await)
      final future = notifier.submitBooking();
      
      var state = container.read(bookingProvider);
      expect(state.isSubmitting, true);
      
      await future;
      
      state = container.read(bookingProvider);
      expect(state.isSubmitting, false);
    });
  });

  group('Derived Providers', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('totalPriceProvider returns correct price', () {
      final notifier = container.read(bookingProvider.notifier);
      notifier.updateCheckIn(DateTime(2026, 6, 10));
      notifier.updateCheckOut(DateTime(2026, 6, 15));
      
      final totalPrice = container.read(totalPriceProvider);
      expect(totalPrice, 750.0);
    });

    test('isValidBookingProvider returns correct validity', () {
      final notifier = container.read(bookingProvider.notifier);
      notifier.updateGuestName('Ahmed');
      notifier.updateCheckIn(DateTime(2026, 6, 10));
      notifier.updateCheckOut(DateTime(2026, 6, 15));
      
      final isValid = container.read(isValidBookingProvider);
      expect(isValid, true);
    });
  });
}