import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../booking_utils.dart';

/// Booking form state
class BookingFormState extends Equatable {
  final String guestName;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final double nightlyRate;
  final String roomType;
  final String? selectedSlip;
  final List<String> bookedSlips;
  final bool isSubmitting;
  final String? errorMessage;

  const BookingFormState({
    this.guestName = '',
    this.checkIn,
    this.checkOut,
    this.nightlyRate = 150.0,
    this.roomType = 'Standard',
    this.selectedSlip,
    this.bookedSlips = const ['slip-2'],
    this.isSubmitting = false,
    this.errorMessage,
  });

  /// List of available slips
  List<String> get availableSlips => [
        'slip-1',
        'slip-2',
        'slip-3',
        'slip-4',
        'slip-5',
      ];

  /// Check if a slip is booked
  bool isSlipBooked(String slipId) => bookedSlips.contains(slipId);

  /// Calculate total price
  double get totalPrice {
    if (checkIn == null || checkOut == null) return 0;
    return calculateBookingPrice(
      nightlyRate: nightlyRate,
      checkIn: checkIn!,
      checkOut: checkOut!,
    );
  }

  /// Calculate number of nights
  int get nights {
    if (checkIn == null || checkOut == null) return 0;
    return checkOut!.difference(checkIn!).inDays;
  }

  /// Check if booking is valid
  bool get isValid {
    if (guestName.isEmpty) return false;
    if (checkIn == null || checkOut == null) return false;
    return validateDateRange(checkIn, checkOut);
  }

  /// Validation errors
  String? get guestNameError {
    if (guestName.isEmpty) return null;
    if (guestName.length < 3) return 'Name must be at least 3 characters';
    if (guestName.length > 50) return 'Name must be less than 50 characters';
    return null;
  }

  BookingFormState copyWith({
    String? guestName,
    DateTime? checkIn,
    DateTime? checkOut,
    double? nightlyRate,
    String? roomType,
    String? selectedSlip,
    List<String>? bookedSlips,
    bool? isSubmitting,
    String? errorMessage,
    bool clearCheckIn = false,
    bool clearCheckOut = false,
    bool clearSelectedSlip = false,
    bool clearError = false,
  }) {
    return BookingFormState(
      guestName: guestName ?? this.guestName,
      checkIn: clearCheckIn ? null : (checkIn ?? this.checkIn),
      checkOut: clearCheckOut ? null : (checkOut ?? this.checkOut),
      nightlyRate: nightlyRate ?? this.nightlyRate,
      roomType: roomType ?? this.roomType,
      selectedSlip:
          clearSelectedSlip ? null : (selectedSlip ?? this.selectedSlip),
      bookedSlips: bookedSlips ?? this.bookedSlips,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        guestName,
        checkIn,
        checkOut,
        nightlyRate,
        roomType,
        selectedSlip,
        bookedSlips,
        isSubmitting,
        errorMessage,
      ];
}

/// Booking notifier using Riverpod
class BookingNotifier extends StateNotifier<BookingFormState> {
  BookingNotifier() : super(const BookingFormState());

  void updateGuestName(String name) {
    state = state.copyWith(guestName: name, clearError: true);
  }

  void updateCheckIn(DateTime date) {
    state = state.copyWith(
      checkIn: date,
      clearError: true,
      clearCheckOut: state.checkOut != null && state.checkOut!.isBefore(date),
    );
  }

  void updateCheckOut(DateTime date) {
    state = state.copyWith(checkOut: date, clearError: true);
  }

  void updateNightlyRate(double rate) {
    state = state.copyWith(nightlyRate: rate, clearError: true);
  }

  void updateRoomType(String type) {
    state = state.copyWith(roomType: type, clearError: true);
  }

  void updateSelectedSlip(String? slip) {
    state = state.copyWith(
      selectedSlip: slip,
      clearSelectedSlip: slip == null,
      clearError: true,
    );
  }

  Future<Booking?> submitBooking() async {
    if (!state.isValid) {
      state = state.copyWith(errorMessage: 'Please fill in all required fields');
      return null;
    }

    state = state.copyWith(isSubmitting: true);

    try {
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));

      final booking = Booking(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        guestName: state.guestName,
        checkIn: state.checkIn!,
        checkOut: state.checkOut!,
        nightlyRate: state.nightlyRate,
        roomType: state.roomType,
        bookedSlips: state.selectedSlip != null
            ? [...state.bookedSlips, state.selectedSlip!]
            : state.bookedSlips,
      );

      // Reset form
      state = BookingFormState(bookedSlips: booking.bookedSlips);

      return booking;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to submit booking: ${e.toString()}',
      );
      return null;
    }
  }

  void resetForm() {
    state = BookingFormState(bookedSlips: state.bookedSlips);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// Provider for booking state
final bookingProvider =
    StateNotifierProvider<BookingNotifier, BookingFormState>((ref) {
  return BookingNotifier();
});

/// Provider for total price (derived state)
final totalPriceProvider = Provider<double>((ref) {
  return ref.watch(bookingProvider).totalPrice;
});

/// Provider for booking validity
final isValidBookingProvider = Provider<bool>((ref) {
  return ref.watch(bookingProvider).isValid;
});