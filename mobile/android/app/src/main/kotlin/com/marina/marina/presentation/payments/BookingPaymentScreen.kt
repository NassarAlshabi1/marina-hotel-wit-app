package com.marina.marina.presentation.payments

import androidx.compose.foundation.background
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun BookingPaymentScreen(
    onBack: () -> Unit = {},
    viewModel: BookingPaymentViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showAddPayment by remember { mutableStateOf(false) }
    var showCheckoutConfirm by remember { mutableStateOf(false) }
    var voidingPayment by remember { mutableStateOf<Payment?>(null) }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.consumeMessage()
        }
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("حجز غرفة ${state.booking?.roomNumber ?: ""}", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            floatingActionButton = {
                if (state.booking != null && StatusUtils.isBookingActive(state.booking!!.status)) {
                    FloatingActionButton(
                        onClick = { showAddPayment = true },
                        containerColor = AppColors.SuccessColor,
                        contentColor = Color.White
                    ) {
                        Text("+", fontSize = 24.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        ) { padding ->
            when {
                state.isLoading -> Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center
                ) { CircularProgressIndicator() }

                state.booking == null -> Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center
                ) { Text("الحجز غير موجود", style = AppTypography.bodyLarge, color = AppColors.TextSecondary) }

                else -> LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    val booking = state.booking!!

                    item { GuestSummaryCard(state) }

                    item { FinancialSummaryCard(state) }

                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            if (StatusUtils.isBookingActive(booking.status)) {
                                Button(
                                    onClick = { showCheckoutConfirm = true },
                                    modifier = Modifier.weight(1f).height(52.dp),
                                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryColor),
                                    shape = RoundedCornerShape(12.dp)
                                ) {
                                    Text("إتمام المغادرة", color = Color.White, fontWeight = FontWeight.Bold)
                                }
                            } else {
                                Card(
                                    modifier = Modifier.weight(1f),
                                    colors = CardDefaults.cardColors(containerColor = AppColors.AccentSoft),
                                    shape = RoundedCornerShape(12.dp)
                                ) {
                                    Box(modifier = Modifier.padding(16.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
                                        Text(
                                            "الحجز ${booking.status}",
                                            style = AppTypography.titleMedium,
                                            color = AppColors.WarningColor,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }
                            }
                        }
                    }

                    item {
                        Text(
                            "سجل المدفوعات (${state.payments.size})",
                            style = AppTypography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = AppColors.TextPrimary
                        )
                    }

                    if (state.payments.isEmpty()) {
                        item {
                            Card(
                                colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                                shape = RoundedCornerShape(12.dp),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Box(modifier = Modifier.padding(24.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
                                    Text("لا توجد مدفوعات بعد", style = AppTypography.bodyMedium, color = AppColors.TextSecondary)
                                }
                            }
                        }
                    } else {
                        items(state.payments, key = { it.id }) { payment ->
                            PaymentRow(payment = payment, onVoid = { voidingPayment = payment })
                        }
                    }
                }
            }
        }
    }

    if (showAddPayment) {
        AddPaymentDialog(
            remaining = state.remaining,
            onDismiss = { showAddPayment = false },
            onConfirm = { amount, method, revenueType, notes ->
                viewModel.addPayment(amount, method, revenueType, notes)
                showAddPayment = false
            }
        )
    }

    if (showCheckoutConfirm) {
        AlertDialog(
            onDismissRequest = { showCheckoutConfirm = false },
            title = { Text("تأكيد إتمام المغادرة") },
            text = {
                if (state.remaining > 0) {
                    Text("⚠ المتبقي ${state.remaining.toInt()} ريال سيُخصم أو يُسجل كدين على الحساب.\nهل تريد المتابعة؟")
                } else {
                    Text("سيتم إغلاق الحجز وتحرير الغرفة. هل تريد المتابعة؟")
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.completeCheckout()
                    showCheckoutConfirm = false
                }) { Text("متابعة", color = AppColors.PrimaryColor) }
            },
            dismissButton = {
                TextButton(onClick = { showCheckoutConfirm = false }) { Text("إلغاء") }
            }
        )
    }

    voidingPayment?.let { payment ->
        var reason by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { voidingPayment = null },
            title = { Text("إلغاء الدفعة") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("دفعة بمبلغ ${payment.amount.toInt()} ريال")
                    OutlinedTextField(
                        value = reason,
                        onValueChange = { reason = it },
                        label = { Text("سبب الإلغاء") },
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.voidPayment(payment, reason.ifBlank { "بدون سبب" })
                    voidingPayment = null
                }) { Text("إلغاء الدفعة", color = AppColors.DangerColor) }
            },
            dismissButton = {
                TextButton(onClick = { voidingPayment = null }) { Text("تراجع") }
            }
        )
    }
}

@Composable
private fun GuestSummaryCard(state: BookingPaymentUiState) {
    val booking = state.booking ?: return
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(booking.guestName.ifBlank { "ضيف" }, style = AppTypography.titleLarge, fontWeight = FontWeight.Bold)
                Text("غرفة ${booking.roomNumber}", style = AppTypography.titleMedium, color = AppColors.PrimaryColor)
            }
            if (booking.guestPhone.isNotBlank()) {
                Text("📱 ${booking.guestPhone}", style = AppTypography.bodyMedium, color = AppColors.TextSecondary)
            }
            if (booking.guestIdNumber.isNotBlank()) {
                Text("🪪 ${booking.guestIdType}: ${booking.guestIdNumber} (${booking.guestNationality})", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
            }

            HorizontalDivider(color = AppColors.DividerColor)

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                SummaryCell(
                    "تاريخ الدخول",
                    HotelTimeEngine.parseDate(booking.checkinDate)?.let { HotelTimeEngine.formatDisplayDateOnly(it) } ?: "—"
                )
                SummaryCell("الليالي", "${state.nights}")
                SummaryCell(
                    "المغادرة",
                    HotelTimeEngine.parseDate(booking.actualCheckout ?: booking.checkoutDate)?.let {
                        HotelTimeEngine.formatDisplayDateOnly(it)
                    } ?: "—"
                )
                SummaryCell("السعر/ليلة", "${state.roomPrice.toInt()}")
            }

            if (!booking.notes.isNullOrBlank()) {
                Text("📝 ${booking.notes}", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
            }
        }
    }
}

@Composable
private fun FinancialSummaryCard(state: BookingPaymentUiState) {
    Card(
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.Transparent)
    ) {
        Box(
            modifier = Modifier
                .background(
                    Brush.horizontalGradient(
                        listOf(AppColors.PrimaryColor, AppColors.PrimaryDark)
                    ),
                    RoundedCornerShape(12.dp)
                )
                .padding(16.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "الملخص المالي",
                    style = AppTypography.titleMedium,
                    color = Color.White,
                    fontWeight = FontWeight.Bold
                )
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    FinancialCell("إجمالي الاستحقاق", "${state.totalDue.toInt()}", Color.White)
                    FinancialCell("المدفوع", "${state.totalPaid.toInt()}", Color(0xFF9EE6C0))
                    FinancialCell(
                        "المتبقي",
                        "${state.remaining.toInt()}",
                        if (state.remaining > 0) Color(0xFFFFB4A9) else Color(0xFF9EE6C0)
                    )
                }
                if (state.totalDue > 0) {
                    LinearProgressIndicator(
                        progress = { (state.totalPaid / state.totalDue).toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth().height(8.dp),
                        color = Color(0xFF9EE6C0),
                        trackColor = Color.White.copy(alpha = 0.25f)
                    )
                    Text(
                        if (state.isFullyPaid) "✓ مسددة بالكامل" else "متبقي ${state.remaining.toInt()} ريال",
                        style = AppTypography.bodySmall,
                        color = Color.White
                    )
                }
            }
        }
    }
}

@Composable
private fun PaymentRow(payment: Payment, onVoid: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(12.dp).fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    "${payment.amount.toInt()} ريال",
                    style = AppTypography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.SuccessColor
                )
                Text(
                    "${payment.paymentMethod} • ${payment.revenueType}",
                    style = AppTypography.bodySmall,
                    color = AppColors.TextSecondary
                )
                payment.hotelDayKey?.let {
                    Text("اليوم الفندقي: $it", style = AppTypography.labelSmall, color = AppColors.TextSecondary)
                }
                payment.notes?.let { if (it.isNotBlank()) Text(it, style = AppTypography.labelSmall, color = AppColors.TextSecondary) }
            }
            TextButton(onClick = onVoid) {
                Text("إلغاء", color = AppColors.DangerColor, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun AddPaymentDialog(
    remaining: Double,
    onDismiss: () -> Unit,
    onConfirm: (Double, String, String, String?) -> Unit
) {
    var amount by remember { mutableStateOf("") }
    var method by remember { mutableStateOf("نقدي") }
    var revenueType by remember { mutableStateOf("room") }
    var notes by remember { mutableStateOf("") }

    val methods = listOf("نقدي", "تحويل", "بطاقة", "شيك", "تقسيط")
    val revenueTypes = listOf("room" to "إقامة", "service" to "خدمات", "deposit" to "عربون", "other" to "أخرى")

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("تسجيل دفعة", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (remaining > 0) {
                    // Quick-pay buttons: 25% / 50% / 75% / 100% of remaining (Flutter parity).
                    Text("المتبقي: ${remaining.toInt()} ريال", style = AppTypography.bodyMedium, color = AppColors.TextSecondary)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(0.25, 0.5, 0.75, 1.0).forEach { fraction ->
                            OutlinedButton(
                                onClick = { amount = (remaining * fraction).toInt().toString() },
                                modifier = Modifier.weight(1f)
                            ) {
                                Text("${(fraction * 100).toInt()}%", fontSize = 12.sp)
                            }
                        }
                    }
                }
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { ch -> ch.isDigit() } },
                    label = { Text("المبلغ (ريال)") },
                    singleLine = true
                )
                Text("طريقة الدفع", style = AppTypography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    methods.take(3).forEach { m ->
                        FilterChip(selected = method == m, onClick = { method = m }, label = { Text(m, fontSize = 12.sp) })
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    methods.drop(3).forEach { m ->
                        FilterChip(selected = method == m, onClick = { method = m }, label = { Text(m, fontSize = 12.sp) })
                    }
                }
                Text("نوع الإيراد", style = AppTypography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    revenueTypes.forEach { (key, label) ->
                        FilterChip(selected = revenueType == key, onClick = { revenueType = key }, label = { Text(label, fontSize = 12.sp) })
                    }
                }
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("ملاحظات (اختياري)") },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val value = amount.toDoubleOrNull() ?: return@TextButton
                    onConfirm(value, method, revenueType, notes.ifBlank { null })
                }
            ) { Text("تأكيد الدفعة", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

@Composable
private fun SummaryCell(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = AppTypography.titleSmall, fontWeight = FontWeight.SemiBold, color = AppColors.TextPrimary)
        Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary)
    }
}

@Composable
private fun FinancialCell(label: String, value: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = AppTypography.headlineSmall, fontWeight = FontWeight.Bold, color = color, fontSize = 20.sp)
        Text(label, style = AppTypography.labelSmall, color = Color.White.copy(alpha = 0.8f))
    }
}
