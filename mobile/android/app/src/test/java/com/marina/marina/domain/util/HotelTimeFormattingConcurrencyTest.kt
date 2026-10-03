package com.marina.marina.domain.util

import java.util.Calendar
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Test

class HotelTimeFormattingConcurrencyTest {
    @Test fun backgroundRowFormattingAndUiFormattingKeepIdenticalDates() {
        val instants = (1..24).map { day ->
            Calendar.getInstance().apply {
                set(2026, Calendar.SEPTEMBER, day, if (day % 2 == 0) 13 else 15, 30, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
        }
        fun formats(time: Long) = listOf(
            HotelTimeEngine.hotelDayKey(time), HotelTimeEngine.formatDisplay(time),
            HotelTimeEngine.formatDisplayDateOnly(time), HotelTimeEngine.formatIso(time)
        )
        val expected = instants.associateWith(::formats)
        val workers = Executors.newFixedThreadPool(4)
        try {
            val futures = workers.invokeAll((0 until 8).map { worker -> Callable {
                repeat(100) { iteration ->
                    val time = instants[(worker + iteration) % instants.size]
                    assertEquals(expected.getValue(time), formats(time))
                }
            } })
            futures.forEach { it.get(10, TimeUnit.SECONDS) }
        } finally {
            workers.shutdownNow()
        }
    }
}
