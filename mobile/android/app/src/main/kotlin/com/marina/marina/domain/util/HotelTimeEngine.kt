package com.marina.marina.domain.util

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Single source of truth for all hotel day calculations.
 * Ported 1:1 from the Flutter app's `lib/services/hotel_time_engine.dart`.
 *
 * ## Business Rules
 *
 * The hotel day boundary is at **14:01** (2:01 PM).
 *
 * | Time             | Classification      |
 * |------------------|---------------------|
 * | Before 14:01:00  | Previous hotel day  |
 * | Exactly 14:01:00 | Current hotel day   |
 * | After 14:01:00   | Current hotel day   |
 *
 * 14:00:59 marks the **end** of the current hotel day.
 * Times at 14:01:00 or later belong to the next hotel day.
 */
object HotelTimeEngine {

    /** The hour at which the hotel day boundary occurs (14 = 2:00 PM). */
    const val BOUNDARY_HOUR = 14

    /** The minute at which the hotel day boundary occurs (01). The hotel day starts at 14:01, not 14:00. */
    const val BOUNDARY_MINUTE = 1

    private val hotelDayFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    // ---------------------------------------------------------------------------
    // Core day resolution
    // ---------------------------------------------------------------------------

    /**
     * Determines the hotel day (date-only `yyyy-MM-dd` key) for a given [time].
     *
     * - **Before** 14:01:00 -> previous hotel day
     * - **At or after** 14:01:00 -> current hotel day
     */
    fun hotelDayKey(time: Long): String {
        val cal = Calendar.getInstance()
        cal.timeInMillis = time
        if (!isAfterCutoff(cal)) {
            cal.add(Calendar.DAY_OF_YEAR, -1)
        }
        return hotelDayFormat.format(cal.time)
    }

    /** Hotel day key for the current instant. */
    fun currentHotelDayKey(): String = hotelDayKey(System.currentTimeMillis())

    /** Hotel day key for a [Date]. */
    fun hotelDayKey(date: Date): String = hotelDayKey(date.time)

    // ---------------------------------------------------------------------------
    // Cutoff helpers
    // ---------------------------------------------------------------------------

    /**
     * Returns `true` if the calendar's time-of-day is at or after 14:01:00.
     *
     * Examples: `14:00:59` -> false, `14:01:00` -> true, `13:59:59` -> false, `15:00:00` -> true.
     */
    fun isAfterCutoff(cal: Calendar): Boolean {
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        val minute = cal.get(Calendar.MINUTE)
        return hour > BOUNDARY_HOUR || (hour == BOUNDARY_HOUR && minute >= BOUNDARY_MINUTE)
    }

    /** Convenience overload for a raw epoch-millis instant. */
    fun isAfterCutoff(time: Long): Boolean {
        val cal = Calendar.getInstance()
        cal.timeInMillis = time
        return isAfterCutoff(cal)
    }

    // ---------------------------------------------------------------------------
    // Day count calculation
    // ---------------------------------------------------------------------------

    /**
     * Calculates the number of hotel days between [checkIn] and [checkOut].
     *
     * If [checkOut] is `null` (or in the past relative to check-in), the current
     * instant is used. Uses calendar-date difference plus a boundary-hour
     * adjustment:
     * - First compute the raw calendar-day difference.
     * - If the result is 0, treat it as 1 (minimum one day).
     * - If checkout time is at or after 14:01:00, add 1 extra day.
     *
     * Verification:
     * | Check-in   | Check-out   | Result |
     * |------------|-------------|--------|
     * | 01/01 14:01| 02/01 14:00 | 1 day  |
     * | 01/01 14:01| 02/01 14:01 | 2 days |
     */
    fun calculateDays(checkIn: Long, checkOut: Long? = null): Int {
        val end = checkOut ?: System.currentTimeMillis()

        val checkInCal = Calendar.getInstance().apply { timeInMillis = checkIn }
        val checkOutCal = Calendar.getInstance().apply { timeInMillis = end }

        val checkInDay = Calendar.getInstance().apply {
            set(checkInCal.get(Calendar.YEAR), checkInCal.get(Calendar.MONTH), checkInCal.get(Calendar.DAY_OF_MONTH), 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val checkOutDay = Calendar.getInstance().apply {
            set(checkOutCal.get(Calendar.YEAR), checkOutCal.get(Calendar.MONTH), checkOutCal.get(Calendar.DAY_OF_MONTH), 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }

        var days = ((checkOutDay.timeInMillis - checkInDay.timeInMillis) / (24L * 60 * 60 * 1000)).toInt()

        // A stay that starts and ends on the same calendar date is at least 1 day.
        if (days == 0) days = 1

        // If checkout time is at or after 14:01:00, add 1 day.
        if (isAfterCutoff(checkOutCal)) days += 1

        return days
    }

    // ---------------------------------------------------------------------------
    // Night counting — Dart `Time.nightsWithCutoff` (lib/utils/time.dart)
    // ---------------------------------------------------------------------------

    /**
     * The night counter used by ALL payment-processing screens in the Flutter
     * app (`booking_payment_screen`, `booking_checkout_screen`,
     * `EnhancedBookingCalculationService`, guest detail report, invoices).
     *
     * Ported 1:1 from Dart:
     * ```
     * startOfCheckinHotelDay = DateTime(y, m, d, 14, 1);
     * if (checkin.isBefore(startOfCheckinHotelDay)) startOfCheckinHotelDay -= 1 day;
     * totalSeconds = (end - startOfCheckinHotelDay).inSeconds;
     * if (totalSeconds <= 0) return 1;
     * nights = totalSeconds ~/ 86400 + 1;   // reaching 14:01 exactly adds a full night
     * return max(nights, 1);
     * ```
     *
     * Key differences from [calculateDays] (which mirrors the *other* Dart
     * algorithm, `HotelTimeEngine.calculateDays`):
     * - A check-in **before 14:01** belongs to the *previous* hotel day
     *   (a morning check-in therefore bills one extra night vs calculateDays).
     * - A same-day stay with both check-in and check-out after 14:01 counts
     *   as **1** night (calculateDays would say 2).
     */
    fun nightsWithCutoff(checkIn: Long, checkOut: Long? = null): Int {
        val end = checkOut ?: System.currentTimeMillis()

        val checkInCal = Calendar.getInstance().apply { timeInMillis = checkIn }
        // Start of the check-in hotel day at 14:01 on the same calendar date.
        val startCal = Calendar.getInstance().apply {
            set(
                checkInCal.get(Calendar.YEAR), checkInCal.get(Calendar.MONTH),
                checkInCal.get(Calendar.DAY_OF_MONTH), BOUNDARY_HOUR, BOUNDARY_MINUTE, 0
            )
            set(Calendar.MILLISECOND, 0)
        }
        // A check-in before 14:01 belongs to the previous hotel day.
        if (checkInCal.timeInMillis < startCal.timeInMillis) {
            startCal.add(Calendar.DAY_OF_YEAR, -1)
        }

        val totalSeconds = ((end - startCal.timeInMillis) / 1000L).toInt()
        if (totalSeconds <= 0) return 1
        val nights = totalSeconds / (24 * 3600) + 1
        return if (nights > 0) nights else 1
    }

    /**
     * Ported from Dart `_countNightsWithDiscount` (booking_payment_screen.dart):
     * number of nights affected by a per-night discount whose start date is
     * [discountStartDateIso]. The discount start day is normalized to the
     * 14:01 boundary; the effective start is `max(discountDayStart, checkin)`.
     */
    fun countNightsWithDiscount(checkIn: Long, checkOut: Long?, discountStartDateIso: String?): Int {
        if (discountStartDateIso.isNullOrBlank()) return 0
        val discountStart = parseDate(discountStartDateIso) ?: return 0
        // Normalize the discount day to its 14:01 hotel-day start.
        val dayStart = Calendar.getInstance().apply { timeInMillis = discountStart }
        val normalized = Calendar.getInstance().apply {
            set(
                dayStart.get(Calendar.YEAR), dayStart.get(Calendar.MONTH),
                dayStart.get(Calendar.DAY_OF_MONTH), BOUNDARY_HOUR, BOUNDARY_MINUTE, 0
            )
            set(Calendar.MILLISECOND, 0)
        }
        val effectiveStart = maxOf(normalized.timeInMillis, checkIn)
        if (checkOut != null && checkOut <= effectiveStart) return 0
        return nightsWithCutoff(effectiveStart, checkOut)
    }

    // ---------------------------------------------------------------------------
    // Hotel day interval helpers
    // ---------------------------------------------------------------------------

    /** Returns the start instant (14:01:00) of the hotel day that [time] falls within. */
    fun hotelDayStart(time: Long): Long {
        val cal = Calendar.getInstance().apply { timeInMillis = time }
        if (!isAfterCutoff(cal)) cal.add(Calendar.DAY_OF_YEAR, -1)
        cal.set(Calendar.HOUR_OF_DAY, BOUNDARY_HOUR)
        cal.set(Calendar.MINUTE, BOUNDARY_MINUTE)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    /** Returns the end instant (14:01:00 of the following day) of the hotel day that [time] falls within. */
    fun hotelDayEnd(time: Long): Long {
        val cal = Calendar.getInstance().apply { timeInMillis = hotelDayStart(time) }
        cal.add(Calendar.DAY_OF_YEAR, 1)
        return cal.timeInMillis
    }

    // ---------------------------------------------------------------------------
    // Pricing
    // ---------------------------------------------------------------------------

    /**
     * Calculates the total amount for a hotel stay (clamped to zero).
     *
     * - [pricePerNight] – cost per hotel day (must be non-negative).
     * - [checkIn] / [checkOut] – stay bounds (checkout defaults to now).
     * - [discount] – amount to subtract from the total.
     */
    fun calculateTotalAmount(pricePerNight: Double, checkIn: Long, checkOut: Long? = null, discount: Double = 0.0): Double {
        val days = calculateDays(checkIn, checkOut)
        val total = days * pricePerNight - discount
        return if (total < 0) 0.0 else total
    }

    // ---------------------------------------------------------------------------
    // Formatting / parsing
    // ---------------------------------------------------------------------------

    private val displayFormat = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.US)
    private val displayDateOnlyFormat = SimpleDateFormat("dd/MM/yyyy", Locale.US)
    private val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)

    /** Formats an epoch instant as `dd/MM/yyyy HH:mm`. */
    fun formatDisplay(time: Long): String = displayFormat.format(Date(time))

    /** Formats an epoch instant as `dd/MM/yyyy`. */
    fun formatDisplayDateOnly(time: Long): String = displayDateOnlyFormat.format(Date(time))

    /** Formats an epoch instant as ISO `yyyy-MM-ddTHH:mm:ss`. */
    fun formatIso(time: Long): String = isoFormat.format(Date(time))

    /** Best-effort parse of the app's stored date strings (ISO or `yyyy-MM-dd HH:mm`). */
    fun parseDate(raw: String?): Long? {
        if (raw.isNullOrBlank()) return null
        val trimmed = raw.trim().replace("Z", "").replace("T", " ")
        val patterns = listOf(
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
            "dd/MM/yyyy HH:mm", "dd/MM/yyyy"
        )
        for (pattern in patterns) {
            try {
                val fmt = SimpleDateFormat(pattern, Locale.US)
                fmt.isLenient = true
                val parsed = fmt.parse(trimmed)
                if (parsed != null) return parsed.time
            } catch (_: Exception) {
                // try next pattern
            }
        }
        return null
    }
}
