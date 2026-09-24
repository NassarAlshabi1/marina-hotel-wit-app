package com.marina.marina.presentation.payments

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import java.util.Calendar

/**
 * تاريخ المدفوعات — 1:1 port of `payment_history_screen.dart`:
 * filter dialog (revenue type / method / from-to dates), active filter
 * chips, total banner, payment tiles with details dialog.
 */
@Composable
fun PaymentHistoryScreen(
    bookingId: Long? = null,
    showBack: Boolean = true,
    onBack: () -> Unit = {},
    viewModel: PaymentHistoryViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showFilterDialog by remember { mutableStateOf(false) }
    var detailsPayment by remember { mutableStateOf<Payment?>(null) }

    LaunchedEffect(bookingId) { viewModel.filterBooking(bookingId) }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("تاريخ المدفوعات", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        if (showBack) {
                            TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                        }
                    },
                    actions = {
                        TextButton(onClick = { showFilterDialog = true }) { Text("فلترة") }
                        if (state.hasActiveFilters) {
                            TextButton(onClick = { viewModel.clearFilters() }) { Text("مسح") }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            }
        ) { padding ->
            Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                // Active filter chips (Dart l.366-397).
                if (state.hasActiveFilters) {
                    Row(
                        modifier = Modifier
                            .padding(horizontal = 16.dp, vertical = 4.dp)
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        state.selectedRevenueType?.let {
                            FilterChip(selected = true, onClick = { viewModel.setRevenueType(null) },
                                label = { Text("النوع: ${revenueLabel(it)}", fontSize = 10.sp) })
                        }
                        state.selectedPaymentMethod?.let {
                            FilterChip(selected = true, onClick = { viewModel.setMethod(null) },
                                label = { Text("الطريقة: $it", fontSize = 10.sp) })
                        }
                        state.fromDate?.let {
                            FilterChip(selected = true, onClick = { viewModel.setDateRange(null, state.toDate) },
                                label = { Text("من: ${HotelTimeEngine.formatDisplayDateOnly(it)}", fontSize = 10.sp) })
                        }
                        state.toDate?.let {
                            FilterChip(selected = true, onClick = { viewModel.setDateRange(state.fromDate, null) },
                                label = { Text("إلى: ${HotelTimeEngine.formatDisplayDateOnly(it)}", fontSize = 10.sp) })
                        }
                    }
                }

                LazyColumn(
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    item {
                        // Total banner (Dart l.180-218) — green gradient card.
                        Card(
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.cardColors(containerColor = Color.Transparent),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Box(
                                modifier = Modifier
                                    .background(
                                        Brush.horizontalGradient(
                                            listOf(Color(0xFF2E7D5B), Color(0xFF1B5E40))
                                        ),
                                        RoundedCornerShape(12.dp)
                                    )
                                    .padding(16.dp)
                                    .fillMaxWidth()
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Column {
                                        Text("إجمالي المدفوعات", color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp)
                                        Text(
                                            "${CurrencyFormatter.formatAmount(state.totalAmount)} ريال",
                                            color = Color.White, fontWeight = FontWeight.Bold, fontSize = 18.sp
                                        )
                                    }
                                    Text(
                                        "عدد المدفوعات: ${state.visible.size}",
                                        color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp,
                                        modifier = Modifier.align(Alignment.CenterVertically)
                                    )
                                }
                            }
                        }
                    }

                    if (!state.isLoading && state.visible.isEmpty()) {
                        item {
                            EmptyHistoryCard(
                                if (state.hasActiveFilters) "لا توجد مدفوعات تطابق الفلاتر المحددة"
                                else "لا توجد مدفوعات مسجلة"
                            )
                        }
                    } else {
                        items(state.visible, key = { it.id }) { payment ->
                            HistoryPaymentRow(payment) { detailsPayment = payment }
                        }
                    }
                }
            }
        }
    }

    if (showFilterDialog) {
        FilterDialog(
            state = state,
            onDismiss = { showFilterDialog = false },
            onApply = { revenue, method, from, to ->
                viewModel.setRevenueType(revenue)
                viewModel.setMethod(method)
                viewModel.setDateRange(from, to)
                showFilterDialog = false
            }
        )
    }

    detailsPayment?.let { payment ->
        AlertDialog(
            onDismissRequest = { detailsPayment = null },
            title = { Text("تفاصيل الدفعة") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    HistoryDetailRow("المبلغ", "${CurrencyFormatter.formatAmount(payment.amount)} ريال")
                    HistoryDetailRow("طريقة الدفع", payment.paymentMethod)
                    HistoryDetailRow("نوع الإيراد", revenueLabel(payment.revenueType))
                    HistoryDetailRow("التاريخ", payment.paymentDate.take(16).replace("T", " "))
                    payment.roomNumber?.let { HistoryDetailRow("رقم الغرفة", it) }
                    payment.referenceNumber?.let { HistoryDetailRow("رقم المرجع", it) }
                    payment.notes?.let { if (it.isNotBlank()) HistoryDetailRow("ملاحظات", it) }
                    if (payment.isVoided) {
                        HistoryDetailRow("الحالة", "ملغاة — ${payment.voidReason ?: ""}", AppColors.DangerColor)
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { detailsPayment = null }) { Text("إغلاق") }
            }
        )
    }
}

@Composable
private fun HistoryPaymentRow(payment: Payment, onTap: () -> Unit) {
    val (color, icon) = methodVisual(payment.paymentMethod)
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        shape = RoundedCornerShape(10.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(12.dp).fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier.size(42.dp).background(color.copy(alpha = 0.15f), RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center
            ) { Text(icon, fontSize = 18.sp) }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "${CurrencyFormatter.formatAmount(payment.amount)} ريال",
                    fontWeight = FontWeight.Bold, fontSize = 15.sp,
                    color = if (payment.isVoided) AppColors.TextSecondary else AppColors.TextPrimary
                )
                Text("${payment.paymentMethod} • ${revenueLabel(payment.revenueType)}", fontSize = 10.sp, color = AppColors.TextSecondary)
                Text(payment.paymentDate.take(16).replace("T", " "), fontSize = 10.sp, color = AppColors.TextSecondary)
                payment.notes?.let {
                    if (it.isNotBlank()) Text(it, fontSize = 10.sp, color = AppColors.TextSecondary, maxLines = 1)
                }
                if (payment.isVoided) {
                    Text(
                        "ملغاة${payment.voidReason?.let { " — $it" } ?: ""}",
                        fontSize = 9.sp, color = AppColors.DangerColor
                    )
                }
            }
            payment.roomNumber?.let { room ->
                Text(
                    room, fontSize = 12.sp, color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold,
                    modifier = Modifier.background(AppColors.PrimaryLight, RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 3.dp)
                )
            }
        }
    }
}

@Composable
private fun FilterDialog(
    state: PaymentHistoryUiState,
    onDismiss: () -> Unit,
    onApply: (String?, String?, Long?, Long?) -> Unit
) {
    var revenue by remember { mutableStateOf(state.selectedRevenueType) }
    var method by remember { mutableStateOf(state.selectedPaymentMethod) }
    var from by remember { mutableStateOf(state.fromDate) }
    var to by remember { mutableStateOf(state.toDate) }
    val context = androidx.compose.ui.platform.LocalContext.current

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("فلترة المدفوعات") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text("نوع الإيراد", style = AppTypography.labelLarge)
                listOf(null to "جميع الأنواع", "room" to "إيراد غرفة", "service" to "خدمات إضافية", "deposit" to "عربون", "other" to "أخرى")
                    .forEach { (key, label) ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            RadioButton(selected = revenue == key, onClick = { revenue = key })
                            Text(label, fontSize = 13.sp)
                        }
                    }
                HorizontalDivider()
                Text("طريقة الدفع", style = AppTypography.labelLarge)
                listOf(null to "جميع الطرق", "نقدي" to "نقدي", "تحويل" to "تحويل")
                    .forEach { (key, label) ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            RadioButton(selected = method == key, onClick = { method = key })
                            Text(label, fontSize = 13.sp)
                        }
                    }
                HorizontalDivider()
                Text("الفترة", style = AppTypography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = {
                            val cal = Calendar.getInstance()
                            cal.timeInMillis = from ?: System.currentTimeMillis()
                            android.app.DatePickerDialog(
                                context, { _, y, m, d ->
                                    cal.set(y, m, d, 0, 0, 0)
                                    cal.set(Calendar.MILLISECOND, 0)
                                    from = cal.timeInMillis
                                }, cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
                            ).show()
                        },
                        modifier = Modifier.weight(1f)
                    ) { Text("من تاريخ", fontSize = 11.sp) }
                    OutlinedButton(
                        onClick = {
                            val cal = Calendar.getInstance()
                            cal.timeInMillis = to ?: System.currentTimeMillis()
                            android.app.DatePickerDialog(
                                context, { _, y, m, d ->
                                    cal.set(y, m, d, 23, 59, 59)
                                    cal.set(Calendar.MILLISECOND, 999)
                                    to = cal.timeInMillis
                                }, cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
                            ).show()
                        },
                        modifier = Modifier.weight(1f)
                    ) { Text("إلى تاريخ", fontSize = 11.sp) }
                }
                from?.let { Text("من: ${HotelTimeEngine.formatDisplayDateOnly(it)}", fontSize = 11.sp, color = AppColors.TextSecondary) }
                to?.let { Text("إلى: ${HotelTimeEngine.formatDisplayDateOnly(it)}", fontSize = 11.sp, color = AppColors.TextSecondary) }
            }
        },
        confirmButton = {
            TextButton(onClick = { onApply(revenue, method, from, to) }) {
                Text("تطبيق الفلاتر", color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

private fun revenueLabel(revenueType: String): String = when (revenueType.lowercase()) {
    "room" -> "إيراد غرفة"
    "service" -> "خدمات إضافية"
    "deposit" -> "عربون"
    else -> "أخرى"
}

private fun methodVisual(method: String): Pair<Color, String> = when {
    method.contains("نقدي") -> Color(0xFF2E7D5B) to "💵"
    method.contains("بطاقة") -> Color(0xFF1976D2) to "💳"
    method.contains("تحويل") -> Color(0xFFF57C00) to "🏦"
    method.contains("شيك") -> Color(0xFF7B1FA2) to "🧾"
    else -> Color(0xFF6C6F8F) to "💳"
}

@Composable
private fun HistoryDetailRow(label: String, value: String, valueColor: Color = AppColors.TextPrimary) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = AppTypography.bodySmall, color = AppColors.TextSecondary)
        Text(value, style = AppTypography.bodySmall, color = valueColor, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun EmptyHistoryCard(message: String) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(24.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text("لا توجد مدفوعات", style = AppTypography.titleMedium, color = AppColors.TextPrimary)
            Text(message, style = AppTypography.bodySmall, color = AppColors.TextSecondary, textAlign = TextAlign.Center)
        }
    }
}
