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

/** Dart ID-type fallback list (booking_edit.dart l.64-78 dynamic list fallback). */
private val ID_TYPES = listOf(
    "بطاقة شخصية", "جواز سفر", "رخصة قيادة", "بطاقة إنتخاب", "حفيظة نفوس", "إقامة"
)

/** Dart payment-method fallback list. */
private val PAYMENT_METHODS = listOf("نقدي", "تحويل بنكي", "بطاقة", "شيك", "تقسيط")

/** Dart booking status vocabulary (booking_edit.dart l.99, 416-428). */
private val BOOKING_STATUSES = listOf("محجوزة", "مؤقت", "شاغرة", "مكتمل", "ملغي")

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
    val formKey = state.booking?.id ?: -1L
    var guestName by remember(formKey) { mutableStateOf(booking?.guestName ?: "") }
    var guestPhone by remember(formKey) { mutableStateOf(booking?.guestPhone ?: "") }
    var idType by remember(formKey) { mutableStateOf(booking?.guestIdType ?: ID_TYPES.first()) }
    var idNumber by remember(formKey) { mutableStateOf(booking?.guestIdNumber ?: "") }
    var idIssueDate by remember(formKey) { mutableStateOf(booking?.guestIdIssueDate ?: "") }
    var idIssuePlace by remember(formKey) { mutableStateOf(booking?.guestIdIssuePlace ?: "") }
    var nationality by remember(formKey) { mutableStateOf(booking?.guestNationality ?: "يمني") }
    var guestEmail by remember(formKey) { mutableStateOf(booking?.guestEmail ?: "") }
    var guestAddress by remember(formKey) { mutableStateOf(booking?.guestAddress ?: "") }
    // Dart l.140-144: the preselected room from the Rooms/Dashboard flow wins
    // for NEW bookings; the check-in field defaults to now.
    var roomNumber by remember(formKey) {
        mutableStateOf(booking?.roomNumber ?: state.preselectedRoom)
    }
    var checkinDate by remember(formKey) {
        mutableStateOf(booking?.checkinDate?.take(16) ?: HotelTimeEngine.formatIso(System.currentTimeMillis()).take(16))
    }
    var checkoutDate by remember(formKey) { mutableStateOf(booking?.checkoutDate?.take(16) ?: "") }
    var status by remember(formKey) { mutableStateOf(booking?.status ?: "") }
    var notes by remember(formKey) { mutableStateOf(booking?.notes ?: "") }
    var advanceEnabled by remember(formKey) { mutableStateOf(false) }
    var advanceAmount by remember(formKey) { mutableStateOf("") }
    var advanceMethod by remember(formKey) { mutableStateOf(PAYMENT_METHODS.first()) }
    var advanceNotes by remember(formKey) { mutableStateOf("") }

    fun currentForm() = BookingEditForm(
        guestName = guestName, guestPhone = guestPhone,
        guestIdType = idType, guestIdNumber = idNumber,
        guestIdIssueDate = idIssueDate, guestIdIssuePlace = idIssuePlace,
        guestNationality = nationality, guestEmail = guestEmail, guestAddress = guestAddress,
        roomNumber = roomNumber, checkinDate = checkinDate, checkoutDate = checkoutDate,
        status = status, notes = notes,
        advanceEnabled = advanceEnabled, advanceAmount = advanceAmount,
        advanceMethod = advanceMethod, advanceNotes = advanceNotes
    )

    MarinaTheme {
        // Dart security warning (l.622-713) — a blacklisted guest name match
        // blocks the save until the user explicitly chooses متابعة الحجز.
        state.blacklistWarning?.let { entry ->
            AlertDialog(
                onDismissRequest = { viewModel.dismissBlacklistWarning() },
                title = { Text("تحذير أمني", color = AppColors.DangerColor, fontWeight = FontWeight.Bold) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("اسم النزيل موجود في القائمة السوداء!", fontWeight = FontWeight.Bold, color = AppColors.DangerColor)
                        Text("الاسم: ${entry.name}")
                        entry.nationality?.let { Text("الجنسية: $it") }
                        entry.reason?.let { Text("السبب: $it", color = AppColors.WarningColor) }
                    }
                },
                confirmButton = {
                    TextButton(onClick = { viewModel.save(currentForm(), overrideBlacklist = true) }) {
                        Text("متابعة الحجز", color = AppColors.WarningColor, fontWeight = FontWeight.Bold)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { viewModel.dismissBlacklistWarning() }) { Text("إلغاء") }
                }
            )
        }

        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text(if (state.isEdit) "تعديل حجز" else "إضافة حجز", style = AppTypography.titleLarge) },
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
                        DropdownField("نوع الهوية", idType, ID_TYPES) { idType = it }
                        FormField("رقم الهوية *", idNumber, { idNumber = it })
                        FormField("تاريخ الإصدار (yyyy-MM-dd)", idIssueDate, { idIssueDate = it })
                        FormField("مكان الإصدار", idIssuePlace, { idIssuePlace = it })
                        FormField("الجنسية *", nationality, { nationality = it })
                        FormField("البريد الإلكتروني", guestEmail, { guestEmail = it })
                        FormField("العنوان", guestAddress, { guestAddress = it })
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

                        // Live nights preview — Dart _recalculateExpectedNights
                        // (l.981-1000) uses Time.nightsWithCutoff.
                        val checkinMillis = HotelTimeEngine.parseDate(checkinDate)
                        val checkoutMillis = HotelTimeEngine.parseDate(checkoutDate)
                        if (checkinMillis != null) {
                            val nights = if (checkoutMillis == null) 1
                            else HotelTimeEngine.nightsWithCutoff(checkinMillis, checkoutMillis)
                            Text(
                                "عدد الليالي المحتسب (حد 14:01): $nights",
                                style = AppTypography.bodySmall,
                                color = AppColors.PrimaryColor,
                                fontWeight = FontWeight.SemiBold
                            )
                        }

                        // Dart status dropdown (l.416-428) — includes the
                        // auto-checkout path when set to مكتمل.
                        DropdownField(
                            "حالة الحجز" + if (status.isBlank()) " (افتراضي حسب الوقت)" else "",
                            status.ifBlank { "تلقائي" },
                            listOf("تلقائي") + BOOKING_STATUSES
                        ) { status = if (it == "تلقائي") "" else it }

                        // Dart l.440-450 — read-only actual checkout display.
                        booking?.actualCheckout?.let {
                            Text(
                                "المغادرة الفعلية: ${it.take(16)}",
                                style = AppTypography.bodySmall, color = AppColors.TextSecondary
                            )
                        }
                    }

                    // Dart advance-payment section (l.456-539).
                    FormSection("دفعة مقدمة") {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(checked = advanceEnabled, onCheckedChange = { advanceEnabled = it })
                            Text("تسجيل دفعة مقدمة عند الحفظ", style = AppTypography.bodyMedium)
                        }
                        if (advanceEnabled) {
                            FormField("مبلغ الدفعة المقدمة *", advanceAmount, { advanceAmount = it })
                            DropdownField("طريقة الدفع", advanceMethod, PAYMENT_METHODS) { advanceMethod = it }
                            FormField("ملاحظات", advanceNotes, { advanceNotes = it })
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
                        onClick = { viewModel.save(currentForm()) },
                        enabled = !state.isSaving,
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryColor),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text(
                            if (state.isSaving) "جاري الحفظ..." else "حفظ الحجز",
                            color = Color.White, fontWeight = FontWeight.Bold
                        )
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

/** Exposed dropdown (Material3) used for ID type / status / payment method. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DropdownField(label: String, value: String, options: List<String>, onChange: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it }
    ) {
        OutlinedTextField(
            value = value,
            onValueChange = {},
            readOnly = true,
            modifier = Modifier.fillMaxWidth().menuAnchor(),
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) }
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option) },
                    onClick = {
                        onChange(option)
                        expanded = false
                    }
                )
            }
        }
    }
}
