package com.marina.marina.presentation.reports

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
import com.marina.marina.components.SidebarMenuButton
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun ReportsScreen(
    viewModel: ReportsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var selectedTab by remember { mutableIntStateOf(0) }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("التقارير", style = AppTypography.titleLarge) },
                    navigationIcon = { SidebarMenuButton() },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 16.dp)
            ) {
                // Date-range presets (hotel-day based, like the Flutter ReportDateFilterWidget).
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(
                        "today" to "اليوم",
                        "week" to "الأسبوع",
                        "month" to "الشهر",
                        "all" to "الكل"
                    ).forEach { (key, label) ->
                        FilterChip(
                            selected = state.range == key,
                            onClick = { viewModel.setRange(key) },
                            label = { Text(label, fontSize = 12.sp) }
                        )
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                // Financial quick summary.
                Card(
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = Color.Transparent),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Box(
                        modifier = Modifier
                            .background(
                                Brush.horizontalGradient(
                                    if (state.summary.net >= 0)
                                        listOf(AppColors.PrimaryColor, AppColors.PrimaryDark)
                                    else listOf(AppColors.DangerColor, Color(0xFFB93338))
                                ),
                                RoundedCornerShape(12.dp)
                            )
                            .padding(16.dp)
                            .fillMaxWidth()
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                "الملخص المالي — ${state.rangeLabel}",
                                style = AppTypography.titleSmall,
                                color = Color.White
                            )
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                SummaryCell("الإيرادات", "${state.summary.totalIncome.toInt()}", Color(0xFF9EE6C0))
                                SummaryCell("المصروفات", "${state.summary.totalExpenses.toInt()}", Color(0xFFFFB4A9))
                                SummaryCell(
                                    if (state.summary.net >= 0) "الصافي" else "العجز",
                                    "${state.summary.net.toInt()}",
                                    if (state.summary.net >= 0) Color.White else Color(0xFFFFD7D2)
                                )
                            }
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(
                                    "حجوزات نشطة: ${state.summary.activeBookings}",
                                    style = AppTypography.labelSmall,
                                    color = Color.White.copy(alpha = 0.85f)
                                )
                                Text(
                                    "ديون معلقة: ${state.summary.unsettledDebtsTotal.toInt()} ريال",
                                    style = AppTypography.labelSmall,
                                    color = Color.White.copy(alpha = 0.85f)
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                TabRow(selectedTabIndex = selectedTab) {
                    Tab(selected = selectedTab == 0, onClick = { selectedTab = 0 }, text = { Text("المدفوعات") })
                    Tab(selected = selectedTab == 1, onClick = { selectedTab = 1 }, text = { Text("المصروفات") })
                }

                Spacer(modifier = Modifier.height(10.dp))

                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        "تعذر تحميل التقارير: ${state.error}",
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor
                    )
                    selectedTab == 0 -> PaymentsReportList(state)
                    else -> ExpensesReportList(state)
                }
            }
        }
    }
}

@Composable
private fun PaymentsReportList(state: ReportsUiState) {
    if (state.paymentRows.isEmpty()) {
        Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
            Text("لا توجد مدفوعات في هذه الفترة", style = AppTypography.bodyLarge, color = AppColors.TextSecondary)
        }
        return
    }
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(bottom = 24.dp)
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
                    Text("الإجمالي: ${state.paymentsTotal.toInt()} ريال", style = AppTypography.titleSmall, fontWeight = FontWeight.Bold)
                    Text("${state.paymentRows.size} دفعة", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
                }
            }
        }
        items(state.paymentRows) { row ->
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
                    Column(modifier = Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            ReportBadge(row.roomNumber, AppColors.PrimaryLight, AppColors.PrimaryColor)
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(row.guestName, style = AppTypography.bodyMedium, fontWeight = FontWeight.SemiBold)
                        }
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            "${row.method} • ${row.hotelDayKey}",
                            style = AppTypography.labelSmall,
                            color = AppColors.TextSecondary
                        )
                    }
                    Text(
                        "${row.amount.toInt()} ريال",
                        style = AppTypography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.SuccessColor
                    )
                }
            }
        }
    }
}

@Composable
private fun ExpensesReportList(state: ReportsUiState) {
    if (state.expenseGroups.isEmpty()) {
        Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
            Text("لا توجد مصروفات في هذه الفترة", style = AppTypography.bodyLarge, color = AppColors.TextSecondary)
        }
        return
    }
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(bottom = 24.dp)
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
                    Text("الإجمالي: ${state.expensesTotal.toInt()} ريال", style = AppTypography.titleSmall, fontWeight = FontWeight.Bold)
                    Text("${state.expenseGroups.sumOf { it.count }} عملية", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
                }
            }
        }
        items(state.expenseGroups) { group ->
            Card(
                colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                shape = RoundedCornerShape(10.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier.padding(14.dp).fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(group.type, style = AppTypography.titleSmall, fontWeight = FontWeight.Bold)
                        Text("${group.count} عملية", style = AppTypography.labelSmall, color = AppColors.TextSecondary)
                    }
                    Text(
                        "${group.total.toInt()} ريال",
                        style = AppTypography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.DangerColor
                    )
                }
                // Share bar for the group within total expenses.
                if (state.expensesTotal > 0) {
                    LinearProgressIndicator(
                        progress = { (group.total / state.expensesTotal).toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier.padding(horizontal = 14.dp).padding(bottom = 12.dp).fillMaxWidth().height(5.dp),
                        color = AppColors.DangerColor,
                        trackColor = AppColors.LightGray
                    )
                }
            }
        }
    }
}

@Composable
private fun SummaryCell(label: String, value: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = AppTypography.titleLarge, fontWeight = FontWeight.Bold, color = color)
        Text(label, style = AppTypography.labelSmall, color = Color.White.copy(alpha = 0.85f))
    }
}

@Composable
private fun ReportBadge(text: String, background: Color, textColor: Color) {
    Box(
        modifier = Modifier
            .background(background, RoundedCornerShape(6.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp)
    ) {
        Text(text, fontSize = 11.sp, color = textColor, fontWeight = FontWeight.SemiBold)
    }
}
