package com.marina.marina.presentation.payments

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

/**
 * إدارة المدفوعات — 1:1 port of `payments_main_screen.dart`:
 * three tabs (نظرة عامة / المعاملات / الحجوزات النشطة), quick stats with
 * the Dart quirks (grand total sums voided payments too, today's card
 * excludes them), recent today payments, active bookings with the late
 * windows (22:00 warning / 23:00-05:00 overdue) and the FAB standalone
 * payment dialog with the 5 methods + reference field for transfer/check.
 */
@Composable
fun PaymentsMainScreen(
    onOpenBookingCheckout: (bookingId: Long) -> Unit = {},
    viewModel: PaymentsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var selectedTab by remember { mutableStateOf(0) }
    var showNewPayment by remember { mutableStateOf(false) }

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
                    title = { Text("إدارة المدفوعات", style = AppTypography.titleLarge) },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            floatingActionButton = {
                ExtendedFloatingActionButton(
                    onClick = { showNewPayment = true },
                    containerColor = AppColors.SuccessColor,
                    contentColor = Color.White
                ) {
                    Text("+ دفعة جديدة", fontWeight = FontWeight.Bold)
                }
            }
        ) { padding ->
            Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                TabRow(selectedTabIndex = selectedTab) {
                    Tab(selected = selectedTab == 0, onClick = { selectedTab = 0 },
                        text = { Text("نظرة عامة", fontSize = 13.sp) })
                    Tab(selected = selectedTab == 1, onClick = { selectedTab = 1 },
                        text = { Text("المعاملات", fontSize = 13.sp) })
                    Tab(selected = selectedTab == 2, onClick = { selectedTab = 2 },
                        text = { Text("الحجوزات النشطة", fontSize = 13.sp) })
                }

                when (selectedTab) {
                    0 -> OverviewTab(state)
                    1 -> TransactionsTab(
                        state = state,
                        onSearch = { viewModel.setSearchQuery(it) },
                        onMethodFilter = { viewModel.setMethodFilter(it) },
                        onRevenueFilter = { viewModel.setRevenueFilter(it) }
                    )
                    2 -> ActiveBookingsTab(
                        bookings = state.activeBookings,
                        lateWindow = state.lateWindow,
                        onPay = { onOpenBookingCheckout(it.id) }
                    )
                }
            }
        }
    }

    if (showNewPayment) {
        StandalonePaymentDialog(
            onDismiss = { showNewPayment = false },
            onConfirm = { amount, method, notes, reference ->
                viewModel.addStandalonePayment(amount, method, notes, reference)
                showNewPayment = false
            }
        )
    }
}

// ---------------------------------------------------------------------------
// Tab 1 — Overview (Dart l.110-384)
// ---------------------------------------------------------------------------

@Composable
private fun OverviewTab(state: PaymentsUiState) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (state.payments.isEmpty() && !state.isLoading) {
            item {
                EmptyCard("لا توجد مدفوعات مسجلة", "عند إضافة مدفوعات جديدة ستظهر هنا")
            }
        } else {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    StatCard(
                        "اليوم الفندقي", CurrencyFormatter.formatAmount(state.todayTotal),
                        Color(0xFFFFA000), Modifier.weight(1f)
                    )
                    StatCard(
                        "الإجمالي", CurrencyFormatter.formatAmount(state.grandTotal),
                        AppColors.SuccessColor, Modifier.weight(1f)
                    )
                    StatCard(
                        "هذا الشهر", CurrencyFormatter.formatAmount(state.monthTotal),
                        Color(0xFF1976D2), Modifier.weight(1f)
                    )
                }
            }
            item {
                Card(
                    colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                    shape = RoundedCornerShape(12.dp),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("مدفوعات اليوم الفندقي", fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
                        if (state.recentTodayPayments.isEmpty()) {
                            Text("لا توجد مدفوعات اليوم", style = AppTypography.bodyMedium, color = AppColors.TextSecondary)
                        } else {
                            state.recentTodayPayments.forEach { payment ->
                                TodayPaymentRow(payment)
                                HorizontalDivider(color = AppColors.DividerColor.copy(alpha = 0.5f))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TodayPaymentRow(payment: Payment) {
    val (color, icon) = methodVisual(payment.paymentMethod)
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(
            modifier = Modifier.size(36.dp).background(color.copy(alpha = 0.15f), RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center
        ) { Text(icon, fontSize = 16.sp) }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                "${CurrencyFormatter.formatAmount(payment.amount)} ريال",
                fontWeight = FontWeight.Bold, fontSize = 14.sp, color = AppColors.TextPrimary
            )
            Text(
                "${payment.paymentMethod} • ${payment.paymentDate.take(16).replace("T", " ")}",
                fontSize = 10.sp, color = AppColors.TextSecondary
            )
        }
        payment.roomNumber?.let { room ->
            Text(
                room, fontSize = 11.sp, color = AppColors.PrimaryColor,
                modifier = Modifier.background(AppColors.PrimaryLight, RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 3.dp)
            )
        }
    }
}

private fun methodVisual(method: String): Pair<Color, String> = when {
    method.contains("نقدي") || method.contains("cash", true) -> Color(0xFF2E7D5B) to "💵"
    method.contains("بطاقة") || method.contains("card", true) -> Color(0xFF1976D2) to "💳"
    method.contains("تحويل") || method.contains("transfer", true) -> Color(0xFFF57C00) to "🏦"
    method.contains("شيك") || method.contains("check", true) -> Color(0xFF7B1FA2) to "🧾"
    else -> Color(0xFF6C6F8F) to "💳"
}

@Composable
private fun StatCard(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.1f))
    ) {
        Column(
            modifier = Modifier.padding(vertical = 12.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Text(label, fontSize = 10.sp, color = AppColors.TextSecondary)
        }
    }
}

// ---------------------------------------------------------------------------
// Tab 2 — Transactions: search + method + revenue filters + filtered total
// ---------------------------------------------------------------------------

@Composable
private fun TransactionsTab(
    state: PaymentsUiState,
    onSearch: (String) -> Unit,
    onMethodFilter: (String) -> Unit,
    onRevenueFilter: (String) -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        FilterBar(state, onSearch, onMethodFilter, onRevenueFilter)
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                Card(
                    colors = CardDefaults.cardColors(containerColor = AppColors.SuccessColor.copy(alpha = 0.1f)),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp).fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text("إجمالي المدفوعات", fontSize = 12.sp, color = AppColors.TextSecondary)
                            Text(
                                "${CurrencyFormatter.formatAmount(state.filtered.sumOf { it.amount })} ريال",
                                fontWeight = FontWeight.Bold, color = AppColors.SuccessColor, fontSize = 16.sp
                            )
                        }
                        Text(
                            "عدد المدفوعات: ${state.filtered.size}",
                            fontSize = 12.sp, color = AppColors.TextSecondary,
                            modifier = Modifier.align(Alignment.CenterVertically)
                        )
                    }
                }
            }
            if (state.filtered.isEmpty()) {
                item { EmptyCard("لا توجد مدفوعات تطابق الفلاتر المحددة", "جرّب تعديل الفلاتر أو البحث") }
            } else {
                items(state.filtered, key = { it.id }) { payment ->
                    PaymentListRow(payment)
                }
            }
        }
    }
}

@Composable
private fun FilterBar(
    state: PaymentsUiState,
    onSearch: (String) -> Unit,
    onMethodFilter: (String) -> Unit,
    onRevenueFilter: (String) -> Unit
) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        OutlinedTextField(
            value = state.searchQuery,
            onValueChange = onSearch,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("بحث (غرفة، مبلغ، ملاحظات...)", fontSize = 12.sp) },
            singleLine = true,
            shape = RoundedCornerShape(12.dp)
        )
        Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("all" to "الكل", "نقدي" to "نقدي", "تحويل" to "تحويل", "بطاقة" to "بطاقة", "شيك" to "شيك", "تقسيط" to "تقسيط").forEach { (key, label) ->
                FilterChip(
                    selected = state.methodFilter == key,
                    onClick = { onMethodFilter(key) },
                    label = { Text(label, fontSize = 11.sp) }
                )
            }
        }
        Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("all" to "الكل", "room" to "إقامة", "service" to "خدمات", "deposit" to "عربون", "other" to "أخرى").forEach { (key, label) ->
                FilterChip(
                    selected = state.revenueFilter == key,
                    onClick = { onRevenueFilter(key) },
                    label = { Text(label, fontSize = 11.sp) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = AppColors.AccentSoft,
                        selectedLabelColor = AppColors.WarningColor
                    )
                )
            }
        }
    }
}

@Composable
private fun PaymentListRow(payment: Payment) {
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
                modifier = Modifier.size(40.dp).background(color.copy(alpha = 0.15f), RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center
            ) { Text(icon, fontSize = 18.sp) }
            Column(modifier = Modifier.weight(1f)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "${CurrencyFormatter.formatAmount(payment.amount)} ريال",
                        fontWeight = FontWeight.Bold, fontSize = 14.sp
                    )
                    if (payment.isVoided) {
                        Text(
                            "ملغاة", fontSize = 9.sp, color = AppColors.DangerColor,
                            modifier = Modifier.background(AppColors.DangerColor.copy(alpha = 0.12f), RoundedCornerShape(6.dp)).padding(horizontal = 4.dp, vertical = 1.dp)
                        )
                    }
                    Text(
                        revenueLabel(payment.revenueType), fontSize = 9.sp, color = AppColors.WarningColor,
                        modifier = Modifier.background(AppColors.AccentSoft, RoundedCornerShape(6.dp)).padding(horizontal = 4.dp, vertical = 1.dp)
                    )
                }
                Text(
                    "${payment.paymentMethod} • ${payment.paymentDate.take(16).replace("T", " ")}",
                    fontSize = 10.sp, color = AppColors.TextSecondary
                )
                payment.notes?.let {
                    if (it.isNotBlank()) Text(it, fontSize = 10.sp, color = AppColors.TextSecondary, maxLines = 1)
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

private fun revenueLabel(revenueType: String): String = when (revenueType.lowercase()) {
    "room" -> "إقامة"
    "service" -> "خدمات"
    "deposit" -> "عربون"
    else -> "أخرى"
}

// ---------------------------------------------------------------------------
// Tab 3 — Active bookings (Dart l.405-636)
// ---------------------------------------------------------------------------

@Composable
private fun ActiveBookingsTab(
    bookings: List<Booking>,
    lateWindow: LateWindow,
    onPay: (Booking) -> Unit
) {
    if (bookings.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            EmptyCard("لا توجد حجوزات نشطة", "جميع الحجوزات مكتملة!")
        }
        return
    }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        items(bookings, key = { it.id }) { booking ->
            ActiveBookingCard(booking, lateWindow, onPay)
        }
    }
}

@Composable
private fun ActiveBookingCard(booking: Booking, lateWindow: LateWindow, onPay: (Booking) -> Unit) {
    val hasRemaining = booking.remainingBalanceCached.toInt() > 0
    val isLate = hasRemaining && lateWindow == LateWindow.WARNING
    val isOverdue = hasRemaining && lateWindow == LateWindow.OVERDUE

    val borderColor = when {
        isOverdue -> AppColors.DangerColor
        isLate -> AppColors.WarningColor
        else -> Color.Transparent
    }
    val badgeColor = when {
        isOverdue -> AppColors.DangerColor
        isLate -> AppColors.WarningColor
        else -> Color.Transparent
    }

    Card(
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        border = if (borderColor != Color.Transparent) androidx.compose.foundation.BorderStroke(1.5.dp, borderColor) else null,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(12.dp).fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .background(
                        when {
                            isOverdue -> Color(0xFFFFEBEE)
                            isLate -> Color(0xFFFFF3E0)
                            else -> AppColors.PrimaryLight
                        }, CircleShape
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(booking.roomNumber, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor, fontSize = 15.sp)
            }
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(booking.guestName.ifBlank { "ضيف" }, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    if (badgeColor != Color.Transparent) {
                        Text(
                            if (isOverdue) "متأخر" else "تنبيه 22:00",
                            fontSize = 8.sp, color = badgeColor, fontWeight = FontWeight.Bold,
                            modifier = Modifier.background(badgeColor.copy(alpha = 0.12f), RoundedCornerShape(6.dp)).padding(horizontal = 4.dp, vertical = 1.dp)
                        )
                    }
                }
                Text(
                    buildString {
                        if (booking.guestPhone.isNotBlank()) append("${booking.guestPhone} • ")
                        append("دخول: ${booking.checkinDate.take(10)}")
                        if (booking.guestNationality.isNotBlank()) append(" • ${booking.guestNationality}")
                    },
                    fontSize = 10.sp, color = AppColors.TextSecondary, maxLines = 1
                )
                if (hasRemaining) {
                    Text(
                        "متبقي: ${CurrencyFormatter.formatAmount(booking.remainingBalanceCached)}",
                        fontSize = 10.sp, color = AppColors.WarningColor, fontWeight = FontWeight.Bold
                    )
                }
            }
            Button(
                onClick = { onPay(booking) },
                colors = ButtonDefaults.buttonColors(
                    containerColor = when {
                        isOverdue -> Color(0xFFD32F2F)
                        isLate -> Color(0xFFF57C00)
                        else -> AppColors.SuccessColor
                    }
                ),
                shape = RoundedCornerShape(10.dp),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp)
            ) {
                Text(if (isOverdue) "دفع فوري" else "دفع", fontSize = 12.sp, color = Color.White)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// FAB dialog — Dart _showNewPaymentDialog (l.679-829)
// ---------------------------------------------------------------------------

@Composable
private fun StandalonePaymentDialog(
    onDismiss: () -> Unit,
    onConfirm: (amount: Double, method: String, notes: String?, reference: String?) -> Unit
) {
    var amount by remember { mutableStateOf("") }
    var method by remember { mutableStateOf("نقدي") }
    var notes by remember { mutableStateOf("") }
    var reference by remember { mutableStateOf("") }

    val methods = listOf("نقدي", "تحويل", "بطاقة", "شيك", "تقسيط")

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("دفعة جديدة تراكمية", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("طريقة الدفع", style = AppTypography.labelLarge)
                Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    methods.forEach { m ->
                        FilterChip(
                            selected = method == m,
                            onClick = { method = m },
                            label = { Text(m, fontSize = 12.sp) }
                        )
                    }
                }
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { c -> c.isDigit() } },
                    label = { Text("المبلغ *") },
                    prefix = { Text("ر.ي ") },
                    singleLine = true
                )
                if (method == "تحويل" || method == "شيك") {
                    OutlinedTextField(
                        value = reference,
                        onValueChange = { reference = it },
                        label = { Text("رقم المرجع / الشيك") },
                        singleLine = true
                    )
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
                    val value = CurrencyFormatter.parseAmount(amount)
                    if (value != null && value > 0) {
                        onConfirm(value, method, notes.ifBlank { null }, reference.ifBlank { null })
                    }
                }
            ) { Text("تسجيل الدفعة", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

@Composable
private fun EmptyCard(title: String, subtitle: String) {
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
            Text(title, style = AppTypography.titleMedium, color = AppColors.TextPrimary, textAlign = TextAlign.Center)
            Text(subtitle, style = AppTypography.bodySmall, color = AppColors.TextSecondary, textAlign = TextAlign.Center)
        }
    }
}
