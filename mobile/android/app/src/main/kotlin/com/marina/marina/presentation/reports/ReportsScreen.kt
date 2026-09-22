package com.marina.marina.presentation.reports

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

/**
 * التقارير — 1:1 port of `reports_screen.dart` (hub):
 * quick indicators (اليوم الفندقي + income/expenses/net, occupancy,
 * unsettled debts) + the six report shortcuts + تقرير الديون.
 */
@Composable
fun ReportsScreen(
    onOpenReport: (String) -> Unit = {},
    viewModel: ReportsHubViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("التقارير", style = AppTypography.titleLarge) },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            }
        ) { padding ->
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Quick financial summary card (Dart l.399-454).
                item {
                    Card(
                        shape = RoundedCornerShape(14.dp),
                        colors = CardDefaults.cardColors(containerColor = Color.Transparent),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(
                            modifier = Modifier
                                .background(
                                    Brush.verticalGradient(listOf(AppColors.PrimaryColor, AppColors.PrimaryDark)),
                                    RoundedCornerShape(14.dp)
                                )
                                .padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("مؤشرات سريعة", color = Color.White, fontWeight = FontWeight.Bold)
                                Text("اليوم الفندقي: ${state.hotelDayKey}", color = Color(0xFFFFE082), fontSize = 11.sp)
                            }
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                HubStat("الإيرادات", CurrencyFormatter.formatAmount(state.income), Color(0xFF9EE6C0), Modifier.weight(1f))
                                HubStat("المصروفات", CurrencyFormatter.formatAmount(state.expenses), Color(0xFFFFB4A9), Modifier.weight(1f))
                                HubStat(
                                    "صافي", CurrencyFormatter.formatAmount(state.net),
                                    if (state.net >= 0) Color(0xFF80CBC4) else Color(0xFFFFCC80),
                                    Modifier.weight(1f)
                                )
                            }
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                HubStat("الإشغال", "${state.occupancyPercent}%", Color(0xFFB39DDB), Modifier.weight(1f))
                                HubStat("حجوزات نشطة", "${state.activeBookings}", Color(0xFF64B5F6), Modifier.weight(1f))
                                HubStat(
                                    "ديون غير مسددة", "${state.unsettledDebts}",
                                    if (state.unsettledDebts > 0) Color(0xFFFFB4A9) else Color(0xFF9EE6C0),
                                    Modifier.weight(1f)
                                )
                            }
                        }
                    }
                }

                item {
                    Text("التقارير المالية", style = AppTypography.titleMedium, fontWeight = FontWeight.Bold, color = AppColors.TextPrimary)
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                        ReportShortcut("تقرير دفوعات النزلاء", "🧾", Color(0xFF2E7D5B), Modifier.weight(1f)) { onOpenReport("payments_report") }
                        ReportShortcut("تقرير تفصيلي - الأيام والمدفوعات", "📋", Color(0xFF3F51B5), Modifier.weight(1f)) { onOpenReport("guest_detail_report") }
                    }
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                        ReportShortcut("تقرير المصروفات", "💰", Color(0xFFF57C00), Modifier.weight(1f)) { onOpenReport("expenses_report") }
                        ReportShortcut("تقرير الدخل والخرج", "📈", Color(0xFF00897B), Modifier.weight(1f)) { onOpenReport("income_expense_report") }
                    }
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                        ReportShortcut("تقرير سحبيات الرواتب", "💳", Color(0xFF1976D2), Modifier.weight(1f)) { onOpenReport("salary_report") }
                        ReportShortcut("التقرير المخزني", "📦", Color(0xFF795548), Modifier.weight(1f)) { onOpenReport("inventory_report") }
                    }
                }

                item {
                    Text("تقارير المخاطر والمتابعة", style = AppTypography.titleMedium, fontWeight = FontWeight.Bold, color = AppColors.TextPrimary)
                }
                item {
                    ReportShortcut("تقرير الديون", "📊", Color(0xFF7B1FA2), Modifier.fillMaxWidth()) { onOpenReport("debts_report") }
                }
            }
        }
    }
}

@Composable
private fun HubStat(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .background(Color.White.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Text(label, color = Color.White.copy(alpha = 0.8f), fontSize = 9.sp)
    }
}

@Composable
private fun ReportShortcut(
    title: String,
    icon: String,
    color: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Card(
        modifier = modifier.clickable(onClick = onClick).height(80.dp),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.1f))
    ) {
        Column(
            modifier = Modifier.padding(10.dp).fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(icon, fontSize = 20.sp)
            Text(title, fontWeight = FontWeight.Bold, color = color, fontSize = 11.sp, textAlign = TextAlign.Center, maxLines = 2)
        }
    }
}
