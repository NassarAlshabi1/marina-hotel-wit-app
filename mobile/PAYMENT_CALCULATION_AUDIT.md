# Payment calculation fixes – audit notes

## Changes included

1. `lib/services/guest_payment_calculation_service.dart`
   - Guest financial summary now uses `EnhancedBookingCalculationService.calculateFinancials` for the planned booking total, rather than multiplying the room's current rate by planned nights.
   - Uses stored, non-deleted nightly records for consumed-night pricing when enough records exist, preserving historical nightly prices and per-night adjustments.
   - Applies a proportional share of a booking-level (`total`) discount to consumed nights; legacy bookings without nightly records retain a fallback calculation.
   - Payment query excludes deleted, voided and pending-balance records.

2. `lib/screens/payments/booking_payment_screen.dart`
   - Last-payment selection excludes pending-balance records as well as voided records.
   - Daily/extra-night payment calculation uses the same stay calculator as the payment screen, and excludes pending/voided payments from collected totals.

3. `lib/services/enhanced_booking_calculation_service.dart`
   - `remainingBalance` now preserves negative values (`totalDue - totalPaid`). A negative balance is a guest credit/overpayment; clamping it to zero previously hid that amount in cached financial summaries and reports.

## Business rules represented

- A payment is counted as received only when it is not deleted, not voided, and not marked `isPendingBalance`.
- All received payment revenue types remain eligible for the booking balance; revenue type is a reporting classification, not a payment-validity rule.
- Booking total is derived from the nightly breakdown and active price adjustments; booking-level total discount is subtracted once by the shared financial summary.
- Negative remaining balance is retained as credit rather than discarded.
- No automatic checkout or booking status transition is introduced.

## Validation status / cautions

- Static source review only. Flutter/Dart SDK is not installed in this execution environment, so `dart format`, `flutter analyze`, and automated tests could not be run.
- Existing behavior for legacy bookings without `booking_nights` records uses a fallback based on the current room rate; historical prices cannot be reconstructed if the database never stored them.
- The consumed-night report prorates a booking-level total discount across elapsed nights. This is an accounting allocation for the consumed-cost view; the final booking total still applies the discount once to the whole stay.
