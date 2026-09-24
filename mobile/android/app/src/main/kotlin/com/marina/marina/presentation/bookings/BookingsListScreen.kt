package com.marina.marina.presentation.bookings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.components.SidebarMenuButton
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun BookingsListScreen(
    onBookingClick: (Long) -> Unit = {},
    onAddBooking: () -> Unit = {},
    viewModel: BookingsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.consumeMessage()
        }
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("الحجوزات", style = AppTypography.titleLarge) },
                    navigationIcon = { SidebarMenuButton() },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            floatingActionButton = {
                FloatingActionButton(
                    onClick = onAddBooking,
                    containerColor = AppColors.PrimaryColor,
                    contentColor = Color.White
                ) {
                    Text("+", fontSize = 24.sp, fontWeight = FontWeight.Bold)
                }
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 16.dp)
            ) {
                OutlinedTextField(
                    value = state.searchQuery,
                    onValueChange = viewModel::setSearchQuery,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("بحث باسم الضيف، الهاتف، الغرفة...") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp)
                )

                Spacer(modifier = Modifier.height(10.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(
                        // Dart default dataset (l.113-122): everything except
                        // completed/departed — cancelled bookings stay visible.
                        "default" to "الافتراضي",
                        "النشطة" to "النشطة",
                        "all" to "الكل",
                        "مكتمل" to "المكتملة",
                        "ملغي" to "الملغاة"
                    ).forEach { (key, label) ->
                        FilterChip(
                            selected = state.statusFilter == key,
                            onClick = { viewModel.setStatusFilter(key) },
                            label = { Text(label) }
                        )
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        "تعذر تحميل الحجوزات: ${state.error}",
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor,
                        modifier = Modifier.padding(16.dp)
                    )
                    state.filtered.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("لا توجد حجوزات", style = AppTypography.bodyLarge, color = AppColors.TextSecondary)
                    }
                    else -> LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        contentPadding = PaddingValues(bottom = 88.dp)
                    ) {
                        items(state.filtered, key = { it.id }) { booking ->
                            BookingCard(
                                booking = booking,
                                roomPrice = state.roomPrices[booking.roomNumber] ?: 0.0,
                                onClick = { onBookingClick(booking.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BookingCard(booking: Booking, roomPrice: Double, onClick: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StatusBadge(
                        text = booking.roomNumber,
                        backgroundColor = AppColors.PrimaryColor
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        booking.guestName.ifBlank { "ضيف" },
                        style = AppTypography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
                BookingStatusChip(status = booking.status)
            }

            if (booking.guestPhone.isNotBlank()) {
                Text("📱 ${booking.guestPhone}", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                val checkin = HotelTimeEngine.parseDate(booking.checkinDate)
                InfoCell("الدخول", checkin?.let { HotelTimeEngine.formatDisplayDateOnly(it) } ?: booking.checkinDate.take(10))
                val nights = booking.calculatedNights
                InfoCell("الليالي", "$nights")
                InfoCell("السعر/ليلة", "${roomPrice.toInt()}")
            }

            // Payment progress (uses the denormalized financial cache — now
            // recomputed on every booking save, Dart bookings_repository l.97/224).
            val total = booking.totalDueCached
            val paid = booking.totalPaidCached
            val remaining = booking.remainingBalanceCached
            // Dart payment-status verdict badge (l.551-556, 687-708).
            val (verdictText, verdictColor) = when {
                remaining <= 0 -> "مسددة" to AppColors.SuccessColor
                paid > 0 -> "جزئياً" to AppColors.WarningColor
                else -> "غير مسددة" to AppColors.DangerColor
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                StatusBadge(text = verdictText, backgroundColor = verdictColor)
                // Dart period row (l.645-665): checkin + حتى planned + actual.
                val checkoutLabel = booking.actualCheckout?.take(10)
                    ?: booking.checkoutDate?.take(10)
                if (checkoutLabel != null) {
                    Text(
                        "حتى $checkoutLabel" + if (booking.actualCheckout != null) " (خروج فعلي)" else "",
                        style = AppTypography.labelSmall,
                        color = AppColors.TextSecondary
                    )
                }
            }
            if (total > 0) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("الإجمالي: ${total.toInt()}", style = AppTypography.labelMedium)
                        Text("المدفوع: ${paid.toInt()}", style = AppTypography.labelMedium, color = AppColors.SuccessColor)
                        Text(
                            "المتبقي: ${remaining.toInt()}",
                            style = AppTypography.labelMedium,
                            color = if (remaining > 0) AppColors.DangerColor else AppColors.SuccessColor
                        )
                    }
                    LinearProgressIndicator(
                        progress = { if (total > 0) (paid / total).toFloat().coerceIn(0f, 1f) else 0f },
                        modifier = Modifier.fillMaxWidth().height(6.dp),
                        color = AppColors.SuccessColor,
                        trackColor = AppColors.LightGray
                    )
                }
            }
        }
    }
}

@Composable
private fun BookingStatusChip(status: String) {
    val (bg, label) = when {
        status.contains("مؤقت") -> AppColors.WarningColor to "مؤقت"
        StatusUtils.isBookingActive(status) -> AppColors.SuccessColor to "محجوزة"
        status == "مكتمل" || status == "completed" -> AppColors.PrimaryColor to "مكتمل"
        status == "ملغي" || status == "cancelled" -> AppColors.DangerColor to "ملغي"
        else -> AppColors.MediumGray to status
    }
    StatusBadge(text = label, backgroundColor = bg)
}

@Composable
private fun StatusBadge(text: String, backgroundColor: Color) {
    Box(
        modifier = Modifier
            .background(backgroundColor, RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 3.dp)
    ) {
        Text(text, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun InfoCell(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = AppTypography.titleSmall, fontWeight = FontWeight.SemiBold, color = AppColors.TextPrimary)
        Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary)
    }
}
