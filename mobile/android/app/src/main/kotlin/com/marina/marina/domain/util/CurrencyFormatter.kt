package com.marina.marina.domain.util

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale

/**
 * Currency rules ported 1:1 from the Flutter app's
 * `lib/utils/currency_formatter.dart` (Yemeni Rial, integer-only money).
 *
 * Contract:
 * - Format `#,##0` with `en_US` grouping — **no decimals ever**.
 * - Truncation, not rounding: a positive amount floors, a negative amount
 *   ceils ("never add to a guest's bill via rounding").
 * - Parsing accepts Arabic-Indic / Persian digits and Arabic thousands
 *   separators, then truncates any fraction (`1000.5 -> 1000`).
 */
object CurrencyFormatter {

    private val format: DecimalFormat = DecimalFormat("#,##0", DecimalFormatSymbols(Locale.US)).apply {
        isDecimalSeparatorAlwaysShown = false
    }

    /** Formats an amount with thousands commas, truncating toward zero. */
    fun formatAmount(amount: Double): String = format.format(truncate(amount))

    /**
     * Truncates toward zero (Dart contract: floor for >= 0, ceil for < 0) so
     * rounding can never increase a guest's bill.
     */
    fun truncate(amount: Double): Double = if (amount >= 0) kotlin.math.floor(amount) else kotlin.math.ceil(amount)

    private val arabicDigits = mapOf(
        '٠' to '0', '١' to '1', '٢' to '2', '٣' to '3', '٤' to '4',
        '٥' to '5', '٦' to '6', '٧' to '7', '٨' to '8', '٩' to '9',
        '۰' to '0', '۱' to '1', '۲' to '2', '۳' to '3', '۴' to '4',
        '۵' to '5', '۶' to '6', '۷' to '7', '۸' to '8', '۹' to '9'
    )

    private val arabicSeparators = charArrayOf('٬', '،', ',')

    /**
     * Parses a user-typed amount: maps Arabic digits to ASCII, strips Arabic
     * thousands separators, parses the number and truncates any fraction.
     * Returns `null` when the text is empty or not a valid number.
     */
    fun parseAmount(raw: String): Double? {
        val sb = StringBuilder()
        for (ch in raw.trim()) {
            val mapped = arabicDigits[ch]
            when {
                mapped != null -> sb.append(mapped)
                ch in arabicSeparators -> Unit // strip thousands separators
                ch == '.' || ch == '٫' -> sb.append('.')
                ch.isDigit() -> sb.append(ch)
                ch == '-' -> sb.append(ch)
                else -> Unit // drop anything else (spaces, currency labels…)
            }
        }
        val cleaned = sb.toString()
        if (cleaned.isEmpty() || cleaned == "-" || cleaned == ".") return null
        val value = cleaned.toDoubleOrNull() ?: return null
        if (value.isNaN() || value.isInfinite()) return null
        return truncate(value)
    }
}
