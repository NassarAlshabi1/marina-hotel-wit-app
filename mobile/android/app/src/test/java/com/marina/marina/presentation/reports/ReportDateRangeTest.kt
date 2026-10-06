package com.marina.marina.presentation.reports

import java.util.Calendar
import org.junit.Assert.assertEquals
import org.junit.Test

class ReportDateRangeTest {
    @Test
    fun startKeepsLegacyOneSecondAdjustmentAndEndStaysInclusive() {
        val range = ReportDateRange(time(4, 14, 0, 59), time(5, 14, 0, 59))
        assertEquals("2026-10-04", range.fromHotelDayKey)
        assertEquals("2026-10-04", range.toHotelDayKey)
        assertEquals("النطاق: 2026-10-04 14:01 - 2026-10-04 14:00", range.label)
    }

    @Test
    fun endAtCutoffBelongsToNextHotelDay() {
        val range = ReportDateRange(time(4, 14, 1, 0), time(5, 14, 1, 0))
        assertEquals("2026-10-04", range.fromHotelDayKey)
        assertEquals("2026-10-05", range.toHotelDayKey)
    }

    private fun time(day: Int, hour: Int, minute: Int, second: Int): Long = Calendar.getInstance().apply {
        clear()
        set(2026, Calendar.OCTOBER, day, hour, minute, second)
    }.timeInMillis
}
