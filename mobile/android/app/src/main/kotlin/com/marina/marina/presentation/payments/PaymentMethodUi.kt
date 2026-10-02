package com.marina.marina.presentation.payments

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Money
import androidx.compose.material.icons.filled.Payment
import androidx.compose.material.icons.filled.ReceiptLong
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarData
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.marina.marina.ui.theme.AppColors

/**
 * أدوات مشتركة لشاشات المدفوعات — نظير `PaymentMethod` من
 * models/payment_models.dart (displayName/icon/color) ودوال الألوان
 * المحلية `_getPaymentMethodColor` / `_getPaymentMethodIcon` في
 * payments_main_screen.dart و payment_history_screen.dart.
 */

enum class PayMethodUi(
    val db: String,
    val label: String,
    val icon: ImageVector
) {
    CASH("نقدي", "نقدي", Icons.Filled.Money),
    CARD("بطاقة", "بطاقة ائتمانية", Icons.Filled.CreditCard),
    TRANSFER("تحويل", "تحويل بنكي", Icons.Filled.AccountBalance),
    CHECK("شيك", "شيك", Icons.Filled.ReceiptLong),
    INSTALLMENT("تقسيط", "تقسيط", Icons.Filled.Schedule);

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

/** Theme-aware tint for method labels/icons on surfaces. */
@Composable
fun PayMethodUi.colorForTheme(): Color = when (this) {
    PayMethodUi.CASH -> AppColors.SuccessColor
    PayMethodUi.CARD, PayMethodUi.INSTALLMENT -> AppColors.PrimaryColor
    PayMethodUi.TRANSFER -> AppColors.WarningColor
    PayMethodUi.CHECK -> AppColors.InfoColor
}

/** Strong, fixed fill colors keep white labels legible on selected method chips. */
fun PayMethodUi.actionColor(): Color = when (this) {
    PayMethodUi.CASH -> AppColors.SuccessActionColor
    PayMethodUi.TRANSFER -> AppColors.WarningActionColor
    PayMethodUi.CARD, PayMethodUi.CHECK, PayMethodUi.INSTALLMENT -> AppColors.PrimaryActionColor
}

/** Dart `_getPaymentMethodColor` (payments_main_screen.dart l.639-653). */
@Composable
fun dbMethodColor(method: String): Color = when (method) {
    "نقدي" -> AppColors.SuccessColor
    "بطاقة" -> AppColors.InfoColor
    "تحويل" -> AppColors.WarningColor
    "شيك" -> AppColors.InfoColor
    else -> AppColors.TextSecondary
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

/** Snackbar colors use strong action fills to keep white content accessible. */
@Composable
fun PaymentSnackbarHost(hostState: SnackbarHostState, tone: MsgTone) {
    SnackbarHost(hostState) { data: SnackbarData ->
        val container = when (tone) {
            MsgTone.SUCCESS -> AppColors.SuccessActionColor
            MsgTone.ERROR, MsgTone.ERROR_DARK -> AppColors.DangerActionColor
            MsgTone.WARN -> AppColors.WarningActionColor
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
