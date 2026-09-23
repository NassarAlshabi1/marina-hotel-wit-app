package com.marina.marina.domain.util

import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.BookingNight
import com.marina.marina.domain.model.Payment
import java.util.Calendar

/**
 * The single financial calculation used by the payment-processing screens,
 * ported 1:1 from `booking_payment_screen.dart` (build(), l.257-447) and
 * shared with `booking_checkout_screen.dart` (l.119-186).
 *
 * Priority of night totals:
 * 1. Per-night ledger (`BookingNight`) when non-empty — sum of
 *    `finalRate > 0 ? finalRate : nightlyRate`.
 * 2. Fallback formula using [HotelTimeEngine.nightsWithCutoff] and the
 *    per-night discount split (`_countNightsWithDiscount`).
 *
 * `totalAmount` then applies a `total`-type discount with a clamp to
 * `[0, nightTotal]`.
 */
object BookingFinancials {

    data class Summary(
        val roomRate: Double,
        val nightsCount: Int,
        val expectedNights: Int,
        val nightTotal: Double,
        val totalAmount: Double,
        val paidAmount: Double,
        val todayPaidAmount: Double,
        val remainingAmount: Double,
        val lastPayment: Payment?,
        val discountedNights: Int,
        val surchargeNights: Int,
        val normalNights: Int,
        val totalDiscount: Double,
        val totalSurcharge: Double,
        val hasDebt: Boolean,
        val debtAmount: Double
    ) {
        val isFullyPaid: Boolean get() = remainingAmount <= 0
        val paidPercentage: Double get() = if (totalAmount > 0) (paidAmount / totalAmount) * 100 else 0.0
    }

    fun calculate(
        booking: Booking,
        roomRate: Double,
        payments: List<Payment>,
        nights: List<BookingNight> = emptyList(),
        debtRemaining: Double = 0.0,
        nowMillis: Long = System.currentTimeMillis()
    ): Summary {
        val checkinMillis = HotelTimeEngine.parseDate(booking.checkinDate)
        val actualCheckoutMillis = HotelTimeEngine.parseDate(booking.actualCheckout)
        val plannedCheckoutMillis = HotelTimeEngine.parseDate(booking.checkoutDate)

        // actualNights = booking.calculatedNights (Dart l.305 — refreshed by the
        // derived-fields service with nightsWithCutoff).
        val actualNights = if (booking.calculatedNights > 0) booking.calculatedNights else booking.expectedNights

        val discount = booking.discount
        val discountType = booking.discountType

        // ------------------------------------------------------------------
        // nightTotal — per-night ledger preferred, fallback formula otherwise.
        // ------------------------------------------------------------------
        val nightTotal: Double = if (nights.isNotEmpty()) {
            nights.sumOf { if (it.finalRate > 0) it.finalRate else it.nightlyRate }
        } else {
            val checkout = actualCheckoutMillis ?: nowMillis
            if (discount > 0 && discountType == "per_night" && checkinMillis != null) {
                val discountedNights = HotelTimeEngine.countNightsWithDiscount(
                    checkinMillis, checkout, booking.discountStartDate
                )
                val fullNights = (actualNights - discountedNights).coerceAtLeast(0)
                val discountedRate = (roomRate - discount).coerceIn(0.0, roomRate)
                (fullNights * roomRate) + (discountedNights * discountedRate)
            } else {
                actualNights * roomRate
            }
        }

        // totalAmount with total-type discount (clamped to [0, nightTotal]).
        val totalAmount = if (discount > 0 && discountType == "total") {
            (nightTotal - discount).coerceIn(0.0, nightTotal)
        } else nightTotal

        // ------------------------------------------------------------------
        // Discount / surcharge night breakdown.
        // ------------------------------------------------------------------
        var discountedNights = 0
        var surchargeNights = 0
        var totalDiscount = 0.0
        var totalSurcharge = 0.0
        if (nights.isNotEmpty()) {
            discountedNights = nights.count { it.adjustment < 0 }
            surchargeNights = nights.count { it.adjustment > 0 }
            totalDiscount = nights.filter { it.adjustment < 0 }.sumOf { -it.adjustment }
            totalSurcharge = nights.filter { it.adjustment > 0 }.sumOf { it.adjustment }
            // Legacy-data guard (Dart l.370-386): ignore stale ledger discounts
            // when the booking itself carries no discount and the rates look
            // like un-adjusted copies. Real discounts (finalRate BELOW baseRate)
            // are KEPT — Dart only zeroes when no base rates exist at all, or
            // when every night's finalRate equals its baseRate.
            if (discount <= 0 && totalDiscount > 0) {
                val hasValidBaseRates = nights.any { it.baseRate > 0 }
                val allRatesMatchBase = nights.all { kotlin.math.abs(it.finalRate - it.baseRate) < 0.01 }
                if (!hasValidBaseRates || allRatesMatchBase) {
                    totalDiscount = 0.0
                    discountedNights = 0
                }
            }
        } else if (discount > 0) {
            if (discountType == "per_night" && checkinMillis != null) {
                val checkout = actualCheckoutMillis ?: nowMillis
                discountedNights = HotelTimeEngine.countNightsWithDiscount(
                    checkinMillis, checkout, booking.discountStartDate
                )
                totalDiscount = discountedNights * discount
            } else {
                totalDiscount = discount
            }
        }
        val normalNights = (actualNights - discountedNights - surchargeNights).coerceAtLeast(0)

        // ------------------------------------------------------------------
        // Paid amounts (voided excluded — Dart l.402-433).
        // ------------------------------------------------------------------
        val validPayments = payments.filter { !it.isVoided }
        val paidAmount = validPayments.sumOf { it.amount }
        val todayPaidAmount = validPayments.filter {
            val hotelDay = HotelTimeEngine.currentHotelDayKey()
            it.hotelDayKey == hotelDay || (it.hotelDayKey == null && it.paymentDate.startsWith(hotelDay))
        }.sumOf { it.amount }
        val lastPayment = validPayments.maxByOrNull { it.paymentDate }

        val remainingAmount = (totalAmount - paidAmount).coerceAtLeast(0.0)

        val nightsCount = if (nights.isNotEmpty()) nights.size else actualNights

        return Summary(
            roomRate = roomRate,
            nightsCount = nightsCount,
            expectedNights = booking.expectedNights,
            nightTotal = nightTotal,
            totalAmount = totalAmount,
            paidAmount = paidAmount,
            todayPaidAmount = todayPaidAmount,
            remainingAmount = remainingAmount,
            lastPayment = lastPayment,
            discountedNights = discountedNights,
            surchargeNights = surchargeNights,
            normalNights = normalNights,
            totalDiscount = totalDiscount,
            totalSurcharge = totalSurcharge,
            hasDebt = debtRemaining > 0,
            debtAmount = debtRemaining
        )
    }

    /**
     * Dart `StayBalanceCalculator` — the auto-checkout estimate shown on the
     * summary card: nights fully covered by cumulative paid payments and the
     * resulting automatic checkout date. Simplified to the no-adjustment case
     * (rate constant across the stay), which matches the Dart day-by-day
     * simulation whenever no price adjustments are active.
     */
    data class StayBalance(
        val totalPaidNights: Int,
        val autoCheckoutMillis: Long?,
        val isAutoExtended: Boolean
    )

    fun stayBalance(
        booking: Booking,
        roomRate: Double,
        paidAmount: Double,
        nowMillis: Long = System.currentTimeMillis()
    ): StayBalance {
        if (roomRate <= 0 || paidAmount <= 0) return StayBalance(0, null, false)
        val checkinMillis = HotelTimeEngine.parseDate(booking.checkinDate) ?: return StayBalance(0, null, false)
        val paidNights = (paidAmount / roomRate).toInt()
        // Auto-checkout = check-in date (date-only) + paidNights days.
        val checkinDay = Calendar.getInstance().apply {
            timeInMillis = checkinMillis
            set(Calendar.HOUR_OF_DAY, 12); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        checkinDay.add(Calendar.DAY_OF_YEAR, paidNights)
        val planned = HotelTimeEngine.parseDate(booking.checkoutDate)
        val isAutoExtended = planned != null && checkinDay.timeInMillis > planned
        return StayBalance(paidNights, checkinDay.timeInMillis, isAutoExtended)
    }

    /**
     * Dart `_shouldShowExtendedStayOptions` (l.1171-1188): true when the guest
     * has stayed past the planned checkout (`currentStay > expectedNights` or
     * `now > plannedCheckout`).
     */
    fun isExtendedStayActive(booking: Booking, nowMillis: Long = System.currentTimeMillis()): Boolean {
        val checkinMillis = HotelTimeEngine.parseDate(booking.checkinDate) ?: return false
        val plannedCheckout = HotelTimeEngine.parseDate(booking.checkoutDate)
        val currentStay = HotelTimeEngine.nightsWithCutoff(checkinMillis, nowMillis)
        val pastPlanned = plannedCheckout != null && nowMillis > plannedCheckout
        return currentStay > booking.expectedNights || pastPlanned
    }

    /**
     * Dart early-checkout refund calculation (l.2041-2103):
     * `unusedNights = plannedNights - actualNights`;
     * `refund = (totalPaid - actualNightsCost).clamp(0, totalPaid)`.
     */
    data class EarlyCheckout(
        val actualNights: Int,
        val plannedNights: Int,
        val unusedNights: Int,
        val actualNightsCost: Double,
        val refundAmount: Double
    )

    fun earlyCheckout(
        booking: Booking,
        roomRate: Double,
        paidAmount: Double,
        nights: List<BookingNight> = emptyList(),
        nowMillis: Long = System.currentTimeMillis()
    ): EarlyCheckout? {
        val checkinMillis = HotelTimeEngine.parseDate(booking.checkinDate) ?: return null
        val plannedCheckout = HotelTimeEngine.parseDate(booking.checkoutDate) ?: return null
        if (nowMillis >= plannedCheckout) return null

        val actualNights = HotelTimeEngine.nightsWithCutoff(checkinMillis, nowMillis)
        val plannedNights = HotelTimeEngine.nightsWithCutoff(checkinMillis, plannedCheckout)
        val unusedNights = plannedNights - actualNights

        val actualNightsCost = if (nights.isNotEmpty()) {
            nights.sortedBy { it.sequence }
                .take(actualNights.coerceIn(0, nights.size))
                .sumOf { if (it.finalRate > 0) it.finalRate else it.nightlyRate }
        } else {
            actualNights * roomRate
        }
        val refundAmount = (paidAmount - actualNightsCost).coerceIn(0.0, paidAmount)
        return EarlyCheckout(actualNights, plannedNights, unusedNights, actualNightsCost, refundAmount)
    }

    // -------------------------------------------------------------------------
    // Dart `_cleanAndFormatPhone` (booking_payment_screen.dart l.129-163)
    // -------------------------------------------------------------------------

    /** Normalizes a Yemeni/Saudi phone number to E.164-ish digits. */
    fun cleanAndFormatPhone(raw: String): String {
        var digits = raw.filter { it.isDigit() }
        if (digits.isBlank()) return ""
        if (digits.startsWith("00")) digits = digits.removePrefix("00")
        if (digits.startsWith("967")) return digits
        if (digits.startsWith("966")) return digits
        if (digits.startsWith("07") && digits.length >= 10) return "967${digits.substring(1)}"
        if (digits.startsWith("7") && digits.length == 9) return "967$digits"
        if (digits.startsWith("5") && digits.length == 9) return "966$digits"
        if (digits.length <= 10) return "967$digits"
        return digits
    }
}
