package com.marina.marina.data.backup

import java.util.Locale

/** Stable numeric formatting with Arabic unit labels, independent of device locale. */
object FileSizeFormatter {
    private const val BINARY_UNIT = 1024.0
    private const val BITS_PER_UNIT = 10
    private val suffixes = arrayOf("بايت", "كيلوبايت", "ميجابايت", "جيجابايت", "تيرابايت")

    fun formatBytes(bytes: Long, decimals: Int = 2): String {
        if (bytes <= 0) return "0 بايت"
        val exponent = ((Long.SIZE_BITS - 1 - java.lang.Long.numberOfLeadingZeros(bytes)) / BITS_PER_UNIT)
            .coerceAtMost(suffixes.lastIndex)
        return String.format(
            Locale.US, "%.${decimals}f ${suffixes[exponent]}",
            bytes / Math.pow(BINARY_UNIT, exponent.toDouble())
        )
    }
}
