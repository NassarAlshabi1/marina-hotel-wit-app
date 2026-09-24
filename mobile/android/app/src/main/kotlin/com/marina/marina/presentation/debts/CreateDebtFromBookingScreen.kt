package com.marina.marina.presentation.debts

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.Calculate
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Note
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.util.PdfExporter
import java.util.Calendar
import kotlinx.coroutines.launch

// ─── Flutter shade constants used by create_debt_from_booking.dart ───
private val FlutterOrange = Color(0xFFFF9800)
private val FlutterGreen = Color(0xFF4CAF50)
private val FlutterRed = Color(0xFFF44336)
private val FlutterGrey = Color(0xFF9E9E9E)
private val TitleStyle = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold)
private val LabelStyle = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Bold)
private val FieldStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold)

/** yyyy-MM-dd of a DatePicker selection (UTC millis — formatted in UTC). */
private fun cdUtcDateText(millis: Long): String {
    val cal = Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
    cal.timeInMillis = millis
    return "%04d-%02d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))
}

/**
 * شاشة «إنشاء دين من حجز» — نقل 1:1 لـ create_debt_from_booking.dart:
 * اختيار حجز نشط → معلومات الحجز → فترة الدين (من/إلى) → احسب الدين →
 * ملخص الدين → المبلغ والملاحظات → إنشاء الدين + حوار تأكيد المغادرة.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateDebtFromBookingScreen(
    viewModel: CreateDebtFromBookingViewModel = hiltViewModel(),
    bookingId: Long = 0L,
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    var snackbarColor by remember { mutableStateOf<Color?>(null) }
    var showDiscardDialog by remember { mutableStateOf(false) }

    LaunchedEffect(bookingId) { viewModel.load(bookingId) }

    LaunchedEffect(state.error) {
        val error = state.error ?: return@LaunchedEffect
        snackbarColor = FlutterRed
        snackbarHostState.showSnackbar(error, duration = SnackbarDuration.Short)
        viewModel.consumeError()
    }

    LaunchedEffect(state.saved) {
        if (state.saved) {
            val amount = CurrencyFormatter.parseAmount(state.amountText) ?: 0.0
            snackbarColor = FlutterGreen
            snackbarHostState.showSnackbar("تم إنشاء الدين بمبلغ ${CurrencyFormatter.formatAmount(amount)}")
            onSaved()
        }
    }

    // ✅ PopScope: منع الرجوع مع تغييرات غير محفوظة + حوار التأكيد.
    BackHandler(enabled = state.hasUnsavedChanges && !state.saved) {
        showDiscardDialog = true
    }

    Scaffold(
        containerColor = AppColors.BackgroundColor,
        snackbarHost = {
            SnackbarHost(snackbarHostState) { data ->
                Snackbar(
                    containerColor = snackbarColor ?: MaterialTheme.colorScheme.inverseSurface,
                    contentColor = if (snackbarColor != null) Color.White else MaterialTheme.colorScheme.inverseOnSurface
                ) { Text(data.visuals.message) }
            }
        },
        topBar = {
            TopAppBar(
                title = { Text("إنشاء دين من حجز") },
                navigationIcon = {
                    IconButton(onClick = {
                        if (state.hasUnsavedChanges && !state.saved) showDiscardDialog = true else onBack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "رجوع")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.SurfaceColor,
                    titleContentColor = AppColors.TextPrimary
                )
            )
        }
    ) { padding ->
        if (state.isLoading) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) { CircularProgressIndicator() }
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            BookingSelector(
                bookings = state.selectableBookings,
                selectedBooking = state.selectedBooking,
                onSelect = viewModel::selectBooking
            )

            state.selectedBooking?.let { booking ->
                Spacer(Modifier.height(16.dp))
                BookingInfo(booking)
                Spacer(Modifier.height(16.dp))
                DateRangeSelector(
                    fromDate = state.fromDate,
                    toDate = state.toDate,
                    onFrom = viewModel::setFromDate,
                    onTo = viewModel::setToDate
                )
                Spacer(Modifier.height(16.dp))
                Button(
                    onClick = viewModel::computeDebt,
                    enabled = !state.isComputing,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    if (state.isComputing) {
                        CircularProgressIndicator(
                            strokeWidth = 2.dp,
                            modifier = Modifier.size(20.dp)
                        )
                    } else {
                        Icon(Icons.Filled.Calculate, contentDescription = null)
                    }
                    Spacer(Modifier.width(8.dp))
                    Text(if (state.isComputing) "جاري الحساب..." else "احسب الدين")
                }

                state.computation?.let { data ->
                    Spacer(Modifier.height(16.dp))
                    DebtSummary(data)
                    Spacer(Modifier.height(16.dp))
                    OutlinedTextField(
                        value = state.amountText,
                        onValueChange = { viewModel.setAmountText(it.filter { ch -> ch.isDigit() || ch == '.' }) },
                        label = { Text("مبلغ الدين", style = LabelStyle) },
                        leadingIcon = { Icon(Icons.Filled.AttachMoney, contentDescription = null) },
                        textStyle = FieldStyle,
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(16.dp))
                    OutlinedTextField(
                        value = state.notes,
                        onValueChange = viewModel::setNotes,
                        label = { Text("ملاحظات", style = LabelStyle) },
                        leadingIcon = { Icon(Icons.Filled.Note, contentDescription = null) },
                        textStyle = FieldStyle,
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(24.dp))
                    Button(
                        onClick = viewModel::createDebt,
                        enabled = !state.isProcessing,
                        modifier = Modifier.fillMaxWidth().height(48.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = FlutterOrange,
                            contentColor = Color.White
                        ),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 16.dp)
                    ) {
                        if (state.isProcessing) {
                            CircularProgressIndicator(
                                strokeWidth = 2.dp,
                                color = Color.White,
                                modifier = Modifier.size(20.dp)
                            )
                        } else {
                            Icon(Icons.Filled.Add, contentDescription = null)
                        }
                        Spacer(Modifier.width(8.dp))
                        Text(if (state.isProcessing) "جاري الإنشاء..." else "إنشاء الدين")
                    }
                }
            }
        }
    }

    // ─── حوار تأكيد المغادرة (Dart _showDiscardDialog) ───
    if (showDiscardDialog) {
        AlertDialog(
            onDismissRequest = { showDiscardDialog = false },
            title = { Text("تأكيد") },
            text = { Text("هل تريد المغادرة بدون حفظ التغييرات؟") },
            confirmButton = {
                TextButton(onClick = {
                    showDiscardDialog = false
                    onBack()
                }) { Text("نعم") }
            },
            dismissButton = {
                TextButton(onClick = { showDiscardDialog = false }) { Text("لا") }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BookingSelector(
    bookings: List<Booking>,
    selectedBooking: Booking?,
    onSelect: (Long) -> Unit
) {
    if (bookings.isEmpty()) {
        Card(modifier = Modifier.fillMaxWidth()) {
            Text("لا توجد حجوزات نشطة", modifier = Modifier.padding(16.dp))
        }
        return
    }
    var expanded by remember { mutableStateOf(false) }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("اختر الحجز", style = TitleStyle)
            Spacer(Modifier.height(8.dp))
            ExposedDropdownMenuBox(
                expanded = expanded,
                onExpandedChange = { expanded = it }
            ) {
                OutlinedTextField(
                    value = selectedBooking?.let { "${it.roomNumber} - ${it.guestName}" } ?: "",
                    onValueChange = {},
                    readOnly = true,
                    enabled = false,
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                    textStyle = TextStyle(
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.TextPrimary
                    ),
                    colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(
                        disabledTextColor = AppColors.TextPrimary,
                        disabledContainerColor = Color.Transparent,
                        disabledBorderColor = Color(0xFF9E9E9E)
                    ),
                    singleLine = true
                )
                ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    bookings.forEach { booking ->
                        androidx.compose.material3.DropdownMenuItem(
                            text = {
                                Text(
                                    "${booking.roomNumber} - ${booking.guestName}",
                                    style = TextStyle(
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = AppColors.TextPrimary
                                    ),
                                    maxLines = 1
                                )
                            },
                            onClick = {
                                onSelect(booking.id)
                                expanded = false
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun BookingInfo(booking: Booking) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text("معلومات الحجز", style = TitleStyle)
            Spacer(Modifier.height(8.dp))
            InfoLine("الغرفة", booking.roomNumber)
            InfoLine("الضيف", booking.guestName)
            InfoLine("الهوية", booking.guestIdNumber)
            InfoLine("تاريخ الدخول", booking.checkinDate.split(" ").firstOrNull() ?: "")
            if (!booking.checkoutDate.isNullOrEmpty()) {
                InfoLine("تاريخ الخروج", booking.checkoutDate.split(" ").firstOrNull() ?: "")
            }
            InfoLine("الحالة", booking.status)
            InfoLine("الإجمالي المستحق", CurrencyFormatter.formatAmount(booking.totalDueCached))
            InfoLine("المدفوع", CurrencyFormatter.formatAmount(booking.totalPaidCached))
            InfoLine("المتبقي", CurrencyFormatter.formatAmount(booking.remainingBalanceCached))
        }
    }
}

@Composable
private fun InfoLine(label: String, value: String) {
    Row(modifier = Modifier.padding(vertical = 3.dp)) {
        Text(
            "$label:",
            style = TextStyle(color = FlutterGrey, fontSize = 13.sp, fontWeight = FontWeight.Bold),
            modifier = Modifier.width(110.dp)
        )
        Text(value, style = FieldStyle, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun DateRangeSelector(
    fromDate: String,
    toDate: String,
    onFrom: (String) -> Unit,
    onTo: (String) -> Unit
) {
    var pickField by remember { mutableStateOf<String?>(null) }
    if (pickField != null) {
        val initialRaw = if (pickField == "from") fromDate else toDate
        val initial = com.marina.marina.domain.util.HotelTimeEngine.parseDate(initialRaw)
            ?: System.currentTimeMillis()
        val pickerState = rememberDatePickerState(initialSelectedDateMillis = initial)
        DatePickerDialog(
            onDismissRequest = { pickField = null },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { picked ->
                        val text = cdUtcDateText(picked)
                        if (pickField == "from") onFrom(text) else onTo(text)
                    }
                    pickField = null
                }) { Text("موافق") }
            },
            dismissButton = {
                TextButton(onClick = { pickField = null }) { Text("إلغاء") }
            }
        ) {
            DatePicker(state = pickerState, showModeToggle = false)
        }
    }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text("فترة الدين", style = TitleStyle)
            Spacer(Modifier.height(8.dp))
            Row {
                Box(modifier = Modifier.weight(1f).clickable { pickField = "from" }) {
                    DateField("من", fromDate)
                }
                Spacer(Modifier.width(16.dp))
                Box(modifier = Modifier.weight(1f).clickable { pickField = "to" }) {
                    DateField("إلى", toDate)
                }
            }
        }
    }
}

@Composable
private fun DateField(label: String, value: String) {
    OutlinedTextField(
        value = value,
        onValueChange = {},
        readOnly = true,
        enabled = false,
        label = { Text(label, style = LabelStyle) },
        textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AppColors.TextPrimary),
        modifier = Modifier.fillMaxWidth(),
        suffix = { Icon(Icons.Filled.CalendarToday, contentDescription = null, modifier = Modifier.size(18.dp)) },
        singleLine = true,
        colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
            disabledContainerColor = Color.Transparent,
            disabledTextColor = AppColors.TextPrimary,
            disabledBorderColor = Color(0xFF9E9E9E),
            disabledLabelColor = AppColors.TextPrimary,
            disabledSuffixColor = AppColors.TextPrimary
        )
    )
}

@Composable
private fun DebtSummary(data: DebtComputation) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF3E0))
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text("ملخص الدين", style = TitleStyle)
            Spacer(Modifier.height(8.dp))
            InfoLine("عدد الليالي", "${data.nights}")
            InfoLine("سعر الليلة", CurrencyFormatter.formatAmount(data.roomRate))
            InfoLine("الإجمالي", CurrencyFormatter.formatAmount(data.total))
            InfoLine("المدفوع", CurrencyFormatter.formatAmount(data.paid))
            androidx.compose.material3.HorizontalDivider()
            InfoLine("المتبقي (الدين)", CurrencyFormatter.formatAmount(data.remaining))
        }
    }
}
