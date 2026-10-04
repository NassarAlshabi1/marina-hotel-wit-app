package com.marina.marina.presentation.reports

import com.marina.marina.domain.util.HotelTimeEngine
import java.util.Calendar

/**
 * Shared report date-range filter — 1:1 port of the Flutter
 * `widgets/report_date_filter.dart`:
 * - Presets: اليوم الفندقي / الأسبوع / الشهر / السنة
 * - Custom pickers where "من" snaps to 14:01 and "إلى" snaps to 14:00:59
 * - The Dart "+1 second" rule: `fromHotelDay = hotelDayKey(from + 1s)`
 *   (without it the preset range resolves to the previous day).
 */
data class ReportDateRange(val from: Long, val to: Long) {
    /** Dart +1s rule (payments/expenses/income/salary screens). */
    val fromHotelDayKey: String get() = HotelTimeEngine.hotelDayKey(from + 1000L)

    /** `toHotelDay = hotelDayKey(to)` — 14:00:59.999 stays on the same day. */
    val toHotelDayKey: String get() = HotelTimeEngine.hotelDayKey(to)

    val isCurrentHotelDay: Boolean
        get() = fromHotelDayKey == HotelTimeEngine.currentHotelDayKey()

    val label: String
        get() = "النطاق: ${fromHotelDayKey} 14:01 - ${toHotelDayKey} 14:00"

    companion object {
        /** Default on every report screen = the current hotel day. */
        fun defaultHotelDay(): ReportDateRange {
            val now = System.currentTimeMillis()
            return ReportDateRange(HotelTimeEngine.hotelDayStart(now), HotelTimeEngine.hotelDayEnd(now) - 1)
        }

        /** Dart `computeQuickFilterRange` (l.54-129). */
        fun quick(type: String): ReportDateRange {
            val now = Calendar.getInstance()
            return when (type) {
                "week" -> {
                    val weekStart = Calendar.getInstance().apply {
                        timeInMillis = now.timeInMillis
                        add(Calendar.DAY_OF_YEAR, -(get(Calendar.DAY_OF_WEEK) - 1))
                        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                    }
                    val hotelWeekStart = HotelTimeEngine.hotelDayStart(weekStart.timeInMillis)
                    val hotelTodayEnd = HotelTimeEngine.hotelDayEnd(now.timeInMillis) - 1
                    ReportDateRange(hotelWeekStart, hotelTodayEnd)
                }
                "month" -> {
                    val monthStart = Calendar.getInstance().apply {
                        set(Calendar.DAY_OF_MONTH, 1)
                        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                    }
                    val hotelMonthStart = HotelTimeEngine.hotelDayStart(monthStart.timeInMillis)
                    ReportDateRange(hotelMonthStart, HotelTimeEngine.hotelDayEnd(now.timeInMillis) - 1)
                }
                "year" -> {
                    val yearStart = Calendar.getInstance().apply {
                        set(Calendar.MONTH, Calendar.JANUARY)
                        set(Calendar.DAY_OF_MONTH, 1)
                        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                    }
                    ReportDateRange(HotelTimeEngine.hotelDayStart(yearStart.timeInMillis), HotelTimeEngine.hotelDayEnd(now.timeInMillis) - 1)
                }
                else -> defaultHotelDay()
            }
        }
    }
}
