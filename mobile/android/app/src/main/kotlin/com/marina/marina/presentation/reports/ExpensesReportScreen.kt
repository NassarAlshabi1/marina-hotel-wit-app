package com.marina.marina.presentation.reports

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
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

/** تقرير المصروفات — UI port of `expenses_report_screen.dart`. */
@Composable
fun ExpensesReportScreen(
    onBack: () -> Unit = {},
    viewModel: ExpensesReportViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("تقرير المصروفات", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    actions = {
                        TextButton(
                            onClick = { exportExpensesPdf(context, state) },
                            enabled = state.groups.isNotEmpty()
                        ) { Text("PDF", color = if (state.groups.isNotEmpty()) AppColors.DangerColor else AppColors.TextSecondary) }
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
                        Text("النوع:", fontSize = 12.sp, color = AppColors.TextSecondary)
                        Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            FilterChip(
                                selected = state.selectedType == null,
                                onClick = { viewModel.setType(null) },
                                label = { Text("الكل", fontSize = 11.sp) }
                            )
                            state.availableTypes.forEach { type ->
                                FilterChip(
                                    selected = state.selectedType == type,
                                    onClick = { viewModel.setType(type) },
                                    label = { Text(type, fontSize = 11.sp) }
                                )
                            }
                        }
                        Spacer(modifier = Modifier.weight(1f))
                        ReportSearchButton(onClick = { viewModel.fetch() }, loading = state.isLoading)
                    }
                }

                // Summary strip (Dart _buildDetailedSummary l.1177-1364).
                item {
                    Card(
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(containerColor = AppColors.WarningColor.copy(alpha = 0.1f)),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    "إجمالي المصروفات: ${CurrencyFormatter.formatAmount(state.totalAmount)}",
                                    color = AppColors.WarningColor, fontWeight = FontWeight.Bold
                                )
                                Text(
                                    "${state.groups.sumOf { it.rows.size }} عملية",
                                    fontSize = 11.sp, color = AppColors.PrimaryColor,
                                    modifier = Modifier.background(AppColors.PrimaryLight, RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 2.dp)
                                )
                            }
                            if (state.salaryTotal > 0) {
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                                    ReportStat(
                                        "سحوبات الرواتب", CurrencyFormatter.formatAmount(state.salaryTotal),
                                        Color(0xFF7B1FA2), Modifier.weight(1f)
                                    )
                                    ReportStat(
                                        "مصروفات تشغيلية", CurrencyFormatter.formatAmount(state.operationalTotal),
                                        Color(0xFF00897B), Modifier.weight(1f)
                                    )
                                }
                            }
                        }
                    }
                }

                if (state.groups.isEmpty() && !state.isLoading) {
                    item { ReportEmptyCard("لا توجد بيانات", "لم يتم العثور على مصروفات ضمن النطاق المحدد.") }
                } else {
                    state.groups.forEach { group ->
                        item(key = "group_${group.type}") {
                            ExpenseGroupCard(group)
                        }
                    }
                }
            }
        }
    }
}

private fun typeVisual(type: String): Pair<Color, String> = when {
    type.contains("رواتب") || type.contains("سحب راتب") || type.contains("سحب من الراتب") -> Color(0xFF7B1FA2) to "👛"
    type.contains("خصم") -> Color(0xFF7B1FA2) to "➖"
    type.contains("ديزل") -> Color(0xFFFFA000) to "⛽"
    type.contains("صيانة") -> Color(0xFFF57C00) to "🔧"
    type.contains("كهرباء") || type.contains("مياه") -> Color(0xFF00897B) to "⚡"
    type.contains("مستلزمات") -> Color(0xFF3F51B5) to "📦"
    type.contains("مساعدة") -> Color(0xFFD81B60) to "🤝"
    else -> Color(0xFF6C6F8F) to "🧾"
}

@Composable
private fun ExpenseGroupCard(group: ExpenseTypeGroup) {
    val (color, icon) = typeVisual(group.type)
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
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(icon, fontSize = 16.sp)
                    Text(group.type, fontWeight = FontWeight.Bold, color = color, fontSize = 13.sp)
                    Text(
                        "${group.rows.size}", fontSize = 10.sp, color = AppColors.PrimaryColor,
                        modifier = Modifier.background(AppColors.PrimaryLight, RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 1.dp)
                    )
                }
                Text(
                    CurrencyFormatter.formatAmount(group.subtotal),
                    fontWeight = FontWeight.Bold, color = color, fontSize = 14.sp
                )
            }
            HorizontalDivider(color = AppColors.DividerColor.copy(alpha = 0.5f))
            group.rows.forEachIndexed { index, row ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "${index + 1}", fontSize = 10.sp, color = AppColors.TextSecondary,
                        modifier = Modifier
                            .background(AppColors.LightGray, RoundedCornerShape(6.dp))
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "${row.displayDate.take(10)} • ${row.type}",
                            fontSize = 10.sp, color = AppColors.TextSecondary
                        )
                        if (row.description.isNotBlank()) {
                            Text(row.description, fontSize = 11.sp, color = AppColors.TextPrimary, maxLines = 2)
                        }
                        if (row.isSalaryWithdrawal) {
                            Text("سحب راتب", fontSize = 9.sp, color = Color(0xFF7B1FA2))
                        }
                        row.employeeName?.let {
                            Text("👤 $it", fontSize = 10.sp, color = if (row.type.contains("راتب") || row.type.contains("خصم")) Color(0xFF7B1FA2) else AppColors.PrimaryColor)
                        }
                    }
                    Text(
                        CurrencyFormatter.formatAmount(row.amount),
                        color = color, fontWeight = FontWeight.Bold, fontSize = 13.sp
                    )
                }
            }
        }
    }
}

internal fun exportExpensesPdf(context: android.content.Context, state: ExpensesReportUiState) {
    val allRows = state.groups.flatMap { it.rows }
    val file = PdfExporter.buildReport(
        context = context,
        reportTitle = "تقرير المصروفات",
        periodText = "الفترة من تاريخ ${state.range.fromHotelDayKey} إلى تاريخ ${state.range.toHotelDayKey}",
        infoRows = listOf(
            "النوع" to (state.selectedType ?: "الكل"),
            "عدد السجلات" to "${allRows.size}",
            "يشمل" to "مصروفات تشغيلية + سحوبات الرواتب"
        ),
        stats = listOf(
            Triple("إجمالي المصروفات", CurrencyFormatter.formatAmount(state.totalAmount), 0xFFF57C00.toInt()),
            Triple("سحوبات الرواتب", CurrencyFormatter.formatAmount(state.salaryTotal), 0xFF7B1FA2.toInt()),
            Triple("مصروفات تشغيلية", CurrencyFormatter.formatAmount(state.operationalTotal), 0xFF00897B.toInt())
        ),
        tables = listOf(
            PdfExporter.PdfTable(
                title = "تفاصيل المصروفات",
                headers = listOf("التاريخ", "المبلغ", "النوع", "الوصف", "الموظف"),
                rows = allRows.map { row ->
                    listOf(
                        row.displayDate.take(10),
                        CurrencyFormatter.formatAmount(row.amount),
                        row.type,
                        row.description.ifBlank { "-" },
                        row.employeeName ?: if (row.isSalaryWithdrawal) "غير محدد" else "-"
                    )
                },
                totalRow = listOf("الإجمالي", CurrencyFormatter.formatAmount(state.totalAmount), "", "", ""),
                columnWeights = listOf(1.1f, 1.0f, 1.2f, 2.0f, 1.2f)
            )
        ),
        fileName = PdfExporter.generateFileName("تقرير-المصروفات")
    )
    PdfExporter.sharePdf(context, file, "تقرير المصروفات")
}
