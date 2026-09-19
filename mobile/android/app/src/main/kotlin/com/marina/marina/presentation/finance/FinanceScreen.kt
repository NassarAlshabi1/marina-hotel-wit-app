package com.marina.marina.presentation.finance

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
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
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun FinanceScreen(
    onBookingClick: (Long) -> Unit = {},
    viewModel: FinanceViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showQuickPayment by remember { mutableStateOf(false) }

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
                    title = { Text("الصندوق والمالية", style = AppTypography.titleLarge) },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            floatingActionButton = {
                FloatingActionButton(
                    onClick = { showQuickPayment = true },
                    containerColor = AppColors.SuccessColor,
                    contentColor = Color.White
                ) {
                    Text("+", fontSize = 24.sp, fontWeight = FontWeight.Bold)
                }
            }
        ) { padding ->
            when {
                state.isLoading -> Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center
                ) { CircularProgressIndicator() }

                else -> LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    // ---- Hotel day card ----------------------------------------
                    item {
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier.padding(14.dp).fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column {
                                    Text("اليوم الفندقي", style = AppTypography.labelMedium, color = AppColors.TextSecondary)
                                    Text(
                                        state.hotelDayKey,
                                        style = AppTypography.titleLarge,
                                        fontWeight = FontWeight.Bold,
                                        color = AppColors.PrimaryColor
                                    )
                                }
                                Text(
                                    if (state.isAfterCutoff) "بعد الحد (14:01)" else "قبل الحد (14:01)",
                                    style = AppTypography.bodySmall,
                                    color = if (state.isAfterCutoff) AppColors.SuccessColor else AppColors.WarningColor
                                )
                            }
                        }
                    }

                    // ---- Cash status card ---------------------------------------
                    item {
                        Card(
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.cardColors(containerColor = Color.Transparent),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Box(
                                modifier = Modifier
                                    .background(
                                        Brush.horizontalGradient(
                                            if (state.isDeficit) listOf(AppColors.DangerColor, Color(0xFFB93338))
                                            else listOf(AppColors.PrimaryColor, AppColors.PrimaryDark)
                                        ),
                                        RoundedCornerShape(12.dp)
                                    )
                                    .padding(18.dp)
                                    .fillMaxWidth()
                            ) {
                                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text(
                                        if (state.isDeficit) "حالة الصندوق — عجز" else "حالة الصندوق — رصيد",
                                        style = AppTypography.titleSmall,
                                        color = Color.White
                                    )
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                        CashCell("الإيرادات", "${state.todayIncome.toInt()}", Color(0xFF9EE6C0))
                                        CashCell("المصروفات", "${state.todayExpenses.toInt()}", Color(0xFFFFB4A9))
                                        CashCell(
                                            if (state.isDeficit) "العجز" else "الرصيد",
                                            "${state.balance.toInt()}",
                                            if (state.isDeficit) Color(0xFFFFD7D2) else Color.White
                                        )
                                    }
                                    Text(
                                        "${state.todayPaymentsCount} دفعة اليوم",
                                        style = AppTypography.labelSmall,
                                        color = Color.White.copy(alpha = 0.85f)
                                    )
                                }
                            }
                        }
                    }

                    // ---- Today's payments grouped by room ------------------------
                    if (state.roomGroups.isNotEmpty() || state.generalPayments.isNotEmpty()) {
                        item {
                            Text(
                                "مدفوعات اليوم حسب الغرفة",
                                style = AppTypography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = AppColors.TextPrimary
                            )
                        }
                        items(state.roomGroups) { group ->
                            RoomGroupCard(group)
                        }
                        if (state.generalPayments.isNotEmpty()) {
                            item {
                                Card(
                                    colors = CardDefaults.cardColors(containerColor = AppColors.AccentSoft),
                                    shape = RoundedCornerShape(10.dp),
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Row(
                                        modifier = Modifier.padding(12.dp).fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text("مدفوعات عامة (بدون غرفة)", style = AppTypography.bodyMedium, fontWeight = FontWeight.SemiBold)
                                        Text(
                                            "${state.generalPayments.sumOf { it.amount }.toInt()} ريال",
                                            style = AppTypography.titleSmall,
                                            fontWeight = FontWeight.Bold,
                                            color = AppColors.TextPrimary
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // ---- Active bookings quick-pay tiles --------------------------
                    if (state.activeBookings.isNotEmpty()) {
                        item {
                            Text(
                                "حجوزات نشطة (${state.activeBookings.size})",
                                style = AppTypography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = AppColors.TextPrimary
                            )
                        }
                        items(state.activeBookings, key = { it.id }) { booking ->
                            val remaining = state.roomRemaining[booking.roomNumber] ?: 0.0
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
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Box(
                                            modifier = Modifier
                                                .background(AppColors.PrimaryColor, RoundedCornerShape(8.dp))
                                                .size(40.dp),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Text(booking.roomNumber, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                        }
                                        Spacer(modifier = Modifier.width(10.dp))
                                        Column {
                                            Text(booking.guestName.ifBlank { "ضيف" }, style = AppTypography.titleSmall, fontWeight = FontWeight.Bold)
                                            Text(
                                                "المتبقي: ${remaining.toInt()} ريال",
                                                style = AppTypography.labelSmall,
                                                color = if (remaining > 0) AppColors.DangerColor else AppColors.SuccessColor
                                            )
                                        }
                                    }
                                    Button(
                                        onClick = { onBookingClick(booking.id) },
                                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.SuccessColor),
                                        shape = RoundedCornerShape(8.dp)
                                    ) {
                                        Text("دفع", color = Color.White, fontSize = 12.sp)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showQuickPayment) {
        QuickPaymentDialog(
            onDismiss = { showQuickPayment = false },
            onConfirm = { amount, method, notes ->
                viewModel.addQuickPayment(amount, method, notes)
                showQuickPayment = false
            }
        )
    }
}

@Composable
private fun RoomGroupCard(group: RoomPaymentGroup) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("غرفة ${group.roomNumber}", style = AppTypography.titleSmall, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
                Text(
                    "${group.total.toInt()} ريال",
                    style = AppTypography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.SuccessColor
                )
            }
            group.payments.forEach { payment ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        "• ${payment.paymentMethod}" + (payment.notes?.takeIf { it.isNotBlank() }?.let { " — $it" } ?: ""),
                        style = AppTypography.bodySmall,
                        color = AppColors.TextSecondary
                    )
                    Text("${payment.amount.toInt()}", style = AppTypography.bodySmall, color = AppColors.TextPrimary)
                }
            }
        }
    }
}

@Composable
private fun CashCell(label: String, value: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = AppTypography.titleLarge, fontWeight = FontWeight.Bold, color = color)
        Text(label, style = AppTypography.labelSmall, color = Color.White.copy(alpha = 0.85f))
    }
}

@Composable
private fun QuickPaymentDialog(
    onDismiss: () -> Unit,
    onConfirm: (Double, String, String?) -> Unit
) {
    var amount by remember { mutableStateOf("") }
    var method by remember { mutableStateOf("نقدي") }
    var notes by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("دفعة صندوق سريعة", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { ch -> ch.isDigit() } },
                    label = { Text("المبلغ (ريال)") },
                    singleLine = true
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("نقدي", "تحويل", "بطاقة").forEach { m ->
                        FilterChip(selected = method == m, onClick = { method = m }, label = { Text(m, fontSize = 12.sp) })
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
                    onConfirm(value, method, notes.ifBlank { null })
                }
            ) { Text("تسجيل", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}
