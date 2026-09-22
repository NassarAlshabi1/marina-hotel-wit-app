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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.util.BookingFinancials
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.util.PdfExporter

/** تقرير مدفوعات النزلاء التفصيلي — UI port of `guest_payments_detail_report_screen.dart`. */
@Composable
fun GuestDetailReportScreen(
    onBack: () -> Unit = {},
    viewModel: GuestDetailReportViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val rows = remember(state) { viewModel.filteredRows() }
    LaunchedEffect(rows) { viewModel.recalcTotals(rows) }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = {
                        Column {
                            Text("مارينا هوتيل", style = AppTypography.titleLarge)
                            Text("تقرير مدفوعات النزلاء التفصيلي", fontSize = 11.sp, color = AppColors.TextSecondary)
                        }
                    },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            }
        ) { padding ->
            Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                // Search + filters + sort (Dart header controls).
                Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    OutlinedTextField(
                        value = state.searchQuery,
                        onValueChange = { viewModel.setSearch(it) },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("بحث (الاسم، الغرفة، الهاتف)", fontSize = 12.sp) },
                        singleLine = true,
                        shape = RoundedCornerShape(12.dp)
                    )
                    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        FilterChip(selected = state.showOnlyActive, onClick = { viewModel.setShowOnlyActive(!state.showOnlyActive) },
                            label = { Text("النشطة فقط", fontSize = 11.sp) })
                        listOf("all" to "الكل", "partial" to "دفع جزئي", "unpaid" to "غير مدفوع", "overpaid" to "زيادة").forEach { (key, label) ->
                            FilterChip(
                                selected = state.filterStatus == key,
                                onClick = { viewModel.setFilterStatus(key) },
                                label = { Text(label, fontSize = 11.sp) }
                            )
                        }
                    }
                    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf("room" to "ترتيب: الغرفة", "remaining" to "ترتيب: المتبقي", "name" to "ترتيب: الاسم").forEach { (key, label) ->
                            FilterChip(
                                selected = state.sortBy == key,
                                onClick = { viewModel.setSortBy(key) },
                                label = { Text(label, fontSize = 11.sp) }
                            )
                        }
                    }
                }

                // Summary bar (Dart l.644-680).
                Card(
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = Color.Transparent),
                    modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier
                            .background(Brush.horizontalGradient(listOf(Color(0xFF0D47A1), Color(0xFF1565C0))), RoundedCornerShape(12.dp))
                            .padding(12.dp)
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        SummaryBarItem("النزلاء", "${rows.size}")
                        SummaryBarItem("المستحق", CurrencyFormatter.formatAmount(state.totalDue))
                        SummaryBarItem("المحصل", CurrencyFormatter.formatAmount(state.totalPaid))
                        SummaryBarItem("المتبقي", CurrencyFormatter.formatAmount(state.totalRemaining))
                    }
                }

                if (state.isLoading) {
                    Box(modifier = Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                } else if (rows.isEmpty()) {
                    Box(modifier = Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                        ReportEmptyCard("لا توجد بيانات تطابق معايير البحث", "")
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        items(rows.size, key = { rows[it].booking.id }) { index ->
                            GuestDetailCard(rows[index]) {
                                val phone = BookingFinancials.cleanAndFormatPhone(rows[index].booking.guestPhone)
                                PdfExporter.openWhatsAppText(context, phone, viewModel.buildGuestStatement(rows[index]))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SummaryBarItem(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
        Text(label, color = Color.White.copy(alpha = 0.8f), fontSize = 9.sp)
    }
}

@Composable
private fun GuestDetailCard(row: GuestDetailRow, onShare: () -> Unit) {
    val b = row.booking
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        shape = RoundedCornerShape(12.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        "غرفة ${b.roomNumber}", fontSize = 11.sp, color = Color.White, fontWeight = FontWeight.Bold,
                        modifier = Modifier.background(Color(0xFF1565C0), RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 3.dp)
                    )
                    Text(b.guestName.ifBlank { "ضيف" }, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text("سعر الليلة: ${CurrencyFormatter.formatAmount(row.nightlyRate)} ريال", fontSize = 10.sp, color = AppColors.TextSecondary)
                    Text(
                        if (b.remainingBalanceCached >= 0) "متبقي: ${CurrencyFormatter.formatAmount(b.remainingBalanceCached)}" else "رصيد للنزيل: ${CurrencyFormatter.formatAmount(-b.remainingBalanceCached)}",
                        fontSize = 11.sp, fontWeight = FontWeight.Bold,
                        color = if (b.remainingBalanceCached > 0) AppColors.DangerColor else AppColors.SuccessColor
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("الدخول: ${b.checkinDate.take(10)}", fontSize = 10.sp, color = AppColors.TextSecondary)
                Text("الليالي المدفوعة: ${row.paidNights} ليلة", fontSize = 10.sp, color = AppColors.TextSecondary)
                row.autoCheckoutMillis?.let {
                    Text(
                        (if (row.isAutoExtended) "المغادرة المخططة (مُمدَّدة)" else "المغادرة المخططة (محسوبة)") + ": " + HotelTimeEngine.formatDisplayDateOnly(it),
                        fontSize = 10.sp, color = if (row.isAutoExtended) AppColors.WarningColor else AppColors.TextSecondary
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MiniStat("المقضية", "${row.actualDays}", Modifier.weight(1f))
                MiniStat(
                    if (row.isAutoExtended) "إضافية (تمديد)" else "المتبقية",
                    "${(row.actualDays - row.paidNights).coerceAtLeast(0)}",
                    Modifier.weight(1f)
                )
                MiniStat("المخططة", "${b.expectedNights}", Modifier.weight(1f))
                MiniStat("المدفوع", CurrencyFormatter.formatAmount(b.totalPaidCached), Modifier.weight(1f))
            }

            // Coverage progress (Dart l.1116+).
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("تغطية التكاليف الحالية", fontSize = 9.sp, color = AppColors.TextSecondary)
                    Text("${"%.0f".format(row.paidPercent)}%", fontSize = 9.sp, color = AppColors.TextSecondary)
                }
                LinearProgressIndicator(
                    progress = { (row.paidPercent / 100.0).coerceIn(0.0, 1.0).toFloat() },
                    modifier = Modifier.fillMaxWidth().height(6.dp),
                    color = if (row.paidPercent >= 100) AppColors.SuccessColor else AppColors.WarningColor,
                    trackColor = AppColors.LightGray
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "إجمالي العقد: ${CurrencyFormatter.formatAmount(b.totalDueCached)} ريال",
                    fontSize = 10.sp, color = AppColors.TextSecondary
                )
                TextButton(onClick = onShare, contentPadding = PaddingValues(horizontal = 8.dp)) {
                    Text("إرسال كشف (واتساب)", fontSize = 10.sp, color = Color(0xFF25D366))
                }
            }
        }
    }
}

@Composable
private fun MiniStat(label: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.background(AppColors.LightGray, RoundedCornerShape(8.dp)).padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AppColors.TextPrimary)
        Text(label, fontSize = 9.sp, color = AppColors.TextSecondary)
    }
}
