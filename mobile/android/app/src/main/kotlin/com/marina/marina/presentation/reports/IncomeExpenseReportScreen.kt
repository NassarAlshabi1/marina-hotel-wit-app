package com.marina.marina.presentation.reports

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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.util.PdfExporter

/** تقرير الدخل والمصروفات — UI port of `income_expense_report_screen.dart`. */
@Composable
fun IncomeExpenseReportScreen(
    onBack: () -> Unit = {},
    viewModel: IncomeExpenseReportViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("تقرير الدخل والمصروفات", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    actions = {
                        TextButton(onClick = {
                            PdfExporter.shareText(context, viewModel.buildCsv(), "تقرير الدخل والمصروفات", "text/csv")
                        }) { Text("CSV", color = AppColors.SuccessColor) }
                        TextButton(
                            onClick = { exportIncomeExpensePdf(context, state) },
                            enabled = state.entries.isNotEmpty()
                        ) { Text("PDF", color = if (state.entries.isNotEmpty()) AppColors.DangerColor else AppColors.TextSecondary) }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            }
        ) { padding ->
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                item {
                    ReportDateFilter(range = state.range, onChange = { viewModel.setRange(it) })
                }
                item {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        FilterChip(
                            selected = state.detailedMode,
                            onClick = { viewModel.setDetailedMode(true) },
                            label = { Text("تفصيلي", fontSize = 11.sp) }
                        )
                        FilterChip(
                            selected = !state.detailedMode,
                            onClick = { viewModel.setDetailedMode(false) },
                            label = { Text("ملخص", fontSize = 11.sp) }
                        )
                        Spacer(modifier = Modifier.weight(1f))
                        if (state.detailedMode) {
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                listOf("daily" to "يومي", "monthly" to "شهري", "yearly" to "سنوي").forEach { (key, label) ->
                                    FilterChip(
                                        selected = state.groupBy == key,
                                        onClick = { viewModel.setGroupBy(key) },
                                        label = { Text(label, fontSize = 11.sp) }
                                    )
                                }
                            }
                        }
                        ReportSearchButton(onClick = { viewModel.fetch() }, loading = state.isLoading)
                    }
                }

                // Summary stat cards (Dart l.2453-2508).
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            ReportStat("إجمالي الدخل", CurrencyFormatter.formatAmount(state.incomeTotal), Color(0xFF2E7D5B), Modifier.weight(1f))
                            ReportStat("إجمالي المصروفات", CurrencyFormatter.formatAmount(state.expenseTotal), AppColors.DangerColor, Modifier.weight(1f))
                            ReportStat("مصروفات الرواتب", CurrencyFormatter.formatAmount(state.salaryTotal), AppColors.WarningColor, Modifier.weight(1f))
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            ReportStat(
                                "صافي الربح", CurrencyFormatter.formatAmount(state.net),
                                if (state.net >= 0) Color(0xFF00897B) else AppColors.DangerColor,
                                Modifier.weight(1f), large = true
                            )
                            ReportStat("ديون مستحقة", CurrencyFormatter.formatAmount(state.unsettledDebtsAmount), Color(0xFF7B1FA2), Modifier.weight(1f), large = true)
                            ReportStat("التزام الرواتب", CurrencyFormatter.formatAmount(state.totalSalaryObligation), Color(0xFF3F51B5), Modifier.weight(1f), large = true)
                        }
                    }
                }

                // Summary mode counts (Dart _buildStatsList).
                if (!state.detailedMode) {
                    item {
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                IndicatorsRow("عدد معاملات الدخل", "${state.entries.count { it.isIncome }}")
                                IndicatorsRow("عدد معاملات المصروفات", "${state.entries.count { !it.isIncome }}")
                                IndicatorsRow("عدد معاملات الرواتب", "${state.entries.count { !it.isIncome && it.isSalary }}")
                                IndicatorsRow("حجوزات الفترة", "${state.bookingsInPeriod}")
                                IndicatorsRow("موظفون نشطون", "${state.activeEmployees}")
                            }
                        }
                    }
                }

                // Financial indicators table (Dart l.1080-1133).
                item {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text("المؤشرات المالية الرئيسية", fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor, fontSize = 13.sp)
                            IndicatorsRow(
                                "هامش الربح", "${"%.1f".format(state.profitMargin)}% ${rating(state.profitMargin, 20.0, 10.0, true)}",
                                ratingColor(state.profitMargin, 20.0, 10.0, true)
                            )
                            IndicatorsRow(
                                "نسبة المصروفات من الدخل", "${"%.1f".format(state.expenseRatio)}% ${rating(100 - state.expenseRatio, 40.0, 20.0, true)}",
                                ratingColor(100 - state.expenseRatio, 40.0, 20.0, true)
                            )
                            IndicatorsRow(
                                "نسبة الرواتب من الدخل", "${"%.1f".format(state.salaryExpenseRatio)}% ${rating(100 - state.salaryExpenseRatio, 70.0, 50.0, true)}",
                                ratingColor(100 - state.salaryExpenseRatio, 70.0, 50.0, true)
                            )
                            IndicatorsRow(
                                "قدرة تغطية الديون",
                                if (state.debtCoverage > 0) "${"%.2f".format(state.debtCoverage)}x ${rating(state.debtCoverage, 2.0, 1.0, false)}" else "غير كافٍ",
                                if (state.debtCoverage > 2) Color(0xFF2E7D5B) else if (state.debtCoverage > 1) Color(0xFFF57C00) else AppColors.DangerColor
                            )
                        }
                    }
                }

                // Detailed grouped list (Dart _buildCombinedList / grouped view).
                if (state.detailedMode) {
                    if (state.groups.isEmpty() && !state.isLoading) {
                        item { ReportEmptyCard("لا توجد بيانات", "لا يوجد دخل أو مصروفات ضمن الفترة المحددة.") }
                    } else {
                        state.groups.forEach { group ->
                            item(key = "group_${group.key}") {
                                IncomeExpenseGroupCard(group)
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun rating(value: Double, excellent: Double, good: Double, greaterIsBetter: Boolean): String = when {
    value >= excellent -> "ممتاز"
    value >= good -> "جيد"
    value > 0 -> "مقبول"
    else -> if (greaterIsBetter) "خسارة" else "مرتفع"
}

private fun ratingColor(value: Double, excellent: Double, good: Double, greaterIsBetter: Boolean): Color = when {
    value >= excellent -> Color(0xFF2E7D5B)
    value >= good -> Color(0xFFF57C00)
    value > 0 -> Color(0xFF6C6F8F)
    else -> AppColors.DangerColor
}

@Composable
private fun IndicatorsRow(label: String, value: String, valueColor: Color = AppColors.TextPrimary) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, fontSize = 11.sp, color = AppColors.TextSecondary)
        Text(value, fontSize = 11.sp, color = valueColor, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun IncomeExpenseGroupCard(group: ReportGroup) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        shape = RoundedCornerShape(12.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(group.label, fontWeight = FontWeight.Bold, fontSize = 13.sp, color = AppColors.PrimaryColor)
                Text(
                    if (group.net >= 0) "ربح: ${CurrencyFormatter.formatAmount(group.net)}" else "خسارة: ${CurrencyFormatter.formatAmount(-group.net)}",
                    fontSize = 11.sp, fontWeight = FontWeight.Bold,
                    color = if (group.net >= 0) Color(0xFF2E7D5B) else AppColors.DangerColor
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                ReportStat("الدخل", CurrencyFormatter.formatAmount(group.incomeTotal), Color(0xFF2E7D5B), Modifier.weight(1f))
                ReportStat("المصروفات", CurrencyFormatter.formatAmount(group.expenseTotal), AppColors.DangerColor, Modifier.weight(1f))
                ReportStat("الرواتب", CurrencyFormatter.formatAmount(group.salaryTotal), AppColors.WarningColor, Modifier.weight(1f))
                ReportStat(
                    "الصافي", CurrencyFormatter.formatAmount(group.net),
                    if (group.net >= 0) Color(0xFF00897B) else AppColors.DangerColor,
                    Modifier.weight(1f)
                )
            }
            HorizontalDivider(color = AppColors.DividerColor.copy(alpha = 0.5f))
            group.entries.take(30).forEach { entry ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        if (entry.isIncome) "⬇️" else if (entry.isSalary) "👥" else "⬆️",
                        fontSize = 13.sp
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(entry.description, fontSize = 11.sp, maxLines = 1)
                        Text(
                            "${java.text.SimpleDateFormat("yyyy/MM/dd", java.util.Locale.US).format(java.util.Date(entry.date))} • " +
                                when {
                                    entry.isIncome -> "دخل"
                                    entry.isSalary -> "راتب"
                                    else -> "مصروف"
                                },
                            fontSize = 9.sp, color = AppColors.TextSecondary
                        )
                    }
                    Text(
                        (if (entry.isIncome) "+" else "-") + CurrencyFormatter.formatAmount(entry.amount),
                        fontSize = 12.sp, fontWeight = FontWeight.Bold,
                        color = if (entry.isIncome) Color(0xFF2E7D5B) else AppColors.DangerColor
                    )
                }
            }
            if (group.entries.size > 30) {
                Text("... و${group.entries.size - 30} معاملة أخرى", fontSize = 10.sp, color = AppColors.TextSecondary)
            }
        }
    }
}

internal fun exportIncomeExpensePdf(context: android.content.Context, state: IncomeExpenseReportUiState) {
    val file = PdfExporter.buildReport(
        context = context,
        reportTitle = "تقرير الدورة المالية الشامل",
        periodText = "الفترة من تاريخ ${state.range.fromHotelDayKey} إلى تاريخ ${state.range.toHotelDayKey}",
        infoRows = listOf(
            "عدد المعاملات" to "${state.entries.size}",
            "حجوزات الفترة" to "${state.bookingsInPeriod}",
            "موظفون نشطون" to "${state.activeEmployees}"
        ),
        stats = listOf(
            Triple("إجمالي الإيرادات", CurrencyFormatter.formatAmount(state.incomeTotal), 0xFF2E7D5B.toInt()),
            Triple("إجمالي المصروفات", CurrencyFormatter.formatAmount(state.expenseTotal), 0xFFE5484D.toInt()),
            Triple("مصروفات الرواتب", CurrencyFormatter.formatAmount(state.salaryTotal), 0xFFF57C00.toInt()),
            Triple("صافي الربح", CurrencyFormatter.formatAmount(state.net), if (state.net >= 0) 0xFF00897B.toInt() else 0xFFE5484D.toInt())
        ),
        tables = listOf(
            PdfExporter.PdfTable(
                title = "تفاصيل الإيرادات",
                headers = listOf("#", "التاريخ", "الغرفة", "طريقة الدفع", "نوع الإيراد", "المبلغ"),
                rows = state.entries.filter { it.isIncome }.mapIndexed { i, e ->
                    listOf(
                        "${i + 1}",
                        java.text.SimpleDateFormat("yyyy/MM/dd", java.util.Locale.US).format(java.util.Date(e.date)),
                        e.roomNumber.ifBlank { "-" },
                        translateMethod(e.paymentMethod).ifBlank { "-" },
                        e.revenueType.ifBlank { "إقامة" },
                        CurrencyFormatter.formatAmount(e.amount)
                    )
                },
                totalRow = listOf("", "", "", "", "الإجمالي", CurrencyFormatter.formatAmount(state.incomeTotal)),
                columnWeights = listOf(0.5f, 1.3f, 0.8f, 1.1f, 1.1f, 1.2f)
            ),
            PdfExporter.PdfTable(
                title = "تفاصيل المصروفات",
                headers = listOf("#", "التاريخ", "النوع", "الوصف", "المبلغ"),
                rows = state.entries.filter { !it.isIncome }.mapIndexed { i, e ->
                    listOf(
                        "${i + 1}",
                        java.text.SimpleDateFormat("yyyy/MM/dd", java.util.Locale.US).format(java.util.Date(e.date)),
                        if (e.isSalary) "رواتب" else e.revenueType,
                        e.description,
                        CurrencyFormatter.formatAmount(e.amount)
                    )
                },
                totalRow = listOf("", "", "", "الإجمالي", CurrencyFormatter.formatAmount(state.expenseTotal)),
                columnWeights = listOf(0.5f, 1.3f, 1.2f, 2.2f, 1.2f)
            )
        ),
        fileName = PdfExporter.generateFileName("تقرير-الدورة-المالية-الشامل")
    )
    PdfExporter.sharePdf(context, file, "تقرير الدخل والمصروفات")
}
