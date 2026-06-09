/// Single source of truth for all hotel day calculations.
///
/// ## Business Rules
///
/// The hotel day boundary is at **14:01** (2:01 PM).
///
/// | Time            | Classification      |
/// |-----------------|---------------------|
/// | Before 14:01:00 | Previous hotel day  |
/// | Exactly 14:01:00| Current hotel day   |
/// | After 14:01:00  | Current hotel day   |
///
/// 14:00:59 marks the **end** of the current hotel day.
/// Times at 14:01:00 or later belong to the next hotel day.
class HotelTimeEngine {
  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  /// The hour at which the hotel day boundary occurs (14 = 2:00 PM).
  static const int boundaryHour = 14;

  /// The minute at which the hotel day boundary occurs (01).
  /// The hotel day starts at 14:01, not 14:00.
  static const int boundaryMinute = 1;

  // ---------------------------------------------------------------------------
  // Core day resolution
  // ---------------------------------------------------------------------------

  /// Determines the hotel day (date-only) for a given [dt].
  ///
  /// The hotel day boundary works as follows:
  /// - **Before** 14:01:00  -> previous hotel day
  /// - **At or after** 14:01:00 -> current hotel day
  ///
  /// 14:00:59 is the **end** of the hotel day, so it maps to
  /// the previous day. 14:01:00 starts the next hotel day.
  ///
  /// Returns a [DateTime] with time set to midnight (00:00:00).
  static DateTime getHotelDay(DateTime dt) {
    final dateOnly = DateTime(dt.year, dt.month, dt.day);

    if (isAfterCutoff(dt)) {
      // At or after 14:01:00 -> current hotel day
      return dateOnly;
    } else {
      // Before 14:01:00 -> previous hotel day
      return dateOnly.subtract(const Duration(days: 1));
    }
  }

  // ---------------------------------------------------------------------------
  // Cutoff helpers
  // ---------------------------------------------------------------------------

  /// Returns `true` if [time] is at or after [boundaryHour]:[boundaryMinute]:00.
  ///
  /// Examples:
  /// - `14:00:59` -> `false`
  /// - `14:01:00` -> `true`
  /// - `13:59:59` -> `false`
  /// - `15:00:00` -> `true`
  static bool isAfterCutoff(DateTime time) {
    if (time.hour > boundaryHour) {
      return true;
    }
    if (time.hour == boundaryHour && time.minute >= boundaryMinute) {
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
  /// - If checkout time is at or after 14:01:00, add 1 extra day.
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
    if (days == 0) {
      days = 1;
    }

    // If checkout time is at or after 14:01:00, add 1 day.
    if (end.hour > boundaryHour ||
        (end.hour == boundaryHour && end.minute >= boundaryMinute)) {
      days += 1;
    }

    return days;
  }

  // ---------------------------------------------------------------------------
  // Hotel day interval helpers
  // ---------------------------------------------------------------------------

  /// Returns the start instant (14:01:00) of the hotel day that [value]
  /// falls within.
  ///
  /// Equivalent to `hotelDayStart(getHotelDay(value))`.
  static DateTime hotelDayStart(DateTime value) {
    final hotelDay = getHotelDay(value);
    return DateTime(hotelDay.year, hotelDay.month, hotelDay.day, boundaryHour, boundaryMinute);
  }

  /// Returns the end instant (14:01:00 of the following day) of the hotel
  /// day that [value] falls within.
  ///
  /// Equivalent to `hotelDayEnd(getHotelDay(value))`.
  static DateTime hotelDayEnd(DateTime value) {
    final hotelDay = getHotelDay(value);
    return DateTime(hotelDay.year, hotelDay.month, hotelDay.day + 1, boundaryHour, boundaryMinute);
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
