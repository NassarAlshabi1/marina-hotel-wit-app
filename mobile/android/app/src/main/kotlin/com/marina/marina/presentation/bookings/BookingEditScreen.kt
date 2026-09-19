package com.marina.marina.presentation.bookings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import java.util.Calendar

@Composable
fun BookingEditScreen(
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    viewModel: BookingEditViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(state.saved) {
        if (state.saved) onSaved()
    }

    // Pre-fill form once loaded (existing booking values or defaults).
    val booking = state.booking
    var guestName by remember(state.booking?.id) { mutableStateOf(booking?.guestName ?: "") }
    var guestPhone by remember(state.booking?.id) { mutableStateOf(booking?.guestPhone ?: "") }
    var idNumber by remember(state.booking?.id) { mutableStateOf(booking?.guestIdNumber ?: "") }
    var nationality by remember(state.booking?.id) { mutableStateOf(booking?.guestNationality?.ifBlank { "يمني" } ?: "يمني") }
    var roomNumber by remember(state.booking?.id) { mutableStateOf(booking?.roomNumber ?: "") }
    var checkinDate by remember(state.booking?.id) { mutableStateOf(booking?.checkinDate?.take(16) ?: HotelTimeEngine.formatIso(System.currentTimeMillis()).take(16)) }
    var checkoutDate by remember(state.booking?.id) { mutableStateOf(booking?.checkoutDate?.take(16) ?: "") }
    var notes by remember(state.booking?.id) { mutableStateOf(booking?.notes ?: "") }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text(if (state.isEdit) "تعديل الحجز" else "حجز جديد", style = AppTypography.titleLarge) },
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
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(16.dp)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    state.error?.let {
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.DangerColor.copy(alpha = 0.1f)),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Text(
                                it,
                                style = AppTypography.bodyMedium,
                                color = AppColors.DangerColor,
                                modifier = Modifier.padding(12.dp)
                            )
                        }
                    }

                    FormSection("بيانات الضيف") {
                        FormField("اسم الضيف *", guestName, { guestName = it })
                        FormField("الهاتف", guestPhone, { guestPhone = it })
                        FormField("رقم الهوية", idNumber, { idNumber = it })
                        FormField("الجنسية", nationality, { nationality = it })
                    }

                    FormSection("تفاصيل الحجز") {
                        Text("الغرفة *", style = AppTypography.labelLarge)
                        if (state.availableRooms.isEmpty()) {
                            Text("لا توجد غرف شاغرة", style = AppTypography.bodySmall, color = AppColors.WarningColor)
                        } else {
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                state.availableRooms.forEach { room ->
                                    FilterChip(
                                        selected = roomNumber == room.roomNumber,
                                        onClick = { roomNumber = room.roomNumber },
                                        label = { Text("${room.roomNumber} (${room.price.toInt()})", fontSize = 12.sp) }
                                    )
                                }
                            }
                        }
                        Spacer(modifier = Modifier.height(4.dp))
                        DateField("تاريخ الدخول * (yyyy-MM-dd HH:mm)", checkinDate, { checkinDate = it })
                        DateField("المغادرة المخططة (yyyy-MM-dd HH:mm)", checkoutDate, { checkoutDate = it })

                        // Live nights preview using the hotel-day engine.
                        val checkinMillis = HotelTimeEngine.parseDate(checkinDate)
                        val checkoutMillis = HotelTimeEngine.parseDate(checkoutDate)
                        if (checkinMillis != null) {
                            val nights = HotelTimeEngine.calculateDays(checkinMillis, checkoutMillis)
                            Text(
                                "عدد الليالي المحتسب (حد 14:01): $nights",
                                style = AppTypography.bodySmall,
                                color = AppColors.PrimaryColor,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }

                    FormSection("ملاحظات") {
                        OutlinedTextField(
                            value = notes,
                            onValueChange = { notes = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("ملاحظات الحجز") },
                            minLines = 2
                        )
                    }

                    Button(
                        onClick = {
                            viewModel.save(guestName, guestPhone, idNumber, nationality, roomNumber, checkinDate, checkoutDate, notes)
                        },
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryColor),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("حفظ الحجز", color = Color.White, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
private fun FormSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, style = AppTypography.titleMedium, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
            content()
        }
    }
}

@Composable
private fun FormField(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = true
    )
}

@Composable
private fun DateField(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = true,
        placeholder = { Text("2026-09-19 15:00") }
    )
}
