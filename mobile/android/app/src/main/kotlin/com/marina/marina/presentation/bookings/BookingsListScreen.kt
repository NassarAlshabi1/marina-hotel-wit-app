package com.marina.marina.presentation.bookings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.outlined.Hotel
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography

/**
 * شاشة «الحجوزات» — نقل 1:1 لـ bookings_list.dart
 * (فرع feat/cloudflare-sync-execution):
 *
 *  • AppBar: «الحجوزات» + زر مزامنة (نظير SyncActionButton في AppScaffold)
 *    + «إدارة المدفوعات» + «حجز جديد» + FAB إضافة.
 *  • الجدول العريض (≥900dp) بصفّ عنوان: # بيانات النزيل الغرفة سعر الليلة
 *    الفترة الليالي المدفوع المتبقي حالة الدفعة حالة الحجز.
 *  • البطاقات المدمجة للهواتف (رقم تسلسلي + الغرفة + النزيل + شارة حالة
 *    الدفعة + سطر الفترة + سطر الخروج الفعلي) — شرائح المعلومات المالية
 *    حُذفت في Dart صراحةً (تعليق l.385-403) فلا تُرسم هنا أيضاً.
 *  • سحب-للتحديث يشغّل مزامنة Cloudflare (triggerManualCloudflareSync بلا
 *    سناك-بار نجاح).
 *  • النقر على أي صف/بطاقة يفتح شاشة دفع الحجز (BookingPaymentScreen).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookingsListScreen(
    onBookingClick: (Long) -> Unit = {},
    onAddBooking: () -> Unit = {},
    onOpenPayments: () -> Unit = {},
    viewModel: BookingsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // سناك-بار الرسائل — ألوان Dart: أحمر للخطأ، برتقالي داكن للتحذير.
    LaunchedEffect(state.snackbar) {
        val snack = state.snackbar ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(
            message = snack.text,
            duration = if (snack.isError) SnackbarDuration.Long else SnackbarDuration.Short,
            withDismissAction = true
        )
        viewModel.consumeSnackbar()
    }

    Scaffold(
        containerColor = AppColors.BackgroundColor,
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("الحجوزات", style = AppTypography.titleLarge) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.SurfaceColor,
                    titleContentColor = AppColors.TextPrimary
                ),
                actions = {
                    // نظير SyncActionButton من AppScaffold (بنفس الرسائل).
                    IconButton(onClick = viewModel::runShellSync, enabled = !state.isSyncing) {
                        if (state.isSyncing) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp
                            )
                        } else {
                            Icon(Icons.Filled.Sync, contentDescription = "مزامنة مع Cloudflare")
                        }
                    }
                    IconButton(onClick = onOpenPayments) {
                        Icon(Icons.Filled.Payments, contentDescription = "إدارة المدفوعات")
                    }
                    IconButton(onClick = onAddBooking) {
                        Icon(Icons.Filled.Add, contentDescription = "حجز جديد")
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onAddBooking,
                containerColor = AppColors.PrimaryColor,
                contentColor = Color.White
            ) {
                Icon(Icons.Filled.Add, contentDescription = "حجز جديد")
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            when {
                state.isLoading -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) { CircularProgressIndicator() }

                state.error != null -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    // Dart l.95-101: نص 'خطأ: $e' في المنتصف.
                    Text(
                        "خطأ: ${state.error}",
                        color = AppColors.TextPrimary,
                        style = AppTypography.bodyMedium
                    )
                }

                state.rows.isEmpty() -> EmptyBookingsState()

                else -> BoxWithConstraints(Modifier.fillMaxSize()) {
                    val isWide = maxWidth >= 900.dp
                    if (isWide) {
                        PullToRefreshBox(
                            isRefreshing = state.isSyncing,
                            onRefresh = viewModel::triggerManualSync,
                            state = rememberPullToRefreshState()
                        ) {
                            WideBookingsTable(
                                rows = state.rows,
                                onRowClick = { onBookingClick(it.booking.id) }
                            )
                        }
                    } else {
                        PullToRefreshBox(
                            isRefreshing = state.isSyncing,
                            onRefresh = viewModel::triggerManualSync,
                            state = rememberPullToRefreshState()
                        ) {
                            LazyColumn(
                                modifier = Modifier.fillMaxSize(),
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                                verticalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                items(state.rows, key = { it.booking.id }) { row ->
                                    CompactBookingCard(
                                        row = row,
                                        onClick = { onBookingClick(row.booking.id) }
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

/** Dart EmptyState(title: 'لا توجد حجوزات', message: 'أضف حجزاً جديداً للبدء', icon: hotel_outlined). */
@Composable
private fun EmptyBookingsState() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                Icons.Outlined.Hotel,
                contentDescription = null,
                tint = AppColors.MediumGray,
                modifier = Modifier.size(48.dp)
            )
            Spacer(Modifier.height(8.dp))
            Text("لا توجد حجوزات", style = AppTypography.titleMedium)
            Spacer(Modifier.height(4.dp))
            Text(
                "أضف حجزاً جديداً للبدء",
                style = AppTypography.bodySmall,
                color = AppColors.MediumGray
            )
        }
    }
}

/**
 * الجدول العريض — Dart l.111-137: تمرير أفقي بحد أدنى 1100dp + صف عنوان
 * بخلفية surfaceContainerHighest@50%.
 */
@Composable
private fun WideBookingsTable(rows: List<BookingRowUi>, onRowClick: (BookingRowUi) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val tableWidth = if (maxWidth >= 1100.dp) maxWidth else 1100.dp
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
        ) {
            Box(Modifier.horizontalScroll(rememberScrollState())) {
                Column(Modifier.width(tableWidth)) {
                    HeaderRow(tableWidth)
                    rows.forEach { row ->
                        WideBookingRow(
                            row = row,
                            tableWidth = tableWidth,
                            onClick = { onRowClick(row) }
                        )
                    }
                }
            }
        }
    }
}

/** Dart _buildHeaderRow (l.412-437). */
@Composable
private fun HeaderRow(tableWidth: Dp) {
    Row(
        modifier = Modifier
            .width(tableWidth)
            .background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.5f))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        HeaderCell("#", Modifier.width(40.dp))
        HeaderCell("بيانات النزيل", Modifier.weight(2f))
        HeaderCell("الغرفة", Modifier.weight(1f))
        HeaderCell("سعر الليلة", Modifier.weight(1f))
        HeaderCell("الفترة", Modifier.weight(2f))
        HeaderCell("الليالي", Modifier.weight(1f))
        HeaderCell("المدفوع", Modifier.weight(1f))
        HeaderCell("المتبقي", Modifier.weight(1f))
        HeaderCell("حالة الدفعة", Modifier.weight(1f))
        HeaderCell("حالة الحجز", Modifier.weight(1f))
    }
}

/** Dart _HeaderCell (l.439-456) — نص مُوسّط. */
@Composable
private fun HeaderCell(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        textAlign = TextAlign.Center,
        style = AppTypography.bodyMedium,
        color = AppColors.TextPrimary,
        modifier = modifier
    )
}

/** صف الجدول العريض — Dart _BookingRow (l.586-704) النسخة غير المدمجة. */
@Composable
private fun WideBookingRow(row: BookingRowUi, tableWidth: Dp, onClick: () -> Unit) {
    val booking = row.booking
    val guestTooltip = guestTooltipText(booking)

    Column(Modifier.width(tableWidth)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                row.index.toString(),
                textAlign = TextAlign.Center,
                style = AppTypography.bodyMedium,
                color = AppColors.TextPrimary,
                modifier = Modifier.width(40.dp)
            )
            // بيانات النزيل (flex 2) — Tooltip بمعلومات النزيل الكاملة.
            Box(Modifier.weight(2f)) {
                TooltipBox(
                    positionProvider = TooltipDefaults.rememberPlainTooltipPositionProvider(),
                    tooltip = { PlainTooltip { Text(guestTooltip) } },
                    state = rememberTooltipState()
                ) {
                    Column {
                        Text(
                            booking.guestName,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.W600,
                            color = AppColors.TextPrimary
                        )
                        if (booking.guestPhone.isNotEmpty()) {
                            Text(
                                booking.guestPhone,
                                fontSize = 12.sp,
                                color = AppColors.TextPrimary
                            )
                        }
                        Spacer(Modifier.height(2.dp))
                        Text(
                            if (booking.guestIdNumber.isEmpty()) booking.guestIdType
                            else "${booking.guestIdType} • ${booking.guestIdNumber}",
                            fontSize = 12.sp,
                            color = AppColors.TextPrimary
                        )
                        if (booking.guestNationality.isNotEmpty()) {
                            Text(
                                booking.guestNationality,
                                fontSize = 12.sp,
                                color = AppColors.TextPrimary
                            )
                        }
                    }
                }
            }
            CellText(booking.roomNumber, Modifier.weight(1f))
            CellText(CurrencyFormatter.formatAmount(row.pricePerNight), Modifier.weight(1f))
            Column(Modifier.weight(2f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    formatDate(booking.checkinDate),
                    style = AppTypography.bodyMedium,
                    color = AppColors.TextPrimary,
                    textAlign = TextAlign.Center
                )
                if (row.plannedText != null) {
                    Text(
                        "حتى ${row.plannedText}",
                        fontSize = 12.sp,
                        color = AppColors.TextPrimary,
                        textAlign = TextAlign.Center
                    )
                }
                if (row.actualText != null) {
                    Text(
                        "خروج فعلي ${row.actualText}",
                        fontSize = 12.sp,
                        color = AppColors.TextPrimary,
                        textAlign = TextAlign.Center
                    )
                }
            }
            CellText(row.nightsLabel, Modifier.weight(1f))
            CellText(CurrencyFormatter.formatAmount(row.paid), Modifier.weight(1f))
            CellText(CurrencyFormatter.formatAmount(row.remaining), Modifier.weight(1f))
            // حالة الدفعة — حبة بحدود ملونة (Dart l.682-701).
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                val statusColor = Color(row.paymentStatusColor)
                Box(
                    modifier = Modifier
                        .border(
                            border = BorderStroke(1.dp, statusColor),
                            shape = RoundedCornerShape(12.dp)
                        )
                        .background(statusColor.copy(alpha = 0.1f), RoundedCornerShape(12.dp))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(
                        row.paymentStatusText,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.TextPrimary
                    )
                }
            }
            // حالة الحجز — شارة ملونة (Dart _buildBookingStatusChip l.739-762).
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Box(
                    modifier = Modifier
                        .background(Color(row.bookingStatusColor), RoundedCornerShape(16.dp))
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                ) {
                    Text(
                        row.bookingStatusText,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.W500,
                        color = AppColors.TextPrimary
                    )
                }
            }
        }
        // Border(bottom: Color(0xFFE0E0E0)) في Dart — نفس الفاصل البصري.
        Box(
            Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(Color(0xFFE0E0E0))
        )
    }
}

@Composable
private fun CellText(value: String, modifier: Modifier = Modifier) {
    Text(
        value,
        style = AppTypography.bodyMedium,
        color = AppColors.TextPrimary,
        textAlign = TextAlign.Center,
        modifier = modifier
    )
}

/** البطاقة المدمجة — Dart _CompactBookingCard (l.238-410). */
@Composable
private fun CompactBookingCard(row: BookingRowUi, onClick: () -> Unit) {
    val booking = row.booking
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .background(AppColors.PrimaryColor, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        row.index.toString(),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.W600,
                        color = Color.White
                    )
                }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        "الغرفة ${booking.roomNumber}",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.TextPrimary
                    )
                    Spacer(Modifier.height(3.dp))
                    Text(
                        booking.guestName,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.TextPrimary
                    )
                    if (booking.guestPhone.isNotEmpty()) {
                        Text(
                            booking.guestPhone,
                            fontSize = 10.sp,
                            color = AppColors.TextPrimary
                        )
                    }
                }
                val statusColor = Color(row.paymentStatusColor)
                Box(
                    modifier = Modifier
                        .background(statusColor.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Text(
                        row.paymentStatusText,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = statusColor
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.CalendarToday,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = AppColors.TextPrimary
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    formatDate(booking.checkinDate) +
                        (row.plannedText?.let { " • حتى $it" } ?: ""),
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.TextPrimary
                )
            }
            if (row.actualText != null) {
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.AutoMirrored.Filled.Logout,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = AppColors.TextPrimary
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        "خروج فعلي ${row.actualText}",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.TextPrimary
                    )
                }
            }
            // ملاحظة Dart l.385-403: فاصل المسافة والـ Wrap الخاص بشرائح
            // (الليالي/السعر/المدفوع/المتبقي/الإجمالي) أُزيل في Dart صراحةً.
        }
    }
}

/**
 * Dart l.534-545 — سطور tooltip النزيل:
 * الاسم / الهاتف / الهوية (النوع + الرقم) / الجنسية / البريد / العنوان.
 */
private fun guestTooltipText(booking: Booking): String {
    val lines = mutableListOf("الاسم: ${booking.guestName}")
    if (booking.guestPhone.isNotEmpty()) lines += "الهاتف: ${booking.guestPhone}"
    if (booking.guestIdNumber.isNotEmpty()) lines += "الهوية: ${booking.guestIdType} ${booking.guestIdNumber}"
    if (booking.guestNationality.isNotEmpty()) lines += "الجنسية: ${booking.guestNationality}"
    if (!booking.guestEmail.isNullOrEmpty()) lines += "البريد: ${booking.guestEmail}"
    if (!booking.guestAddress.isNullOrEmpty()) lines += "العنوان: ${booking.guestAddress}"
    return lines.joinToString("\n")
}

/** Dart _formatDate (l.757-764) — dd/MM/yyyy عبر محرك اليوم الفندقي الموحد. */
private fun formatDate(rawIso: String): String {
    val millis = HotelTimeEngine.parseDate(rawIso) ?: return rawIso
    return HotelTimeEngine.formatDisplayDateOnly(millis)
}
