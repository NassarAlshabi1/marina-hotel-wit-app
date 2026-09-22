package com.marina.marina.presentation.reports

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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

/** تقرير الديون — UI port of `debts_report_screen.dart`. */
@Composable
fun DebtsReportScreen(
    onBack: () -> Unit = {},
    viewModel: DebtsReportViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("تقرير الديون", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    actions = {
                        TextButton(
                            onClick = { exportDebtsPdf(context, state) },
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
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        ReportSearchButton(onClick = { viewModel.fetch() }, loading = state.isLoading, label = "تحديث")
                    }
                }

                // Summary chips (Dart l.529-572).
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        ReportStat("إجمالي الديون", CurrencyFormatter.formatAmount(state.totalDebt), AppColors.DangerColor, Modifier.weight(1f))
                        ReportStat("المدفوعة", CurrencyFormatter.formatAmount(state.totalPaid), AppColors.SuccessColor, Modifier.weight(1f))
                        ReportStat("المتبقية", CurrencyFormatter.formatAmount(state.totalRemaining), AppColors.WarningColor, Modifier.weight(1f))
                        ReportStat("سجلات", "${state.rows.size}", AppColors.PrimaryColor, Modifier.weight(1f))
                    }
                }

                // Guest summary table (Dart l.591-620).
                if (state.guestSummaries.isNotEmpty()) {
                    item {
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text("ملخص حسب النزلاء", fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor, fontSize = 13.sp)
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text("النزيل", fontSize = 10.sp, color = AppColors.TextSecondary, modifier = Modifier.weight(1.2f))
                                    Text("الدين", fontSize = 10.sp, color = AppColors.TextSecondary, modifier = Modifier.weight(1f))
                                    Text("المدفوع", fontSize = 10.sp, color = AppColors.TextSecondary, modifier = Modifier.weight(1f))
                                    Text("المتبقي", fontSize = 10.sp, color = AppColors.TextSecondary, modifier = Modifier.weight(1f))
                                }
                                HorizontalDivider(color = AppColors.DividerColor.copy(alpha = 0.5f))
                                state.guestSummaries.forEach { guest ->
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                        Text(guest.guestName, fontSize = 11.sp, modifier = Modifier.weight(1.2f), maxLines = 1)
                                        Text(CurrencyFormatter.formatAmount(guest.totalDebt), fontSize = 11.sp, modifier = Modifier.weight(1f))
                                        Text(CurrencyFormatter.formatAmount(guest.paid), fontSize = 11.sp, color = AppColors.SuccessColor, modifier = Modifier.weight(1f))
                                        Text(CurrencyFormatter.formatAmount(guest.remaining), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = if (guest.remaining > 0) AppColors.DangerColor else AppColors.SuccessColor, modifier = Modifier.weight(1f))
                                    }
                                }
                            }
                        }
                    }
                }

                // Details records (Dart l.622-697).
                if (state.rows.isEmpty() && !state.isLoading) {
                    item { ReportEmptyCard("لا توجد بيانات", "لم يتم العثور على ديون ضمن النطاق المحدد.") }
                } else {
                    items(state.rows.size, key = { state.rows[it].id }) { index ->
                        val debt = state.rows[index]
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                            shape = RoundedCornerShape(10.dp),
                            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(debt.guestName, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                                    Text(
                                        if (debt.isSettled) "مسدد" else "غير مسدد",
                                        fontSize = 10.sp,
                                        color = if (debt.isSettled) AppColors.SuccessColor else AppColors.DangerColor,
                                        modifier = Modifier.background(
                                            (if (debt.isSettled) AppColors.SuccessColor else AppColors.DangerColor).copy(alpha = 0.12f),
                                            RoundedCornerShape(6.dp)
                                        ).padding(horizontal = 6.dp, vertical = 2.dp)
                                    )
                                }
                                if (debt.debtReason.isNotBlank()) Text("السبب: ${debt.debtReason}", fontSize = 11.sp, color = AppColors.TextSecondary)
                                Text(
                                    "التسجيل: ${if (debt.dateRecorded.isNotBlank()) debt.dateRecorded.take(10) else debt.paymentDate.take(10)} • الدفع: ${debt.paymentDate.take(10)}",
                                    fontSize = 10.sp, color = AppColors.TextSecondary
                                )
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text("الدين: ${CurrencyFormatter.formatAmount(debt.totalAmount)}", fontSize = 11.sp)
                                    Text("المدفوع: ${CurrencyFormatter.formatAmount(debt.paidAmount)}", fontSize = 11.sp, color = AppColors.SuccessColor)
                                    Text(
                                        "المتبقي: ${CurrencyFormatter.formatAmount(debt.remainingAmount)}",
                                        fontSize = 11.sp, fontWeight = FontWeight.Bold,
                                        color = if (debt.remainingAmount > 0) AppColors.DangerColor else AppColors.SuccessColor
                                    )
                                }
                                debt.note?.let { if (it.isNotBlank()) Text(it, fontSize = 10.sp, color = AppColors.TextSecondary, maxLines = 2) }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun exportDebtsPdf(context: android.content.Context, state: DebtsReportUiState) {
    val settledPercent = if (state.totalDebt > 0) (state.totalPaid / state.totalDebt * 100).toInt() else 0
    val file = PdfExporter.buildReport(
        context = context,
        reportTitle = "تقرير الديون",
        periodText = "الفترة من تاريخ ${state.range.fromHotelDayKey} إلى تاريخ ${state.range.toHotelDayKey}",
        infoRows = listOf(
            "عدد السجلات" to "${state.rows.size}",
            "عدد النزلاء" to "${state.guestSummaries.size}",
            "مسدد" to "${state.settledCount} سجل",
            "غير مسدد" to "${state.unsettledCount} سجل"
        ),
        stats = listOf(
            Triple("إجمالي الديون", CurrencyFormatter.formatAmount(state.totalDebt), 0xFFE5484D.toInt()),
            Triple("المدفوع", "${CurrencyFormatter.formatAmount(state.totalPaid)} ($settledPercent%)", 0xFF2E7D5B.toInt()),
            Triple("المتبقي", CurrencyFormatter.formatAmount(state.totalRemaining), 0xFFF57C00.toInt())
        ),
        tables = listOf(
            PdfExporter.PdfTable(
                title = "ملخص حسب النزلاء",
                headers = listOf("النزيل", "إجمالي الدين", "المدفوع", "المتبقي"),
                rows = state.guestSummaries.map {
                    listOf(it.guestName, CurrencyFormatter.formatAmount(it.totalDebt), CurrencyFormatter.formatAmount(it.paid), CurrencyFormatter.formatAmount(it.remaining))
                },
                columnWeights = listOf(1.6f, 1.1f, 1.1f, 1.1f)
            ),
            PdfExporter.PdfTable(
                title = "تفاصيل السجلات",
                headers = listOf("#", "النزيل", "التسجيل", "الإجمالي", "المدفوع", "المتبقي", "الحالة"),
                rows = state.rows.mapIndexed { i, d ->
                    listOf(
                        "${i + 1}", d.guestName,
                        (if (d.dateRecorded.isNotBlank()) d.dateRecorded else d.paymentDate).take(10),
                        CurrencyFormatter.formatAmount(d.totalAmount),
                        CurrencyFormatter.formatAmount(d.paidAmount),
                        CurrencyFormatter.formatAmount(d.remainingAmount),
                        if (d.isSettled) "مسدد" else "غير مسدد"
                    )
                },
                totalRow = listOf("", "الإجمالي", "", CurrencyFormatter.formatAmount(state.totalDebt), CurrencyFormatter.formatAmount(state.totalPaid), CurrencyFormatter.formatAmount(state.totalRemaining), ""),
                columnWeights = listOf(0.5f, 1.5f, 1.0f, 1.0f, 1.0f, 1.0f, 0.9f)
            )
        ),
        fileName = PdfExporter.generateFileName("تقرير-الديون")
    )
    PdfExporter.sharePdf(context, file, "تقرير الديون")
}
