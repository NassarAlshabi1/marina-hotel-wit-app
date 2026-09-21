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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.components.SidebarMenuButton
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun PaymentsMainScreen(
    viewModel: PaymentsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showStandaloneDialog by remember { mutableStateOf(false) }
    var selectedTab by remember { mutableIntStateOf(0) }

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
                    title = { Text("المدفوعات", style = AppTypography.titleLarge) },
                    navigationIcon = { SidebarMenuButton() },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            floatingActionButton = {
                FloatingActionButton(
                    onClick = { showStandaloneDialog = true },
                    containerColor = AppColors.SuccessColor,
                    contentColor = Color.White
                ) {
                    Text("+", fontSize = 24.sp, fontWeight = FontWeight.Bold)
                }
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 16.dp)
            ) {
                // Tabs: overview / transactions
                TabRow(selectedTabIndex = selectedTab) {
                    Tab(selected = selectedTab == 0, onClick = { selectedTab = 0 }, text = { Text("نظرة عامة") })
                    Tab(selected = selectedTab == 1, onClick = { selectedTab = 1 }, text = { Text("السجل") })
                }

                Spacer(modifier = Modifier.height(12.dp))

                if (selectedTab == 0) {
                    PaymentsOverview(state)
                } else {
                    PaymentsHistory(state, viewModel)
                }
            }
        }
    }

    if (showStandaloneDialog) {
        StandalonePaymentDialog(
            onDismiss = { showStandaloneDialog = false },
            onConfirm = { amount, method, notes ->
                viewModel.addStandalonePayment(amount, method, notes)
                showStandaloneDialog = false
            }
        )
    }
}

@Composable
private fun PaymentsOverview(state: PaymentsUiState) {
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
    ) {
        // Gradient total card (Flutter parity).
        Card(
            shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(containerColor = Color.Transparent),
            modifier = Modifier.fillMaxWidth()
        ) {
            Box(
                modifier = Modifier
                    .background(
                        Brush.horizontalGradient(listOf(AppColors.PrimaryColor, AppColors.PrimaryDark)),
                        RoundedCornerShape(12.dp)
                    )
                    .padding(20.dp)
                    .fillMaxWidth()
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    Text("إجمالي اليوم الفندقي", style = AppTypography.bodySmall, color = Color.White.copy(alpha = 0.85f))
                    Text(
                        "${state.todayTotal.toInt()} ريال",
                        style = AppTypography.headlineMedium,
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                    Text("${state.todayCount} دفعة", style = AppTypography.labelMedium, color = Color.White.copy(alpha = 0.85f))
                }
            }
        }

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatBox("إجمالي الشهر", "${state.monthTotal.toInt()}", AppColors.InfoColor, Modifier.weight(1f))
            StatBox("الإجمالي الكلي", "${state.grandTotal.toInt()}", AppColors.SuccessColor, Modifier.weight(1f))
        }

        Text(
            "آخر مدفوعات اليوم",
            style = AppTypography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = AppColors.TextPrimary
        )

        val todayPayments = state.payments.filter { it.hotelDayKey == HotelTimeEngine.currentHotelDayKey() }.take(10)
        if (todayPayments.isEmpty()) {
            Card(
                colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Box(modifier = Modifier.padding(24.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Text("لا توجد مدفوعات اليوم", style = AppTypography.bodyMedium, color = AppColors.TextSecondary)
                }
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                todayPayments.forEach { payment ->
                    PaymentHistoryRow(payment)
                }
            }
        }
    }
}

@Composable
private fun PaymentsHistory(state: PaymentsUiState, viewModel: PaymentsViewModel) {
    Column {
        OutlinedTextField(
            value = state.searchQuery,
            onValueChange = viewModel::setSearchQuery,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("بحث بالمبلغ أو الغرفة...") },
            singleLine = true,
            shape = RoundedCornerShape(12.dp)
        )
        Spacer(modifier = Modifier.height(8.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
            listOf("all" to "الكل", "نقدي" to "نقدي", "تحويل" to "تحويل", "بطاقة" to "بطاقة").forEach { (key, label) ->
                FilterChip(
                    selected = state.methodFilter == key,
                    onClick = { viewModel.setMethodFilter(key) },
                    label = { Text(label, fontSize = 12.sp) }
                )
            }
        }
        Spacer(modifier = Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
            listOf(
                "all" to "كل الإيرادات", "room" to "إقامة", "service" to "خدمات",
                "deposit" to "عربون", "other" to "أخرى"
            ).forEach { (key, label) ->
                FilterChip(
                    selected = state.revenueFilter == key,
                    onClick = { viewModel.setRevenueFilter(key) },
                    label = { Text(label, fontSize = 12.sp) }
                )
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        when {
            state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            state.filtered.isEmpty() -> Box(
                modifier = Modifier.fillMaxWidth().padding(32.dp),
                contentAlignment = Alignment.Center
            ) { Text("لا توجد مدفوعات", style = AppTypography.bodyLarge, color = AppColors.TextSecondary) }
            else -> LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(bottom = 88.dp)
            ) {
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
                            Text("المجموع: ${state.filtered.sumOf { it.amount }.toInt()} ريال", style = AppTypography.titleSmall, color = AppColors.TextPrimary, fontWeight = FontWeight.Bold)
                            Text("${state.filtered.size} دفعة", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
                        }
                    }
                }
                items(state.filtered, key = { it.id }) { payment ->
                    PaymentHistoryRow(payment)
                }
            }
        }
    }
}

@Composable
private fun PaymentHistoryRow(payment: Payment) {
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
                Row(verticalAlignment = Alignment.CenterVertically) {
                    MethodBadge(payment.paymentMethod)
                    Spacer(modifier = Modifier.width(8.dp))
                    payment.roomNumber?.let {
                        Box(
                            modifier = Modifier
                                .background(AppColors.PrimaryLight, RoundedCornerShape(6.dp))
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        ) {
                            Text("غرفة $it", fontSize = 11.sp, color = AppColors.PrimaryColor, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "إيراد: ${revenueLabel(payment.revenueType)}",
                    style = AppTypography.labelSmall,
                    color = AppColors.TextSecondary
                )
                payment.notes?.let { if (it.isNotBlank()) Text(it, style = AppTypography.labelSmall, color = AppColors.TextSecondary, maxLines = 1) }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    "${payment.amount.toInt()} ريال",
                    style = AppTypography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.SuccessColor
                )
                Text(
                    payment.hotelDayKey ?: "",
                    style = AppTypography.labelSmall,
                    color = AppColors.TextSecondary
                )
            }
        }
    }
}

private fun revenueLabel(revenueType: String): String = when (revenueType) {
    "room" -> "إقامة"
    "service" -> "خدمات"
    "deposit" -> "عربون"
    else -> "أخرى"
}

@Composable
private fun MethodBadge(method: String) {
    val color = when (method) {
        "نقدي" -> AppColors.SuccessColor
        "تحويل" -> AppColors.InfoColor
        "بطاقة" -> AppColors.PrimaryColor
        else -> AppColors.MediumGray
    }
    Box(
        modifier = Modifier
            .background(color, RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 3.dp)
    ) {
        Text(method, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun StatBox(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(10.dp)
    ) {
        Column(
            modifier = Modifier.padding(vertical = 12.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value, style = AppTypography.titleLarge, color = color, fontWeight = FontWeight.Bold)
            Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary)
        }
    }
}

@Composable
private fun StandalonePaymentDialog(
    onDismiss: () -> Unit,
    onConfirm: (Double, String, String?) -> Unit
) {
    var amount by remember { mutableStateOf("") }
    var method by remember { mutableStateOf("نقدي") }
    var notes by remember { mutableStateOf("") }
    val methods = listOf("نقدي", "تحويل", "بطاقة", "شيك", "تقسيط")

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("دفعة مستقلة", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { ch -> ch.isDigit() } },
                    label = { Text("المبلغ (ريال)") },
                    singleLine = true
                )
                Text("طريقة الدفع", style = AppTypography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
                    methods.forEach { m ->
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
