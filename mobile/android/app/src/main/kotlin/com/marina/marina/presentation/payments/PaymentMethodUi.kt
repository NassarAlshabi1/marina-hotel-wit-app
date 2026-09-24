package com.marina.marina.presentation.payments

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Money
import androidx.compose.material.icons.filled.Payment
import androidx.compose.material.icons.filled.ReceiptLong
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.runtime.Composable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarData
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * أدوات مشتركة لشاشات المدفوعات — نظير `PaymentMethod` من
 * models/payment_models.dart (displayName/icon/color) ودوال الألوان
 * المحلية `_getPaymentMethodColor` / `_getPaymentMethodIcon` في
 * payments_main_screen.dart و payment_history_screen.dart.
 */

/** Dart `PaymentMethod` (payment_models.dart l.13-19): label/icon/color بالضبط. */
enum class PayMethodUi(
    val db: String,
    val label: String,
    val icon: ImageVector,
    val color: Color
) {
    CASH("نقدي", "نقدي", Icons.Filled.Money, Color(0xFF4CAF50)),
    CARD("بطاقة", "بطاقة ائتمانية", Icons.Filled.CreditCard, Color(0xFF2196F3)),
    TRANSFER("تحويل", "تحويل بنكي", Icons.Filled.AccountBalance, Color(0xFF9C27B0)),
    CHECK("شيك", "شيك", Icons.Filled.ReceiptLong, Color(0xFFFF9800)),
    INSTALLMENT("تقسيط", "تقسيط", Icons.Filled.Schedule, Color(0xFF3F51B5));

    companion object {
        /** Dart `_mapDbMethodToUi` (booking_payment_screen.dart l.94-111). */
        fun fromDb(m: String): PayMethodUi = when (m) {
            "نقدي", "نقداً" -> CASH
            "بطاقة", "بطاقة ائتمان" -> CARD
            "تحويل", "تحويل بنكي" -> TRANSFER
            "شيك" -> CHECK
            "تقسيط" -> INSTALLMENT
            else -> CASH
        }
    }
}

/** Dart `_getPaymentMethodColor` (payments_main_screen.dart l.639-653). */
fun dbMethodColor(method: String): Color = when (method) {
    "نقدي" -> Color(0xFF4CAF50)
    "بطاقة" -> Color(0xFF2196F3)
    "تحويل" -> Color(0xFFFF9800)
    "شيك" -> Color(0xFF9C27B0)
    else -> Color(0xFF9E9E9E)
}

/** Dart `_getPaymentMethodIcon` (payments_main_screen.dart l.655-669). */
fun dbMethodIcon(method: String): ImageVector = when (method) {
    "نقدي" -> Icons.Filled.Money
    "بطاقة" -> Icons.Filled.CreditCard
    "تحويل" -> Icons.Filled.AccountBalance
    "شيك" -> Icons.Filled.ReceiptLong
    else -> Icons.Filled.Payment
}

/** Dart `_getRevenueTypeLabel` (payment_history_screen.dart l.634-646). */
fun revenueTypeLabel(type: String?): String = when (type) {
    "room" -> "إيراد غرفة"
    "service" -> "خدمات إضافية"
    "deposit" -> "عربون"
    "other" -> "أخرى"
    else -> type ?: ""
}

/** لون سناك-بار الرسالة — نظير backgroundColor في Dart SnackBar. */
enum class MsgTone { INFO, SUCCESS, ERROR, ERROR_DARK, WARN }

/** Dart snackbar colors: green / red / red.shade900 / orange / default theme. */
@Composable
fun PaymentSnackbarHost(hostState: SnackbarHostState, tone: MsgTone) {
    SnackbarHost(hostState) { data: SnackbarData ->
        val container = when (tone) {
            MsgTone.SUCCESS -> Color(0xFF4CAF50)
            MsgTone.ERROR -> Color(0xFFF44336)
            MsgTone.ERROR_DARK -> Color(0xFFB71C1C)
            MsgTone.WARN -> Color(0xFFFF9800)
            MsgTone.INFO -> MaterialTheme.colorScheme.inverseSurface
        }
        Snackbar(
            snackbarData = data,
            containerColor = container,
            contentColor = Color.White,
            actionColor = Color.White
        )
    }
}
