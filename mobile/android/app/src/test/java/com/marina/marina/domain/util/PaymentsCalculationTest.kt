package com.marina.marina.domain.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

/**
 * Unit tests for the payments-processing calculation contract, ported from
 * the Flutter `Time.nightsWithCutoff` / `CurrencyFormatter` /
 * `booking_payment_screen.dart` expectations.
 */
class PaymentsCalculationTest {

    private fun millis(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0): Long {
        val cal = Calendar.getInstance()
        cal.set(year, month - 1, day, hour, minute, second)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    // -------------------------------------------------------------------------
    // nightsWithCutoff — Dart `Time.nightsWithCutoff` contract
    // -------------------------------------------------------------------------

    @Test
    fun `one night when checkout next day before 1401`() {
        // 2026-09-01 14:01 → 2026-09-02 14:00 = 1 night (86340s → 0 + 1).
        assertEquals(1, HotelTimeEngine.nightsWithCutoff(
            millis(2026, 9, 1, 14, 1), millis(2026, 9, 2, 14, 0)
        ))
    }

    @Test
    fun `reaching 1401 exactly adds a full night`() {
        // Exactly 86400s → 1 + 1 = 2.
        assertEquals(2, HotelTimeEngine.nightsWithCutoff(
            millis(2026, 9, 1, 14, 1), millis(2026, 9, 2, 14, 1)
        ))
    }

    @Test
    fun `same-day stay after cutoff is one night`() {
        // Check-in 15:00 → check-out 20:00 same date: duration 5h59m → 1 night.
        assertEquals(1, HotelTimeEngine.nightsWithCutoff(
            millis(2026, 9, 1, 15, 0), millis(2026, 9, 1, 20, 0)
        ))
    }

    @Test
    fun `morning checkin rolls back to previous hotel day`() {
        // Check-in 10:00 → check-out 15:00 next day:
        // start = prev day 14:01 → duration 2d59m → 2 + 1 = 3 nights
        // (hotel days: day-1, day1, day2).
        assertEquals(3, HotelTimeEngine.nightsWithCutoff(
            millis(2026, 9, 1, 10, 0), millis(2026, 9, 2, 15, 0)
        ))
    }

    @Test
    fun `morning checkin morning checkout next day`() {
        // start = day0 14:01 → day2 10:00 = 1d19h59m → 1 + 1 = 2 nights.
        assertEquals(2, HotelTimeEngine.nightsWithCutoff(
            millis(2026, 9, 1, 10, 0), millis(2026, 9, 2, 10, 0)
        ))
    }

    @Test
    fun `minimum one night when checkout before checkin`() {
        assertEquals(1, HotelTimeEngine.nightsWithCutoff(
            millis(2026, 9, 2, 15, 0), millis(2026, 9, 1, 10, 0)
        ))
    }

    @Test
    fun `two nights for a standard next-evening stay`() {
        // 14:01 day1 → 20:00 day2: 1d5h59m → 1 + 1 = 2.
        assertEquals(2, HotelTimeEngine.nightsWithCutoff(
            millis(2026, 9, 1, 14, 1), millis(2026, 9, 2, 20, 0)
        ))
    }

    // -------------------------------------------------------------------------
    // countNightsWithDiscount
    // -------------------------------------------------------------------------

    @Test
    fun `discount start after checkout yields zero nights`() {
        val nights = HotelTimeEngine.countNightsWithDiscount(
            millis(2026, 9, 1, 14, 1), millis(2026, 9, 3, 14, 0), "2026-09-04"
        )
        assertEquals(0, nights)
    }

    @Test
    fun `discount covering the last night`() {
        // Check-in 9/1 14:01, checkout 9/3 14:00 = 2 nights; discount from 9/2.
        // Effective start = max(9/2 14:01, checkin) = 9/2 14:01 → 9/3 14:00 = 1 night.
        val nights = HotelTimeEngine.countNightsWithDiscount(
            millis(2026, 9, 1, 14, 1), millis(2026, 9, 3, 14, 0), "2026-09-02"
        )
        assertEquals(1, nights)
    }

    // -------------------------------------------------------------------------
    // CurrencyFormatter
    // -------------------------------------------------------------------------

    @Test
    fun `format adds thousands separators without decimals`() {
        assertEquals("5,000", CurrencyFormatter.formatAmount(5000.0))
        assertEquals("1,250,000", CurrencyFormatter.formatAmount(1250000.0))
        assertEquals("0", CurrencyFormatter.formatAmount(0.0))
    }

    @Test
    fun `format truncates toward zero never rounds up`() {
        assertEquals("1,000", CurrencyFormatter.formatAmount(1000.99))
        assertEquals("-500", CurrencyFormatter.formatAmount(-500.5))
    }

    @Test
    fun `parse maps arabic digits and separators`() {
        assertEquals(1500.0, CurrencyFormatter.parseAmount("١٬٥٠٠")!!, 0.001)
        assertEquals(2500.0, CurrencyFormatter.parseAmount("2,500")!!, 0.001)
        assertEquals(1000.0, CurrencyFormatter.parseAmount("1000.5")!!, 0.001)
    }

    @Test
    fun `parse returns null for invalid input`() {
        assertNull(CurrencyFormatter.parseAmount(""))
        assertNull(CurrencyFormatter.parseAmount("abc"))
    }

    // -------------------------------------------------------------------------
    // BookingFinancials.calculate — the master booking-payment formula
    // -------------------------------------------------------------------------

    private fun booking(
        checkin: String = "2026-09-01 14:01",
        checkout: String? = "2026-09-03 14:00",
        discount: Double = 0.0,
        discountType: String = "per_night",
        discountStartDate: String? = null,
        calculatedNights: Int = 2
    ) = com.marina.marina.domain.model.Booking(
        checkinDate = checkin, checkoutDate = checkout, discount = discount,
        discountType = discountType, discountStartDate = discountStartDate,
        calculatedNights = calculatedNights, expectedNights = 2
    )

    @Test
    fun `two nights at room price with no discount`() {
        val summary = BookingFinancials.calculate(booking(), roomRate = 5000.0, payments = emptyList())
        assertEquals(10000.0, summary.totalAmount, 0.001)
        assertEquals(10000.0, summary.remainingAmount, 0.001)
    }

    @Test
    fun `total discount is subtracted once and clamped to zero`() {
        val summary = BookingFinancials.calculate(
            booking(discount = 3000.0, discountType = "total"), roomRate = 5000.0, payments = emptyList()
        )
        assertEquals(7000.0, summary.totalAmount, 0.001)
    }

    @Test
    fun `per-night discount applies reduced rate to discounted nights only`() {
        // 2 nights, discount from check-in: both nights discounted.
        // Fixed "now" so the live-nights accrual (Dart uses now when no
        // actual checkout) does not grow the bill during the test.
        val summary = BookingFinancials.calculate(
            booking(discount = 1000.0, discountType = "per_night", discountStartDate = "2026-09-01"),
            roomRate = 5000.0, payments = emptyList(),
            nowMillis = millis(2026, 9, 3, 14, 0)
        )
        // fullNights=0, discountedNights=2 → 2 × (5000-1000) = 8000.
        assertEquals(8000.0, summary.totalAmount, 0.001)
    }

    @Test
    fun `paid amount excludes voided payments and remaining clamps at zero`() {
        val payments = listOf(
            com.marina.marina.domain.model.Payment(amount = 6000.0, isVoided = false),
            com.marina.marina.domain.model.Payment(amount = 2000.0, isVoided = true),
            com.marina.marina.domain.model.Payment(amount = 5000.0, isVoided = false)
        )
        val summary = BookingFinancials.calculate(booking(), roomRate = 5000.0, payments = payments)
        assertEquals(11000.0, summary.paidAmount, 0.001)
        assertEquals(0.0, summary.remainingAmount, 0.001)
        assertTrue(summary.isFullyPaid)
    }

    // -------------------------------------------------------------------------
    // Early checkout refund
    // -------------------------------------------------------------------------

    @Test
    fun `early checkout refunds unused nights`() {
        val b = com.marina.marina.domain.model.Booking(
            checkinDate = "2026-09-01 14:01",
            checkoutDate = "2026-09-04 14:00",
            calculatedNights = 3, expectedNights = 3
        )
        // Leave on 9/2 14:00 → actual 1 night, planned 3, unused 2.
        val early = BookingFinancials.earlyCheckout(
            b, roomRate = 5000.0, paidAmount = 15000.0,
            nowMillis = millis(2026, 9, 2, 14, 0)
        )!!
        assertEquals(1, early.actualNights)
        assertEquals(3, early.plannedNights)
        assertEquals(2, early.unusedNights)
        assertEquals(5000.0, early.actualNightsCost, 0.001)
        assertEquals(10000.0, early.refundAmount, 0.001)
    }

    // -------------------------------------------------------------------------
    // Phone normalization
    // -------------------------------------------------------------------------

    @Test
    fun `phone normalization keeps 967 prefix and converts local numbers`() {
        assertEquals("967773458745", BookingFinancials.cleanAndFormatPhone("967773458745"))
        assertEquals("967734587456", BookingFinancials.cleanAndFormatPhone("0734587456"))
        assertEquals("967734587456", BookingFinancials.cleanAndFormatPhone("734587456"))
    }
}
