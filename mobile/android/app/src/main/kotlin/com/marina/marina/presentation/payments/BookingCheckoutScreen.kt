package com.marina.marina.presentation.payments

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

/**
 * دفع الحجز — 1:1 port of `booking_checkout_screen.dart`:
 * booking info card (with the "+N ليلة بعد 14:00" notice), payments section
 * with per-payment tiles, add-payment dialog (نقدي/تحويل + 4 revenue types),
 * and the hard-gated إتمام الحجز button.
 */
@Composable
fun BookingCheckoutScreen(
    onBack: () -> Unit = {},
    onCheckedOut: () -> Unit = {},
    viewModel: BookingCheckoutViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showAddPayment by remember { mutableStateOf(false) }
    var showCompleteConfirm by remember { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.consumeMessage()
        }
    }
    LaunchedEffect(state.checkedOut) { if (state.checkedOut) onCheckedOut() }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("دفع الحجز", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            bottomBar = {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Button(
                        onClick = { showAddPayment = true },
                        enabled = !state.isProcessing,
                        modifier = Modifier.weight(1f).height(52.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.SuccessColor),
                        shape = RoundedCornerShape(12.dp)
                    ) { Text("إضافة دفعة جديدة", color = Color.White, fontWeight = FontWeight.Bold) }
                    Button(
                        onClick = { showCompleteConfirm = true },
                        enabled = !state.isProcessing && state.remaining <= 0.0,
                        modifier = Modifier.weight(1f).height(52.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = AppColors.PrimaryColor,
                            disabledContainerColor = AppColors.LightGray
                        ),
                        shape = RoundedCornerShape(12.dp)
                    ) { Text("إتمام الحجز", color = Color.White, fontWeight = FontWeight.Bold) }
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

                    // Booking info card (Dart l.196-278).
                    item {
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                            shape = RoundedCornerShape(12.dp),
                            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(booking.guestName.ifBlank { "ضيف" }, style = AppTypography.titleMedium, fontWeight = FontWeight.Bold)
                                    Text("غرفة ${booking.roomNumber}", color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold)
                                }
                                CheckoutDetailRow("الهاتف", booking.guestPhone.ifBlank { "غير متوفر" })
                                CheckoutDetailRow("نوع الهوية", booking.guestIdType)
                                CheckoutDetailRow("رقم الهوية", booking.guestIdNumber)
                                CheckoutDetailRow("الجنسية", booking.guestNationality)
                                CheckoutDetailRow(
                                    "تاريخ الدخول",
                                    HotelTimeEngine.parseDate(booking.checkinDate)?.let { HotelTimeEngine.formatDisplay(it) } ?: "—"
                                )
                                CheckoutDetailRow(
                                    "تاريخ المغادرة المخطط",
                                    HotelTimeEngine.parseDate(booking.checkoutDate)?.let { HotelTimeEngine.formatDisplay(it) } ?: "—"
                                )
                                booking.actualCheckout?.let {
                                    CheckoutDetailRow(
                                        "المغادرة الفعلي",
                                        HotelTimeEngine.parseDate(it)?.let { d -> HotelTimeEngine.formatDisplay(d) } ?: "—"
                                    )
                                }
                                CheckoutDetailRow("الليالي المتوقعة", "${state.expectedNights}")
                                CheckoutDetailRow("الليالي الفعلية", "${state.actualNights}")
                                if (state.hasExtraNightsAfterCutoff) {
                                    val extra = state.actualNights - state.expectedNights
                                    Text(
                                        "تمت إضافة $extra ليلة بعد الساعة 14:00 (لم يسجل النزيل خروج)",
                                        color = AppColors.WarningColor, fontSize = 11.sp
                                    )
                                }
                                CheckoutDetailRow("سعر الليلة", CurrencyFormatter.formatAmount(state.roomPrice))
                                if (booking.discount > 0) {
                                    CheckoutDetailRow("التخفيض", CurrencyFormatter.formatAmount(booking.discount), AppColors.PrimaryColor)
                                }
                                CheckoutDetailRow("المبلغ المستحق", CurrencyFormatter.formatAmount(state.totalDue), AppColors.PrimaryColor)
                                CheckoutDetailRow("الحالة", booking.status)
                            }
                        }
                    }

                    // Payments summary (Dart l.280-386).
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                            CheckoutStatBox("المبلغ المستحق", CurrencyFormatter.formatAmount(state.totalDue), AppColors.PrimaryColor, Modifier.weight(1f))
                            CheckoutStatBox("إجمالي المدفوع", CurrencyFormatter.formatAmount(state.totalPaid), AppColors.SuccessColor, Modifier.weight(1f))
                            CheckoutStatBox(
                                "المتبقي", CurrencyFormatter.formatAmount(state.remaining),
                                if (state.remaining > 0) AppColors.DangerColor else AppColors.SuccessColor,
                                Modifier.weight(1f)
                            )
                        }
                    }

                    item {
                        Text("سجل دفعات الحجز (${state.payments.size})", style = AppTypography.titleMedium, fontWeight = FontWeight.Bold)
                    }

                    if (state.payments.isEmpty()) {
                        item {
                            Card(
                                colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                                shape = RoundedCornerShape(12.dp)
                            ) {
                                Box(modifier = Modifier.padding(20.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
                                    Text("لا توجد دفعات سابقة", style = AppTypography.bodyMedium, color = AppColors.TextSecondary)
                                }
                            }
                        }
                    } else {
                        items(state.payments.size) { index ->
                            val p = state.payments[index]
                            Card(
                                colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                                shape = RoundedCornerShape(10.dp),
                                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Row(
                                    modifier = Modifier.padding(12.dp).fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column {
                                        Text(
                                            "${CurrencyFormatter.formatAmount(p.amount)} ريال",
                                            fontWeight = FontWeight.Bold, color = if (p.amount >= 0) AppColors.SuccessColor else AppColors.DangerColor
                                        )
                                        Text("${p.paymentMethod} • ${p.paymentDate.take(16).replace("T", " ")}", fontSize = 10.sp, color = AppColors.TextSecondary)
                                        p.notes?.let { if (it.isNotBlank()) Text(it, fontSize = 10.sp, color = AppColors.TextSecondary) }
                                    }
                                    Text(
                                        revenueLabelShort(p.revenueType), fontSize = 10.sp, color = AppColors.WarningColor,
                                        modifier = Modifier.background(AppColors.AccentSoft, RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 2.dp)
                                    )
                                }
                            }
                        }
                    }

                    if (state.remaining > 0) {
                        item {
                            Text(
                                "لا يمكن إتمام الحجز قبل سداد المبلغ المتبقي",
                                color = AppColors.DangerColor, fontSize = 12.sp
                            )
                        }
                    }
                }
            }
        }
    }

    if (showAddPayment) {
        CheckoutAddPaymentDialog(
            onDismiss = { showAddPayment = false },
            onConfirm = { amount, method, revenueType, notes ->
                viewModel.addPayment(amount, method, revenueType, notes)
                showAddPayment = false
            }
        )
    }

    if (showCompleteConfirm) {
        AlertDialog(
            onDismissRequest = { showCompleteConfirm = false },
            title = { Text("تأكيد إتمام الحجز") },
            text = {
                Text("هل أنت متأكد من إتمام هذا الحجز؟ سيتم تحديث حالة الحجز إلى 'مكتمل' وحالة الغرفة إلى 'شاغرة'.")
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.completeCheckout()
                    showCompleteConfirm = false
                }) { Text("إتمام", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { showCompleteConfirm = false }) { Text("إلغاء") }
            }
        )
    }
}

private fun revenueLabelShort(revenueType: String): String = when (revenueType.lowercase()) {
    "room" -> "إيراد غرفة"
    "service" -> "خدمات إضافية"
    "deposit" -> "عربون"
    else -> "أخرى"
}

@Composable
private fun CheckoutDetailRow(label: String, value: String, valueColor: Color = AppColors.TextPrimary) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = AppTypography.bodySmall, color = AppColors.TextSecondary)
        Text(value, style = AppTypography.bodySmall, color = valueColor, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun CheckoutStatBox(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.1f))
    ) {
        Column(
            modifier = Modifier.padding(vertical = 12.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            Text(label, fontSize = 10.sp, color = AppColors.TextSecondary)
        }
    }
}

/** Dart `_addPayment` dialog (l.442-654): نقدي/تحويل + 4 revenue types + notes. */
@Composable
private fun CheckoutAddPaymentDialog(
    onDismiss: () -> Unit,
    onConfirm: (amount: Double, method: String, revenueType: String, notes: String?) -> Unit
) {
    var amount by remember { mutableStateOf("") }
    var method by remember { mutableStateOf("نقدي") }
    var revenueType by remember { mutableStateOf("room") }
    var notes by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("إضافة دفعة جديدة", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { c -> c.isDigit() } },
                    label = { Text("المبلغ *") },
                    prefix = { Text("ر.ي ") },
                    singleLine = true
                )
                Text("طريقة الدفع", style = AppTypography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("نقدي" to "نقدي", "تحويل" to "تحويل بنكي").forEach { (key, label) ->
                        FilterChip(
                            selected = method == key,
                            onClick = { method = key },
                            label = { Text(label, fontSize = 12.sp) }
                        )
                    }
                }
                Text("نوع الإيراد", style = AppTypography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("room" to "إيراد غرفة", "service" to "خدمات إضافية").forEach { (key, label) ->
                        FilterChip(
                            selected = revenueType == key,
                            onClick = { revenueType = key },
                            label = { Text(label, fontSize = 11.sp) }
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("deposit" to "عربون", "other" to "أخرى").forEach { (key, label) ->
                        FilterChip(
                            selected = revenueType == key,
                            onClick = { revenueType = key },
                            label = { Text(label, fontSize = 11.sp) }
                        )
                    }
                }
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("ملاحظات") },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val value = CurrencyFormatter.parseAmount(amount)
                    if (value != null && value > 0) {
                        onConfirm(value, method, revenueType, notes.ifBlank { null })
                    }
                }
            ) { Text("حفظ", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}
