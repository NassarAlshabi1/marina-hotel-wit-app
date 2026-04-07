/// Single source of truth for all hotel day calculations.
///
/// ## Business Rules
///
/// The hotel day boundary is at **14:00** (2:00 PM).
///
/// | Time            | Classification      |
/// |-----------------|---------------------|
/// | Before 14:00:00 | Previous hotel day  |
/// | Exactly 14:00:00| Current hotel day   |
/// | After 14:00:00  | Next hotel day      |
///
/// The boundary check uses **strictly greater than** (`>`) so that
/// 14:00:00 exactly is *not* considered "after the cutoff".
class HotelTimeEngine {
  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  /// The hour at which the hotel day boundary occurs (14 = 2:00 PM).
  static const int boundaryHour = 14;

  // ---------------------------------------------------------------------------
  // Core day resolution
  // ---------------------------------------------------------------------------

  /// Determines the hotel day (date-only) for a given [dt].
  ///
  /// Uses a three-way classification relative to [boundaryHour]:
  /// - **Before** 14:00:00  -> previous calendar day
  /// - **Exactly** 14:00:00 -> same calendar day
  /// - **After**  14:00:00  -> next calendar day
  ///
  /// Returns a [DateTime] with time set to midnight (00:00:00).
  static DateTime getHotelDay(DateTime dt) {
    final dateOnly = DateTime(dt.year, dt.month, dt.day);

    if (dt.hour < boundaryHour) {
      // Before 14:00 -> belongs to the previous hotel day
      return dateOnly.subtract(const Duration(days: 1));
    } else if (isAfterCutoff(dt)) {
      // After 14:00:00 (even by 1 second) -> belongs to the next hotel day
      return dateOnly.add(const Duration(days: 1));
    } else {
      // Exactly at 14:00:00 -> current hotel day
      return dateOnly;
    }
  }

  // ---------------------------------------------------------------------------
  // Cutoff helpers
  // ---------------------------------------------------------------------------

  /// Returns `true` if [time] is strictly after [boundaryHour]:00:00.
  ///
  /// Checks up to second-level granularity (consistent with
  /// [calculateDays]). Milliseconds and microseconds are ignored.
  ///
  /// Examples:
  /// - `14:00:00` -> `false`
  /// - `14:00:01` -> `true`
  /// - `13:59:59` -> `false`
  /// - `15:00:00` -> `true`
  static bool isAfterCutoff(DateTime time) {
    if (time.hour > boundaryHour) return true;
    if (time.hour == boundaryHour &&
        (time.minute > 0 || time.second > 0)) {
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Day count calculation
  // ---------------------------------------------------------------------------

  /// Calculates the number of hotel days between [checkIn] and [checkOut].
  ///
  /// If [checkOut] is `null`, the current date and time ([DateTime.now()])
  /// is used.
  ///
  /// Uses calendar-date difference plus a boundary-hour adjustment:
  /// - First compute the raw calendar-day difference.
  /// - If the result is 0, treat it as 1 (minimum one day).
  /// - If checkout time is after 14:00:00, add 1 extra day.
  ///
  /// ### Verification
  ///
  /// | Check-in          | Check-out          | Result |
  /// |-------------------|--------------------|--------| \
  /// | 01/01 14:01       | 02/01 14:00        | 1 day  |
  /// | 01/01 14:01       | 02/01 14:01        | 2 days |
  static int calculateDays(DateTime checkIn, {DateTime? checkOut}) {
    final end = checkOut ?? DateTime.now();

    final checkInDate = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final checkOutDate = DateTime(end.year, end.month, end.day);

    int days = checkOutDate.difference(checkInDate).inDays;

    // A stay that starts and ends on the same calendar date is at least 1 day.
    if (days == 0) days = 1;

    // If checkout time is strictly after 14:00:00, add 1 day.
    if (end.hour > boundaryHour ||
        (end.hour == boundaryHour && end.minute > 0) ||
        (end.hour == boundaryHour && end.minute == 0 && end.second > 0)) {
      days += 1;
    }

    return days;
  }

  // ---------------------------------------------------------------------------
  // Hotel day interval helpers
  // ---------------------------------------------------------------------------

  /// Returns the start instant (14:00:00) of the hotel day that [value]
  /// falls within.
  ///
  /// Equivalent to `hotelDayStart(getHotelDay(value))`.
  static DateTime hotelDayStart(DateTime value) {
    final hotelDay = getHotelDay(value);
    return DateTime(hotelDay.year, hotelDay.month, hotelDay.day, boundaryHour);
  }

  /// Returns the end instant (14:00:00 of the following day) of the hotel
  /// day that [value] falls within.
  ///
  /// Equivalent to `hotelDayEnd(getHotelDay(value))`.
  static DateTime hotelDayEnd(DateTime value) {
    final hotelDay = getHotelDay(value);
    return DateTime(hotelDay.year, hotelDay.month, hotelDay.day + 1, boundaryHour);
  }

  // ---------------------------------------------------------------------------
  // Pricing
  // ---------------------------------------------------------------------------

  /// Calculates the total amount for a hotel stay.
  ///
  /// - [pricePerNight] – cost per hotel day (must be non-negative).
  /// - [checkIn] – check-in date/time.
  /// - [checkOut] – optional check-out date/time (defaults to now).
  /// - [discount] – amount to subtract from the total (defaults to 0).
  ///
  /// The returned value is clamped to zero (never negative).
  static int calculateTotalAmount(
    int pricePerNight,
    DateTime checkIn, {
    DateTime? checkOut,
    int discount = 0,
  }) {
    final days = calculateDays(checkIn, checkOut: checkOut);
    final total = (days * pricePerNight) - discount;
    return total < 0 ? 0 : total;
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  /// Formats a [date] as a zero-padded `yyyy-MM-dd` string.
  ///
  /// ```dart
  /// HotelTimeEngine.formatHotelDay(DateTime(2022, 1, 5))
  /// // => '2022-01-05'
  /// ```
  static String formatHotelDay(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
