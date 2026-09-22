package com.marina.marina.presentation.reports

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.util.PdfExporter

/** تقرير دفوعات النزلاء — UI port of `payments_report_screen.dart`. */
@Composable
fun PaymentsReportScreen(
    onBack: () -> Unit = {},
    viewModel: PaymentsReportViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("تقرير دفوعات النزلاء", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    actions = {
                        TextButton(
                            onClick = { exportPaymentsPdf(context, state) },
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
                        Text("الغرفة:", fontSize = 12.sp, color = AppColors.TextSecondary)
                        Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            FilterChip(
                                selected = state.selectedRoom == null,
                                onClick = { viewModel.setRoom(null) },
                                label = { Text("الكل", fontSize = 11.sp) }
                            )
                            state.rooms.forEach { room ->
                                FilterChip(
                                    selected = state.selectedRoom == room,
                                    onClick = { viewModel.setRoom(room) },
                                    label = { Text(room, fontSize = 11.sp) }
                                )
                            }
                        }
                        Spacer(modifier = Modifier.weight(1f))
                        ReportSearchButton(onClick = { viewModel.fetch() }, loading = state.isLoading)
                    }
                }

                // Summary card (Dart l.564-618) — 4 tiles.
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            ReportStat("مدفوعات الغرفة", CurrencyFormatter.formatAmount(state.totalRoomPaid), Color(0xFF2E7D5B), Modifier.weight(1f))
                            ReportStat("مدفوعات أخرى", CurrencyFormatter.formatAmount(state.totalOtherPaid), Color(0xFF00897B), Modifier.weight(1f))
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            ReportStat("إجمالي المدفوعات", CurrencyFormatter.formatAmount(state.totalAll), AppColors.PrimaryColor, Modifier.weight(1f), large = true)
                            ReportStat(
                                "المبلغ المتبقي", CurrencyFormatter.formatAmount(state.totalRemaining),
                                if (state.totalRemaining > 0) AppColors.DangerColor else AppColors.SuccessColor,
                                Modifier.weight(1f), large = true
                            )
                        }
                    }
                }

                if (state.rows.isEmpty() && !state.isLoading) {
                    item {
                        ReportEmptyCard("لا توجد بيانات", "لم يتم العثور على دفوعات ضمن النطاق المحدد.")
                    }
                } else {
                    items(state.rows, key = { it.payment.id }) { row ->
                        PaymentReportCard(row)
                    }
                }
            }
        }
    }
}

@Composable
private fun PaymentReportCard(row: PaymentReportRow) {
    val payment = row.payment
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
                Text(
                    payment.paymentDate.take(16).replace("T", " "),
                    fontSize = 11.sp, color = AppColors.TextSecondary, fontWeight = FontWeight.SemiBold
                )
                Text(
                    "${CurrencyFormatter.formatAmount(payment.amount)} ريال",
                    color = AppColors.SuccessColor, fontWeight = FontWeight.Bold, fontSize = 15.sp
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("🏠 ${row.roomNumber}", fontSize = 11.sp, color = AppColors.PrimaryColor)
                Text("👤 ${row.payerName}", fontSize = 11.sp, color = AppColors.TextSecondary, modifier = Modifier.weight(1f))
                row.bookingCode?.let {
                    Text("#$it", fontSize = 10.sp, color = AppColors.TextSecondary)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(translateMethod(payment.paymentMethod), fontSize = 10.sp, color = AppColors.TextSecondary)
            }
        }
    }
}

internal fun translateMethod(method: String): String = when {
    method.contains("cash", true) || method.contains("نقد") -> "نقداً"
    method.contains("card", true) || method.contains("بطاق") -> "بطاقة"
    method.contains("transfer", true) || method.contains("تحويل") -> "تحويل"
    method.contains("check", true) || method.contains("شيك") -> "شيك"
    else -> method
}

internal fun exportPaymentsPdf(context: android.content.Context, state: PaymentsReportUiState) {
    val roomLabel = state.selectedRoom ?: "الكل"
    val file = PdfExporter.buildReport(
        context = context,
        reportTitle = "مدفوعات النزلاء",
        periodText = "الفترة من تاريخ ${state.range.fromHotelDayKey} إلى تاريخ ${state.range.toHotelDayKey}",
        infoRows = listOf("الغرفة" to roomLabel, "عدد الدفعات" to "${state.rows.size}"),
        stats = listOf(
            Triple("مدفوعات الغرفة", CurrencyFormatter.formatAmount(state.totalRoomPaid), 0xFF2E7D5B.toInt()),
            Triple("مدفوعات أخرى", CurrencyFormatter.formatAmount(state.totalOtherPaid), 0xFF00897B.toInt()),
            Triple("الإجمالي", CurrencyFormatter.formatAmount(state.totalAll), 0xFF242476.toInt()),
            Triple("المتبقي", CurrencyFormatter.formatAmount(state.totalRemaining), 0xFFE5484D.toInt())
        ),
        tables = listOf(
            PdfExporter.PdfTable(
                title = "تفاصيل الدفعات",
                headers = listOf("م", "رقم الحجز", "اسم النزيل", "الغرفة", "طريقة الدفع", "التاريخ", "المبلغ"),
                rows = state.rows.mapIndexed { i, row ->
                    listOf(
                        "${i + 1}",
                        row.bookingCode ?: "غير متوفر",
                        row.payerName,
                        row.roomNumber,
                        translateMethod(row.payment.paymentMethod),
                        row.payment.paymentDate.take(16).replace("T", " "),
                        CurrencyFormatter.formatAmount(row.payment.amount)
                    )
                },
                totalRow = listOf("", "", "", "", "", "الإجمالي", CurrencyFormatter.formatAmount(state.totalRoomPaid)),
                columnWeights = listOf(0.5f, 1.2f, 1.6f, 0.9f, 1.1f, 1.6f, 1.1f)
            )
        ),
        fileName = PdfExporter.generateFileName("مدفوعات-النزلاء")
    )
    PdfExporter.sharePdf(context, file, "تقرير مدفوعات النزلاء")
}

@Composable
internal fun ReportStat(
    label: String,
    value: String,
    color: Color,
    modifier: Modifier = Modifier,
    large: Boolean = false
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.1f))
    ) {
        Column(
            modifier = Modifier.padding(vertical = if (large) 16.dp else 10.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = if (large) 18.sp else 14.sp)
            Text(label, fontSize = 10.sp, color = AppColors.TextSecondary)
        }
    }
}

@Composable
internal fun ReportEmptyCard(title: String, message: String) {
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
            Text(title, style = AppTypography.titleMedium, color = AppColors.TextPrimary)
            Text(message, style = AppTypography.bodySmall, color = AppColors.TextSecondary)
        }
    }
}
