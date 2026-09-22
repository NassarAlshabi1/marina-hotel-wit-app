package com.marina.marina.presentation.settings

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
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.util.BookingFinancials
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.util.PdfExporter

/** تذكير المتبقي — UI port of `active_bookings_reminder_screen.dart`. */
@Composable
fun BookingsReminderScreen(
    onBack: () -> Unit = {},
    viewModel: BookingsReminderViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    fun sendReminder(booking: Booking) {
        val message = buildString {
            append("عزيزي ${booking.guestName}\n")
            append("رقم الغرفة: ${booking.roomNumber}\n")
            append("المبلغ المتبقي: ${CurrencyFormatter.formatAmount(booking.remainingBalanceCached)} ريال\n")
            append("نرجو منكم تسديد المبلغ المتبقي في أقرب وقت ممكن\n")
            append("شكراً لاختيارك فندق مارينا\nللاستفسار: 9677734587456")
        }
        val phone = BookingFinancials.cleanAndFormatPhone(booking.guestPhone)
        PdfExporter.openWhatsAppText(context, phone, message)
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("تذكير المتبقي", style = AppTypography.titleLarge) },
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
            if (state.isLoading) {
                Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else if (state.withRemaining.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Column(
                            modifier = Modifier.padding(24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text("لا توجد حجوزات بمبالغ متبقية", style = AppTypography.titleMedium)
                            Text("جميع الحجوزات النشطة مسددة بالكامل", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
                        }
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    items(state.withRemaining.size, key = { state.withRemaining[it].id }) { index ->
                        val booking = state.withRemaining[index]
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                            shape = RoundedCornerShape(12.dp),
                            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier.padding(12.dp).fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Box(
                                    modifier = Modifier.size(42.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        booking.roomNumber,
                                        fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor, fontSize = 15.sp
                                    )
                                }
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(booking.guestName.ifBlank { "ضيف" }, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                                    Text(
                                        "${booking.guestPhone.ifBlank { "بدون هاتف" }} • ${booking.checkinDate.take(10)}",
                                        fontSize = 10.sp, color = AppColors.TextSecondary
                                    )
                                    Text(
                                        "متبقي: ${CurrencyFormatter.formatAmount(booking.remainingBalanceCached)} ريال",
                                        fontSize = 11.sp, fontWeight = FontWeight.Bold, color = AppColors.WarningColor
                                    )
                                }
                                Button(
                                    onClick = { sendReminder(booking) },
                                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF25D366)),
                                    shape = RoundedCornerShape(10.dp),
                                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                                ) {
                                    Text("تذكير", fontSize = 12.sp, color = Color.White)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
