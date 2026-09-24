package com.marina.marina.presentation.reports

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.Assignment
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.ManageSearch
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.PieChart
import androidx.compose.material.icons.outlined.ReceiptLong
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.StackedLineChart
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Today
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.presentation.common.AppSnackbarHost
import com.marina.marina.presentation.common.ColoredSnackbarVisuals
import com.marina.marina.presentation.common.SnackColors
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import java.text.DecimalFormat

/**
 * التقارير — port 1:1 من `reports_screen.dart` (فرع
 * feat/cloudflare-sync-execution):
 * - ترويسة: بحث شامل / تحديث / مزامنة (triggerManualCloudflareSync).
 * - التقارير المالية (6 اختصارات) + تقارير المخاطر والمتابعة (الديون).
 * - مؤشرات سريعة: ملخص مالي لليوم الفندقي (إيرادات/مصروفات/صافي).
 * - الرسوم الثلاثة الحقيقية: إشغال آخر 7 أيام فندقية، إيرادات مقابل
 *   مصروفات الشهر الفندقي، أعلى الغرف إشغالاً (آخر 30 يوم فندقي).
 */

private val hubMoneyFmt = DecimalFormat("#,##0")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportsScreen(
    onOpenReport: (String) -> Unit = {},
    onOpenSearch: () -> Unit = {},
    viewModel: ReportsHubViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            snackbarHostState.showSnackbar(
                ColoredSnackbarVisuals(
                    message = event.message,
                    containerColor = when (event.kind) {
                        ReportsHubEvent.EventKind.SUCCESS -> SnackColors.green
                        ReportsHubEvent.EventKind.WARNING -> SnackColors.orange
                        ReportsHubEvent.EventKind.ERROR -> SnackColors.red
                    }
                )
            )
        }
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { AppSnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("التقارير", style = AppTypography.titleLarge) },
                    actions = {
                        // ✅ نُقل من ترويسة لوحة التحكم (dashboard_screen.dart) إلى هنا —
                        // قسم التقارير هو المكان الطبيعي لنقطة دخول البحث الشامل.
                        IconButton(onClick = onOpenSearch) {
                            Icon(Icons.Outlined.ManageSearch, contentDescription = "بحث شامل")
                        }
                        IconButton(onClick = { viewModel.loadCharts() }) {
                            Icon(Icons.Outlined.Refresh, contentDescription = "تحديث")
                        }
                        IconButton(onClick = { viewModel.runManualSync() }) {
                            Icon(Icons.Outlined.Sync, contentDescription = "مزامنة")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            }
        ) { padding ->
            when {
                state.isLoading -> Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center
                ) { CircularProgressIndicator() }
                else -> LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(horizontal = 10.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    // ─── التقارير المالية ───
                    item { SectionHeader("التقارير المالية") }
                    item {
                        ReportShortcut(Icons.Outlined.ReceiptLong, "تقرير دفوعات النزلاء", Color(0xFF4CAF50)) { onOpenReport("payments_report") }
                    }
                    item {
                        ReportShortcut(Icons.Outlined.Assignment, "تقرير تفصيلي - الأيام والمدفوعات", Color(0xFF3F51B5)) { onOpenReport("guest_detail_report") }
                    }
                    item {
                        ReportShortcut(Icons.Outlined.AccountBalanceWallet, "تقرير المصروفات", Color(0xFFFF9800)) { onOpenReport("expenses_report") }
                    }
                    item {
                        ReportShortcut(Icons.Outlined.StackedLineChart, "تقرير الدخل والخرج", Color(0xFF009688)) { onOpenReport("income_expense_report") }
                    }
                    item {
                        ReportShortcut(Icons.Outlined.Payments, "تقرير سحبيات الرواتب", Color(0xFF2196F3)) { onOpenReport("salary_report") }
                    }
                    item {
                        ReportShortcut(Icons.Outlined.Inventory2, "التقرير المخزني", Color(0xFF795548)) { onOpenReport("inventory_report") }
                    }

                    // ─── تقارير المخاطر والمتابعة ───
                    item { SectionHeader("تقارير المخاطر والمتابعة") }
                    item {
                        ReportShortcut(Icons.Outlined.PieChart, "تقرير الديون", Color(0xFF9C27B0)) { onOpenReport("debts_report") }
                    }

                    // ─── مؤشرات سريعة ───
                    item { SectionHeader("مؤشرات سريعة") }
                    item { QuickFinancialSummary(state = state) }

                    // ─── الرسوم الثلاثة ───
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            if (state.loadError != null) {
                                ErrorRetryCard(message = state.loadError!!, onRetry = { viewModel.loadCharts() })
                            }
                            Text("الإشغال اليومي (آخر 7 أيام)", fontWeight = FontWeight.SemiBold, fontSize = 11.sp, color = AppColors.TextPrimary)
                            SimpleBarChart(values = state.dailyOccupancy.map { it.toDouble() }, barColor = Color(0xFF009688))
                            Text("الإيرادات مقابل المصروفات (الشهر)", fontWeight = FontWeight.SemiBold, fontSize = 11.sp, color = AppColors.TextPrimary)
                            SimpleBarChart(values = listOf(state.monthIncome, state.monthExpense), barColor = null)
                            Text("أعلى الغرف إشغالاً (آخر 30 يوم فندقي)", fontWeight = FontWeight.SemiBold, fontSize = 11.sp, color = AppColors.TextPrimary)
                            SimpleBarChart(values = state.topRooms.map { it.second.toDouble() }, barColor = Color(0xFF2196F3))
                        }
                    }
                }
            }
        }
    }
}

/** ترويسة قسم — نظير نص Dart العريض fontSize 13. */
@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        fontWeight = FontWeight.Bold,
        fontSize = 13.sp,
        color = AppColors.TextPrimary,
        modifier = Modifier.padding(horizontal = 4.dp)
    )
}

/** اختصار تقرير — نظير `_ReportShortcut` (Card + ListTile + دائرة أيقونة). */
@Composable
private fun ReportShortcut(icon: ImageVector, label: String, color: Color, onTap: () -> Unit) {
    Card(
        elevation = CardDefaults.cardElevation(defaultElevation = 0.5.dp),
        shape = RoundedCornerShape(10.dp),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onTap)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .background(color.copy(alpha = 0.12f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp), tint = color)
            }
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                label,
                fontWeight = FontWeight.SemiBold,
                fontSize = 12.sp,
                color = AppColors.TextPrimary,
                modifier = Modifier.weight(1f)
            )
            Text("›", color = AppColors.TextSecondary, fontSize = 14.sp)
        }
    }
}

/** ملخص مالي سريع — نظير `_buildQuickFinancialSummary` + `_buildFinIndicator`. */
@Composable
private fun QuickFinancialSummary(state: ReportsHubUiState) {
    val net = state.income - state.expenses
    Card(
        elevation = CardDefaults.cardElevation(defaultElevation = 0.5.dp),
        shape = RoundedCornerShape(10.dp),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            // عنوان اليوم الفندقي
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Today, contentDescription = null, modifier = Modifier.size(12.dp), tint = Color(0xFF9E9E9E))
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    "اليوم الفندقي: ${state.hotelDayKey}",
                    fontSize = 9.sp,
                    color = Color(0xFF9E9E9E),
                    fontWeight = FontWeight.Bold
                )
            }
            Spacer(modifier = Modifier.height(6.dp))
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                FinIndicator("الإيرادات", state.income, Color(0xFF4CAF50), Modifier.weight(1f))
                Box(modifier = Modifier.width(1.dp).height(36.dp).background(Color(0xFFEEEEEE)))
                FinIndicator("المصروفات", state.expenses, Color(0xFFF44336), Modifier.weight(1f))
                Box(modifier = Modifier.width(1.dp).height(36.dp).background(Color(0xFFEEEEEE)))
                FinIndicator("صافي", net, if (net >= 0) Color(0xFF009688) else Color(0xFFFF9800), Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun FinIndicator(label: String, value: Double, color: Color, modifier: Modifier = Modifier) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(hubMoneyFmt.format(value), fontWeight = FontWeight.Bold, fontSize = 14.sp, color = color)
        Spacer(modifier = Modifier.height(2.dp))
        Text(label, fontSize = 10.sp, color = Color(0xFF9E9E9E))
    }
}

/** بطاقة خطأ مع إعادة المحاولة — نظير EmptyState + زر «إعادة المحاولة». */
@Composable
private fun ErrorRetryCard(message: String, onRetry: () -> Unit) {
    Card(
        shape = RoundedCornerShape(10.dp),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = SnackColors.red, modifier = Modifier.size(28.dp))
            Spacer(modifier = Modifier.height(6.dp))
            Text("تعذر تحميل التقارير", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = AppColors.TextPrimary)
            Text(message, fontSize = 11.sp, color = AppColors.TextSecondary, textAlign = TextAlign.Center)
            Spacer(modifier = Modifier.height(8.dp))
            Button(onClick = onRetry) {
                Icon(Icons.Outlined.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("إعادة المحاولة")
            }
        }
    }
}

/**
 * رسم أعمدة بسيط (نظير BarChart في Dart: barGroups فقط بلا شبكة ولا عناوين
 * محاور) — العمود الأول [green] للإيراد والثاني [red] للمصروف عند
 * [barColor] = null (رسم الإيرادات/المصروفات)، وإلا لون موحد.
 */
@Composable
private fun SimpleBarChart(values: List<Double>, barColor: Color?, modifier: Modifier = Modifier) {
    val incomeColor = Color(0xFF4CAF50)
    val expenseColor = Color(0xFFF44336)
    Box(modifier = modifier.fillMaxWidth().height(150.dp)) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            if (values.isEmpty()) return@Canvas
            val maxValue = (values.maxOrNull() ?: 1.0).coerceAtLeast(1.0)
            val slot = size.width / values.size
            val barWidth = if (values.size <= 2) 34.dp.toPx() else 16.dp.toPx()
            values.forEachIndexed { index, value ->
                val barHeight = (value / maxValue * size.height * 0.92).toFloat()
                val left = slot * index + (slot - barWidth) / 2
                drawRoundRect(
                    color = barColor ?: if (index == 0) incomeColor else expenseColor,
                    topLeft = Offset(left, size.height - barHeight),
                    size = Size(barWidth, barHeight),
                    cornerRadius = CornerRadius(6.dp.toPx(), 6.dp.toPx())
                )
            }
        }
    }
}
