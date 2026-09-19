package com.marina.marina.presentation.dashboard

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Dashboard formatting utilities — kept free of Compose references so plain
 * JVM unit tests can verify them (same strings the Dart screen produced via
 * `NumberFormat('#,##0', 'en_US')` and `DateFormat('HH:mm')`).
 */
internal object DashboardFormatters {

    /** Thousands-separated integer currency — Dart `NumberFormat('#,##0')`. */
    fun currency(amount: Double): String =
        DecimalFormat("#,##0", DecimalFormatSymbols(Locale.US)).format(amount)

    /** "HH:mm" — the Dart `DateFormat('HH:mm')` shift-start label. */
    fun hourMinute(epochMillis: Long): String =
        SimpleDateFormat("HH:mm", Locale.US).format(Date(epochMillis))
}
