package com.marina.marina.domain.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

/**
 * HotelTimeEngine unit tests — the financial day-boundary contract
 * (14:01 hotel day) ported from the Flutter `hotel_time_engine_test.dart`
 * expectations.
 */
class HotelTimeEngineTest {

    private fun millis(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0): Long {
        val cal = Calendar.getInstance()
        cal.set(year, month - 1, day, hour, minute, second)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    // -------------------------------------------------------------------------
    // Hotel day key resolution
    // -------------------------------------------------------------------------

    @Test
    fun `before 1401 belongs to previous hotel day`() {
        // 2026-09-18 14:00:59 → hotel day 2026-09-17
        val key = HotelTimeEngine.hotelDayKey(millis(2026, 9, 18, 14, 0, 59))
        assertEquals("2026-09-17", key)
    }

    @Test
    fun `exactly 1401 starts the current hotel day`() {
        val key = HotelTimeEngine.hotelDayKey(millis(2026, 9, 18, 14, 1, 0))
        assertEquals("2026-09-18", key)
    }

    @Test
    fun `after 1401 belongs to current hotel day`() {
        val key = HotelTimeEngine.hotelDayKey(millis(2026, 9, 18, 23, 30, 0))
        assertEquals("2026-09-18", key)
    }

    @Test
    fun `early morning belongs to previous calendar day`() {
        // 2026-09-18 01:00 → hotel day 2026-09-17
        val key = HotelTimeEngine.hotelDayKey(millis(2026, 9, 18, 1, 0, 0))
        assertEquals("2026-09-17", key)
    }

    @Test
    fun `noon belongs to previous calendar day`() {
        val key = HotelTimeEngine.hotelDayKey(millis(2026, 9, 18, 12, 0, 0))
        assertEquals("2026-09-17", key)
    }

    // -------------------------------------------------------------------------
    // Cutoff helper
    // -------------------------------------------------------------------------

    @Test
    fun `cutoff boundaries`() {
        assertFalse(HotelTimeEngine.isAfterCutoff(millis(2026, 9, 18, 13, 59, 59)))
        assertTrue(HotelTimeEngine.isAfterCutoff(millis(2026, 9, 18, 14, 1, 0)))
        assertTrue(HotelTimeEngine.isAfterCutoff(millis(2026, 9, 18, 15, 0, 0)))
        assertFalse(HotelTimeEngine.isAfterCutoff(millis(2026, 9, 18, 0, 0, 0)))
    }

    // -------------------------------------------------------------------------
    // Day count / pricing
    // -------------------------------------------------------------------------

    @Test
    fun `one night when checkout next day before 1401`() {
        // Check-in 2026-09-01 14:01 → Check-out 2026-09-02 14:00 = 1 day
        val days = HotelTimeEngine.calculateDays(
            millis(2026, 9, 1, 14, 1, 0),
            millis(2026, 9, 2, 14, 0, 0)
        )
        assertEquals(1, days)
    }

    @Test
    fun `two nights when checkout at or after 1401`() {
        // Check-in 2026-09-01 14:01 → Check-out 2026-09-02 14:01 = 2 days
        val days = HotelTimeEngine.calculateDays(
            millis(2026, 9, 1, 14, 1, 0),
            millis(2026, 9, 2, 14, 1, 0)
        )
        assertEquals(2, days)
    }

    @Test
    fun `same calendar dates count as at least one day`() {
        // Check-in 01:00 → Check-out 10:00 same date (before the 14:01 cutoff):
        // calendar diff 0 → minimum 1 day, no cutoff surcharge = 1 day.
        val days = HotelTimeEngine.calculateDays(
            millis(2026, 9, 1, 1, 0, 0),
            millis(2026, 9, 1, 10, 0, 0)
        )
        assertEquals(1, days)
    }

    @Test
    fun `same-day checkout after cutoff bills two days`() {
        // Flutter contract parity: calendar diff 0 → 1, checkout 20:00 is at
        // or after 14:01 → +1 surcharge = 2 days (identical to Dart engine).
        val days = HotelTimeEngine.calculateDays(
            millis(2026, 9, 1, 15, 0, 0),
            millis(2026, 9, 1, 20, 0, 0)
        )
        assertEquals(2, days)
    }

    @Test
    fun `total amount multiplies days by nightly price`() {
        val total = HotelTimeEngine.calculateTotalAmount(
            pricePerNight = 250.0,
            checkIn = millis(2026, 9, 1, 14, 1, 0),
            checkOut = millis(2026, 9, 3, 14, 0, 0)
        )
        assertEquals(500.0, total, 0.001)
    }

    @Test
    fun `discount subtracted and clamped to zero`() {
        val total = HotelTimeEngine.calculateTotalAmount(
            pricePerNight = 200.0,
            checkIn = millis(2026, 9, 1, 14, 1, 0),
            checkOut = millis(2026, 9, 2, 14, 0, 0),
            discount = 300.0
        )
        assertEquals(0.0, total, 0.001)
    }

    // -------------------------------------------------------------------------
    // Interval helpers
    // -------------------------------------------------------------------------

    @Test
    fun `hotel day start and end bracket the day`() {
        val ref = millis(2026, 9, 18, 20, 0, 0)
        val start = HotelTimeEngine.hotelDayStart(ref)
        val end = HotelTimeEngine.hotelDayEnd(ref)

        val startCal = Calendar.getInstance().apply { timeInMillis = start }
        assertEquals(14, startCal.get(Calendar.HOUR_OF_DAY))
        assertEquals(1, startCal.get(Calendar.MINUTE))
        assertEquals(18, startCal.get(Calendar.DAY_OF_MONTH))

        assertEquals(24 * 60 * 60 * 1000L, end - start)
    }

    // -------------------------------------------------------------------------
    // Parsing
    // -------------------------------------------------------------------------

    @Test
    fun `parses iso and display formats`() {
        assertTrue(HotelTimeEngine.parseDate("2026-09-18T20:15:00") != null)
        assertTrue(HotelTimeEngine.parseDate("2026-09-18 20:15") != null)
        assertTrue(HotelTimeEngine.parseDate("18/09/2026 20:15") != null)
        assertNull(HotelTimeEngine.parseDate(null))
        assertNull(HotelTimeEngine.parseDate(""))
    }
}
