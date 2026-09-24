package com.marina.marina.presentation.payments

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.AddCard
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Payment
import androidx.compose.material.icons.filled.Today
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Hotel
import androidx.compose.material.icons.outlined.Payment
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults.SecondaryIndicator
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import kotlin.math.roundToInt

// ─── Dart palette (payments_main_screen.dart) ───
private val GreenPrimary = Color(0xFF4CAF50)
private val Green800 = Color(0xFF2E7D32)
private val Grey600 = Color(0xFF757575)
private val Grey = Color(0xFF9E9E9E)
private val Amber700 = Color(0xFFFFA000)
private val BluePrimary = Color(0xFF2196F3)
private val Blue50 = Color(0xFFE3F2FD)
private val OrangePrimary = Color(0xFFFF9800)
private val Orange600 = Color(0xFFFB8C00)
private val Orange700 = Color(0xFFF57C00)
private val Orange800 = Color(0xFFEF6C00)
private val Orange100 = Color(0xFFFFE0B2)
private val Red700 = Color(0xFFD32F2F)
private val Red800 = Color(0xFFC62828)
private val Red100 = Color(0xFFFFCDD2)

/**
 * إدارة المدفوعات — نقل 1:1 لـ payments_main_screen.dart
 * (فرع feat/cloudflare-sync-execution):
 *
 *  • FAB «دفعة جديدة» بأيقونة add_card (أخضر) يفتح حوار الدفعة التراكمية.
 *  • تبويبات: نظرة عامة / المعاملات (PaymentHistoryScreen مضمّنة كاملة
 *    كما في Dart l.389) / الحجوزات النشطة.
 *  • نظرة عامة: 3 بطاقات إحصائية (اليوم الفندقي/الإجمالي/هذا الشهر) +
 *    مدفوعات اليوم الفندقي مع «عرض الكل» (ينتقل للتبويب الثاني).
 *  • الحجوزات النشطة: نوافذ التأخر 22:00 (تنبيه) و23:00-05:00 (متأخر)
 *    بألوان الحدود والشارات وزر الدفع المتحول للأحمر/البرتقالي.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaymentsMainScreen(
    onOpenBookingCheckout: (bookingId: Long) -> Unit = {},
    viewModel: PaymentsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var snackbarTone by remember { mutableStateOf(MsgTone.INFO) }
    var selectedTab by remember { mutableIntStateOf(0) }
    var showNewPayment by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message
        if (msg != null) {
            snackbarTone = state.tone
            snackbarHostState.showSnackbar(msg)
            if (state.error == null) showNewPayment = false
            viewModel.consumeMessage()
        }
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { PaymentSnackbarHost(snackbarHostState, snackbarTone) },
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
                // Dart: FloatingActionButton.extended — icon add_card + 'دفعة جديدة' أخضر.
                ExtendedFloatingActionButton(
                    onClick = { if (!state.isSaving) showNewPayment = true },
                    icon = { Icon(Icons.Filled.AddCard, contentDescription = null) },
                    text = { Text("دفعة جديدة") },
                    containerColor = GreenPrimary,
                    contentColor = Color.White
                )
            }
        ) { padding ->
            Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                TabRow(
                    selectedTabIndex = selectedTab,
                    containerColor = AppColors.SurfaceColor,
                    // Dart: indicatorColor أخضر — SecondaryIndicator بنفس النمط الرسمي.
                    indicator = { positions ->
                        SecondaryIndicator(
                            modifier = Modifier.tabIndicatorOffset(positions[selectedTab]),
                            color = GreenPrimary
                        )
                    }
                ) {
                    // Dart l.82-88: labelStyle 12 bold / unselected 11.
                    Tab(
                        selected = selectedTab == 0, onClick = { selectedTab = 0 },
                        text = { Text("نظرة عامة", fontSize = 12.sp, fontWeight = if (selectedTab == 0) FontWeight.Bold else FontWeight.Normal) },
                        icon = { Icon(Icons.Filled.Dashboard, null, modifier = Modifier.size(18.dp)) },
                        selectedContentColor = Green800,
                        unselectedContentColor = Grey600
                    )
                    Tab(
                        selected = selectedTab == 1, onClick = { selectedTab = 1 },
                        text = { Text("المعاملات", fontSize = 12.sp, fontWeight = if (selectedTab == 1) FontWeight.Bold else FontWeight.Normal) },
                        icon = { Icon(Icons.Filled.List, null, modifier = Modifier.size(18.dp)) },
                        selectedContentColor = Green800,
                        unselectedContentColor = Grey600
                    )
                    Tab(
                        selected = selectedTab == 2, onClick = { selectedTab = 2 },
                        text = { Text("الحجوزات النشطة", fontSize = 12.sp, fontWeight = if (selectedTab == 2) FontWeight.Bold else FontWeight.Normal) },
                        icon = { Icon(Icons.Filled.Hotel, null, modifier = Modifier.size(18.dp)) },
                        selectedContentColor = Green800,
                        unselectedContentColor = Grey600
                    )
                }

                when (selectedTab) {
                    0 -> OverviewTab(state = state, onShowAll = { selectedTab = 1 })
                    // Dart l.389: `_buildTransactionsTab()` = PaymentHistoryScreen().
                    1 -> PaymentHistoryScreen(showBack = false)
                    2 -> ActiveBookingsTab(state = state, onPay = { onOpenBookingCheckout(it.id) })
                }
            }
        }
    }

    if (showNewPayment) {
        StandalonePaymentDialog(
            isSaving = state.isSaving,
            onDismiss = { showNewPayment = false },
            onSave = { amount, method, notes, reference ->
                viewModel.addStandalonePayment(amount, method, notes, reference)
            }
        )
    }
}

// ---------------------------------------------------------------------------
// Tab 1 — نظرة عامة (Dart _buildOverviewTab l.110-384)
// ---------------------------------------------------------------------------

@Composable
private fun OverviewTab(state: PaymentsUiState, onShowAll: () -> Unit) {
    if (state.isLoading) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }
    if (state.payments.isEmpty()) {
        // Dart l.119-131: payment_outlined 64 grey + نص 18 رمادي.
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.Payment, null, modifier = Modifier.size(64.dp), tint = Grey)
                Spacer(Modifier.height(16.dp))
                Text("لا توجد مدفوعات مسجلة", fontSize = 18.sp, color = Grey)
            }
        }
        return
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        QuickStats(state)
        Spacer(Modifier.height(16.dp))
        RecentPaymentsCard(state, onShowAll)
    }
}

/** Dart `_buildQuickStats` (l.137-196) + `_buildStatCard` (l.198-274). */
@Composable
private fun QuickStats(state: PaymentsUiState) {
    Row(modifier = Modifier.fillMaxWidth()) {
        StatCard(
            title = "اليوم الفندقي",
            value = CurrencyFormatter.formatAmount(state.todayTotal),
            icon = Icons.Filled.Today,
            color = Amber700,
            modifier = Modifier.weight(1f)
        )
        Spacer(Modifier.width(8.dp))
        StatCard(
            title = "الإجمالي",
            value = CurrencyFormatter.formatAmount(state.grandTotal),
            icon = Icons.Filled.AccountBalanceWallet,
            color = GreenPrimary,
            modifier = Modifier.weight(1f)
        )
        Spacer(Modifier.width(8.dp))
        StatCard(
            title = "هذا الشهر",
            value = CurrencyFormatter.formatAmount(state.monthTotal),
            icon = Icons.Filled.CalendarMonth,
            color = BluePrimary,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun StatCard(
    title: String,
    value: String,
    icon: ImageVector,
    color: Color,
    modifier: Modifier = Modifier
) {
    Card(modifier = modifier) {
        Column(
            modifier = Modifier.padding(vertical = 6.dp, horizontal = 8.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(icon, null, tint = color, modifier = Modifier.size(18.dp))
            Spacer(Modifier.height(4.dp))
            Text(value, fontSize = 13.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            Spacer(Modifier.height(1.dp))
            Text(title, fontSize = 10.sp, color = Grey600, textAlign = TextAlign.Center)
        }
    }
}

/** Dart `_buildRecentPayments` (l.327-384) — مدفوعات اليوم الفندقي (أول 10). */
@Composable
private fun RecentPaymentsCard(state: PaymentsUiState, onShowAll: () -> Unit) {
    Card {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("مدفوعات اليوم الفندقي", style = AppTypography.titleMedium)
                TextButton(onClick = onShowAll) { Text("عرض الكل") }
            }
            Spacer(Modifier.height(8.dp))
            state.recentTodayPayments.forEach { payment ->
                TodayPaymentRow(payment)
            }
        }
    }
}

@Composable
private fun TodayPaymentRow(payment: Payment) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            dbMethodIcon(payment.paymentMethod),
            null,
            tint = dbMethodColor(payment.paymentMethod)
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(CurrencyFormatter.formatAmount(payment.amount), fontWeight = FontWeight.Bold)
            Text(
                "${payment.paymentMethod} • ${payment.paymentDate}",
                fontSize = 12.sp,
                color = AppColors.TextSecondary
            )
        }
        payment.roomNumber?.let { room ->
            AssistChip(
                onClick = {},
                label = { Text(room) },
                colors = AssistChipDefaults.assistChipColors(containerColor = Blue50)
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Tab 3 — الحجوزات النشطة (Dart _buildActiveBookingsTab l.406-636)
// ---------------------------------------------------------------------------

@Composable
private fun ActiveBookingsTab(state: PaymentsUiState, onPay: (Booking) -> Unit) {
    if (state.allBookings.isEmpty()) {
        // Dart l.415-428: لا حجوزات إطلاقاً.
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.Hotel, null, modifier = Modifier.size(64.dp), tint = Grey)
                Spacer(Modifier.height(16.dp))
                Text("لا توجد حجوزات نشطة", fontSize = 18.sp, color = Grey)
            }
        }
        return
    }
    if (state.activeBookings.isEmpty()) {
        // Dart l.432-445: كل الحجوزات مكتملة.
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.CheckCircle, null, modifier = Modifier.size(64.dp), tint = GreenPrimary)
                Spacer(Modifier.height(16.dp))
                Text("جميع الحجوزات مكتملة!", fontSize = 18.sp, color = GreenPrimary)
            }
        }
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        items(state.activeBookings, key = { it.id }) { booking ->
            ActiveBookingCard(booking, onPay)
        }
    }
}

@Composable
private fun ActiveBookingCard(booking: Booking, onPay: (Booking) -> Unit) {
    // ✅ نوافذ التأخر: 22:00-23:00 تنبيه برتقالي، 23:00-05:00 متأخر أحمر.
    val hour = remember { java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY) }
    val isLateWindow = hour >= 22 && hour < 23
    val isOverdueWindow = hour >= 23 || hour < 5
    val hasRemainingBalance = booking.remainingBalanceCached.roundToInt() > 0
    val isLate = hasRemainingBalance && isLateWindow
    val isOverdue = hasRemainingBalance && isOverdueWindow

    // Dart l.532-543: لون دائرة الغرفة (برتقالي افتراضياً، أحمر عند التأخر).
    val avatarBg = if (isOverdue) Red100 else Orange100
    val avatarFg = when {
        isOverdue -> Red700
        isLate -> Orange700
        else -> OrangePrimary
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        shape = RoundedCornerShape(8.dp),
        border = when {
            isOverdue -> androidx.compose.foundation.BorderStroke(1.5.dp, Red700)
            isLate -> androidx.compose.foundation.BorderStroke(1.2.dp, Orange700)
            else -> null
        }
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier.size(32.dp).background(avatarBg, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(booking.roomNumber, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = avatarFg)
            }
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        booking.guestName,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f)
                    )
                    if (isLate) {
                        LateBadge(
                            text = "تنبيه 22:00",
                            bg = Orange100, border = Orange700, fg = Orange800,
                            icon = Icons.Filled.WarningAmber, iconTint = Orange700
                        )
                    } else if (isOverdue) {
                        LateBadge(
                            text = "متأخر",
                            bg = Red100, border = Red700, fg = Red800,
                            icon = Icons.Filled.ErrorOutline, iconTint = Red700
                        )
                    }
                }
                Text("الهاتف: ${booking.guestPhone}", fontSize = 10.sp, color = Grey)
                Text("دخول: ${booking.checkinDate}", fontSize = 10.sp, color = Grey)
                Text("الجنسية: ${booking.guestNationality}", fontSize = 10.sp, color = Grey)
            }
            Spacer(Modifier.width(8.dp))
            // Dart l.622-643: زر دفع يتحول أحمر/برتقالي حسب التأخر.
            Button(
                onClick = { onPay(booking) },
                colors = ButtonDefaults.buttonColors(
                    containerColor = when {
                        isOverdue -> Red700
                        isLate -> Orange600
                        else -> GreenPrimary
                    },
                    contentColor = Color.White
                ),
                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
                shape = RoundedCornerShape(20.dp)
            ) {
                Icon(Icons.Filled.Payment, null, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(4.dp))
                Text(if (isOverdue) "دفع فوري" else "دفع", fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun LateBadge(
    text: String,
    bg: Color,
    border: Color,
    fg: Color,
    icon: ImageVector,
    iconTint: Color
) {
    Row(
        modifier = Modifier
            .background(bg, RoundedCornerShape(8.dp))
            .border(0.8.dp, border, RoundedCornerShape(8.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, modifier = Modifier.size(10.dp), tint = iconTint)
        Spacer(Modifier.width(2.dp))
        Text(text, fontSize = 8.sp, color = fg, fontWeight = FontWeight.Bold)
    }
}

// ---------------------------------------------------------------------------
// FAB dialog — Dart `_showNewPaymentDialog` (l.679-829)
// ---------------------------------------------------------------------------

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StandalonePaymentDialog(
    isSaving: Boolean,
    onDismiss: () -> Unit,
    onSave: (amount: Double, method: String, notes: String?, reference: String?) -> Unit
) {
    var amount by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var reference by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf(PayMethodUi.CASH) }

    AlertDialog(
        onDismissRequest = { if (!isSaving) onDismiss() },
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.AddCard, null, tint = GreenPrimary)
                Spacer(Modifier.width(8.dp))
                Text("دفعة جديدة تراكمية", style = AppTypography.titleLarge)
            }
        },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text("طريقة الدفع", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                // Dart Wrap of ChoiceChips — أيقونة الطريقة + الاسم بلون الطريقة.
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    PayMethodUi.values().forEach { method ->
                        val isSelected = selected == method
                        FilterChip(
                            selected = isSelected,
                            onClick = { selected = method },
                            label = {
                                Text(
                                    method.label,
                                    fontSize = 12.sp,
                                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                    color = if (isSelected) Color.White else method.color
                                )
                            },
                            leadingIcon = {
                                Icon(
                                    method.icon, null,
                                    modifier = Modifier.size(16.dp),
                                    tint = if (isSelected) Color.White else method.color
                                )
                            },
                            colors = FilterChipDefaults.filterChipColors(
                                containerColor = Color.Transparent,
                                selectedContainerColor = method.color
                            )
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { c -> c.isDigit() } },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("المبلغ *") },
                    prefix = { Text("ر.ي ") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true
                )
                if (selected == PayMethodUi.TRANSFER || selected == PayMethodUi.CHECK) {
                    OutlinedTextField(
                        value = reference,
                        onValueChange = { reference = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("رقم المرجع / الشيك") },
                        singleLine = true
                    )
                }
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("ملاحظات (اختياري)") },
                    minLines = 2,
                    maxLines = 2
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val parsed = CurrencyFormatter.parseAmount(amount)
                    if (parsed == null || parsed <= 0) return@Button
                    onSave(
                        parsed,
                        selected.db,
                        notes.trim().ifBlank { null },
                        reference.ifBlank { null }
                    )
                },
                enabled = !isSaving,
                colors = ButtonDefaults.buttonColors(containerColor = GreenPrimary, contentColor = Color.White)
            ) {
                if (isSaving) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = Color.White
                    )
                } else {
                    Text("تسجيل الدفعة")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}
