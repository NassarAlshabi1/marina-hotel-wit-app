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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// ---------------------------------------------------------------------------
// التقرير المخزني — UI port of `inventory_report_screen.dart`
// ---------------------------------------------------------------------------

@Composable
fun InventoryReportScreen(
    onBack: () -> Unit = {},
    viewModel: InventoryReportViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("التقرير المخزني", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    actions = {
                        TextButton(
                            onClick = { exportInventoryPdf(context, state) },
                            enabled = state.rows.isNotEmpty()
                        ) { Text("PDF", color = if (state.rows.isNotEmpty()) AppColors.DangerColor else AppColors.TextSecondary) }
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
                        Text("التصنيف:", fontSize = 12.sp, color = AppColors.TextSecondary)
                        Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            FilterChip(
                                selected = state.selectedCategory == null,
                                onClick = { viewModel.setCategory(null) },
                                label = { Text("الكل", fontSize = 11.sp) }
                            )
                            state.categories.forEach { category ->
                                FilterChip(
                                    selected = state.selectedCategory == category,
                                    onClick = { viewModel.setCategory(category) },
                                    label = { Text(category, fontSize = 11.sp) }
                                )
                            }
                        }
                        Spacer(modifier = Modifier.weight(1f))
                        ReportSearchButton(onClick = { viewModel.fetch() }, loading = state.isLoading)
                    }
                }

                // Summary tiles (Dart l.283-289).
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                        ReportStat("الأصناف", "${state.rows.size}", AppColors.PrimaryColor, Modifier.weight(1f))
                        ReportStat("تحت الحد", "${state.lowStockCount}", AppColors.WarningColor, Modifier.weight(1f))
                        ReportStat("الوارد", CurrencyFormatter.formatAmount(state.totalIn), AppColors.SuccessColor, Modifier.weight(1f))
                        ReportStat("الصرف", CurrencyFormatter.formatAmount(state.totalOut), AppColors.DangerColor, Modifier.weight(1f))
                    }
                }

                if (state.rows.isEmpty() && !state.isLoading) {
                    item { ReportEmptyCard("لا توجد بيانات مخزنية", "لا توجد أصناف نشطة أو حركات ضمن الفترة المحددة.") }
                } else {
                    items(state.rows.size, key = { state.rows[it].item.id }) { index ->
                        val row = state.rows[index]
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
                                Text(
                                    if (row.isLowStock) "⚠️" else "📦",
                                    fontSize = 18.sp
                                )
                                Column(modifier = Modifier.weight(1f)) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Text(row.item.name, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                                        if (row.isLowStock) {
                                            Text(
                                                "تحت الحد", fontSize = 9.sp, color = AppColors.WarningColor,
                                                modifier = Modifier.background(AppColors.AccentSoft, RoundedCornerShape(6.dp)).padding(horizontal = 4.dp, vertical = 1.dp)
                                            )
                                        }
                                    }
                                    Text(
                                        "التصنيف: ${row.item.category ?: "غير مصنف"} • الحد الأدنى: ${row.item.minimumQuantity.toInt()} ${row.item.unit}",
                                        fontSize = 10.sp, color = AppColors.TextSecondary
                                    )
                                    Text(
                                        "وارد ${row.totalIn.toInt()} • صرف ${row.totalOut.toInt()} • تسويات ${row.totalAdjustment.toInt()} • حركات ${row.movementCount}",
                                        fontSize = 10.sp, color = AppColors.TextSecondary
                                    )
                                }
                                Text(
                                    "${row.item.currentQuantity.toInt()} ${row.item.unit}",
                                    fontWeight = FontWeight.Bold, fontSize = 14.sp,
                                    color = if (row.isLowStock) AppColors.WarningColor else AppColors.SuccessColor
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun exportInventoryPdf(context: android.content.Context, state: InventoryReportUiState) {
    val file = PdfExporter.buildReport(
        context = context,
        reportTitle = "التقرير المخزني",
        periodText = "الفترة من تاريخ ${state.range.fromHotelDayKey} إلى تاريخ ${state.range.toHotelDayKey}",
        infoRows = listOf(
            "التصنيف" to (state.selectedCategory ?: "الأصناف النشطة"),
            "عدد الأصناف" to "${state.rows.size}",
            "أصناف تحت الحد الأدنى" to "${state.lowStockCount}",
            "إجمالي الحركات" to "${state.movementCount}"
        ),
        stats = listOf(
            Triple("الأصناف", "${state.rows.size}", 0xFF242476.toInt()),
            Triple("تحت الحد", "${state.lowStockCount}", 0xFFF57C00.toInt()),
            Triple("الوارد", CurrencyFormatter.formatAmount(state.totalIn), 0xFF2E7D5B.toInt()),
            Triple("الصرف", CurrencyFormatter.formatAmount(state.totalOut), 0xFFE5484D.toInt())
        ),
        tables = listOf(
            PdfExporter.PdfTable(
                title = "الأصناف",
                headers = listOf("م", "الصنف", "التصنيف", "الرصيد", "الحد الأدنى", "وارد", "صرف", "تسويات", "الحركات"),
                rows = state.rows.mapIndexed { i, row ->
                    listOf(
                        "${i + 1}", row.item.name, row.item.category ?: "غير مصنف",
                        "${row.item.currentQuantity.toInt()} ${row.item.unit}",
                        "${row.item.minimumQuantity.toInt()}",
                        "${row.totalIn.toInt()}", "${row.totalOut.toInt()}",
                        "${row.totalAdjustment.toInt()}", "${row.movementCount}"
                    )
                },
                columnWeights = listOf(0.5f, 1.6f, 1.2f, 1.0f, 0.9f, 0.8f, 0.8f, 0.9f, 0.9f)
            )
        ),
        fileName = PdfExporter.generateFileName("التقرير-المخزني")
    )
    PdfExporter.sharePdf(context, file, "التقرير المخزني")
}

// ---------------------------------------------------------------------------
// تقرير سحبيات الرواتب — UI port of `salary_withdrawals_report_screen.dart`
// ---------------------------------------------------------------------------

@Composable
fun SalaryWithdrawalsReportScreen(
    onBack: () -> Unit = {},
    viewModel: SalaryReportViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("تقرير سحبيات الرواتب", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    actions = {
                        TextButton(
                            onClick = { exportSalaryPdf(context, state) },
                            enabled = state.rows.isNotEmpty()
                        ) { Text("PDF", color = if (state.rows.isNotEmpty()) AppColors.DangerColor else AppColors.TextSecondary) }
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
                        Text("الموظف:", fontSize = 12.sp, color = AppColors.TextSecondary)
                        Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            FilterChip(
                                selected = state.selectedEmployeeId == null,
                                onClick = { viewModel.setEmployee(null) },
                                label = { Text("الكل", fontSize = 11.sp) }
                            )
                            state.employees.take(12).forEach { (id, name) ->
                                FilterChip(
                                    selected = state.selectedEmployeeId == id,
                                    onClick = { viewModel.setEmployee(id) },
                                    label = { Text(name, fontSize = 11.sp) }
                                )
                            }
                        }
                        Spacer(modifier = Modifier.weight(1f))
                        ReportSearchButton(onClick = { viewModel.fetch() }, loading = state.isLoading)
                    }
                }

                // Summary strip (Dart l.517-558).
                item {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = Color(0xFF1976D2).copy(alpha = 0.1f)),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp).fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "سحبيات: ${state.selectedEmployeeName ?: "جميع الموظفين"} — ${state.rows.size} عملية",
                                fontSize = 12.sp, color = AppColors.PrimaryColor
                            )
                            Text(
                                "${CurrencyFormatter.formatAmount(state.totalAmount)} ريال",
                                fontWeight = FontWeight.Bold, fontSize = 15.sp, color = Color(0xFF1976D2)
                            )
                        }
                    }
                }

                if (state.rows.isEmpty() && !state.isLoading) {
                    item { ReportEmptyCard("لا توجد بيانات", "لم يتم العثور على سحبيات رواتب ضمن النطاق المحدد.") }
                } else {
                    state.groups.forEach { group ->
                        item(key = "salary_group_${group.employeeId}") {
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
                                        Text(group.employeeName, fontWeight = FontWeight.Bold, fontSize = 13.sp, color = Color(0xFF1976D2))
                                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                            Text("${group.rows.size} عملية", fontSize = 10.sp, color = AppColors.TextSecondary)
                                            Text(
                                                CurrencyFormatter.formatAmount(group.totalAmount),
                                                fontWeight = FontWeight.Bold, color = Color(0xFF7B1FA2), fontSize = 14.sp
                                            )
                                        }
                                    }
                                    HorizontalDivider(color = AppColors.DividerColor.copy(alpha = 0.5f))
                                    group.rows.forEach { row ->
                                        val w = row.withdrawal
                                        Row(
                                            modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
                                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text(if (row.isDeduction) "➖" else "👛", fontSize = 13.sp)
                                            Column(modifier = Modifier.weight(1f)) {
                                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                                    Text(
                                                        if (row.isDeduction) "خصم" else "سحب",
                                                        fontSize = 9.sp, color = if (row.isDeduction) AppColors.DangerColor else AppColors.WarningColor,
                                                        modifier = Modifier.background(
                                                            (if (row.isDeduction) AppColors.DangerColor else AppColors.WarningColor).copy(alpha = 0.12f),
                                                            RoundedCornerShape(6.dp)
                                                        ).padding(horizontal = 4.dp, vertical = 1.dp)
                                                    )
                                                    Text(
                                                        SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.US).format(Date(w.withdrawDate)),
                                                        fontSize = 10.sp, color = AppColors.TextSecondary
                                                    )
                                                }
                                                if (!w.reason.isNullOrBlank() && !w.reason!!.startsWith("exp_")) {
                                                    Text(w.reason!!, fontSize = 10.sp, color = AppColors.TextSecondary, maxLines = 1)
                                                }
                                                w.description?.let {
                                                    if (it.isNotBlank()) Text(it, fontSize = 10.sp, color = AppColors.TextSecondary, maxLines = 1)
                                                }
                                            }
                                            Text(
                                                CurrencyFormatter.formatAmount(w.amount),
                                                fontWeight = FontWeight.Bold, fontSize = 13.sp,
                                                color = if (row.isDeduction) AppColors.DangerColor else Color(0xFF7B1FA2)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun exportSalaryPdf(context: android.content.Context, state: SalaryReportUiState) {
    val isAll = state.selectedEmployeeId == null
    val file = PdfExporter.buildReport(
        context = context,
        reportTitle = "تقرير سحبيات الرواتب",
        periodText = "الفترة من تاريخ ${state.range.fromHotelDayKey} إلى تاريخ ${state.range.toHotelDayKey}",
        infoRows = listOf(
            "الموظف" to (state.selectedEmployeeName ?: "الكل"),
            "عدد السجلات" to "${state.rows.size}"
        ),
        stats = listOf(
            Triple("الإجمالي", CurrencyFormatter.formatAmount(state.totalAmount), 0xFF7B1FA2.toInt()),
            Triple("عدد العمليات", "${state.rows.size}", 0xFF1976D2.toInt())
        ),
        tables = listOf(
            PdfExporter.PdfTable(
                title = "تفاصيل السحبيات",
                headers = if (isAll) listOf("التاريخ", "المبلغ", "النوع", "الموظف", "السبب") else listOf("التاريخ", "المبلغ", "النوع", "السبب"),
                rows = state.rows.map { row ->
                    val w = row.withdrawal
                    val base = listOf(
                        SimpleDateFormat("yyyy/MM/dd", Locale.US).format(Date(w.withdrawDate)),
                        CurrencyFormatter.formatAmount(w.amount),
                        if (row.isDeduction) "خصم" else "سحب",
                        row.employeeName,
                        (w.reason?.takeIf { !it.startsWith("exp_") } ?: "-")
                    )
                    if (isAll) base else base.filterIndexed { i, _ -> i != 3 }
                },
                totalRow = if (isAll) listOf("الإجمالي", CurrencyFormatter.formatAmount(state.totalAmount), "", "", "")
                else listOf("الإجمالي", CurrencyFormatter.formatAmount(state.totalAmount), "", ""),
                columnWeights = if (isAll) listOf(1.1f, 1.0f, 0.7f, 1.3f, 1.5f) else listOf(1.1f, 1.0f, 0.7f, 1.8f)
            )
        ),
        fileName = PdfExporter.generateFileName(
            if (isAll) "تقرير-سحبيات-الرواتب" else "سحبيات-راتب-${state.selectedEmployeeName ?: ""}"
        )
    )
    PdfExporter.sharePdf(context, file, "تقرير سحبيات الرواتب")
}
