package com.marina.marina.presentation.debts

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Login
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.AddCircle
import androidx.compose.material.icons.outlined.Hotel
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.components.SidebarMenuButton
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.util.PdfExporter
import java.util.Calendar
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// ─── Flutter Colors.* shades used by debts_list.dart (exact ARGB values) ───
private val Green50 = Color(0xFFE8F5E9)
private val Green300 = Color(0xFF81C784)
private val Green700 = Color(0xFF388E3C)
private val FlutterGreen = Color(0xFF4CAF50)
private val Red50 = Color(0xFFFFEBEE)
private val Red300 = Color(0xFFE57373)
private val Red700 = Color(0xFFD32F2F)
private val Red900 = Color(0xFFB71C1C)
private val FlutterRed = Color(0xFFF44336)
private val Red400 = Color(0xFFEF5350)
private val Orange50 = Color(0xFFFFF3E0)
private val Orange300 = Color(0xFFFFB74D)
private val Orange200 = Color(0xFFFFCC80)
private val FlutterOrange = Color(0xFFFF9800)
private val Blue50 = Color(0xFFE3F2FD)
private val Blue100 = Color(0xFFBBDEFB)
private val Blue200 = Color(0xFF90CAF9)
private val Blue600 = Color(0xFF1E88E5)
private val Blue700 = Color(0xFF1976D2)
private val Blue800 = Color(0xFF1565C0)
private val Blue900 = Color(0xFF0D47A1)
private val FlutterBlue = Color(0xFF2196F3)
private val Grey50 = Color(0xFFFAFAFA)
private val Grey200 = Color(0xFFEEEEEE)
private val Grey300 = Color(0xFFE0E0E0)
private val Grey400 = Color(0xFFBDBDBD)
private val Grey500 = Color(0xFF9E9E9E)
private val Grey600 = Color(0xFF757575)
private val FlutterGrey = Color(0xFF9E9E9E)

/** Dart Time.safeIsoToDateString — empty/unparseable falls back to today. */
internal fun debtsSafeIsoToDateString(value: String?): String {
    val today = HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10)
    if (value.isNullOrEmpty()) return today
    return try {
        if (value.length >= 10 && value.contains('-')) value.take(10)
        else HotelTimeEngine.formatIso(HotelTimeEngine.parseDate(value) ?: System.currentTimeMillis()).take(10)
    } catch (_: Exception) {
        today
    }
}

/** yyyy-MM-dd of a DatePicker selection (UTC millis — formatted in UTC to stay on the picked day). */
internal fun utcDateText(millis: Long): String {
    val cal = Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
    cal.timeInMillis = millis
    return "%04d-%02d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DebtsListScreen(
    onCreateFromBooking: () -> Unit = {},
    viewModel: DebtsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    var snackbarColor by remember { mutableStateOf<Color?>(null) }

    var showQuickAddMenu by remember { mutableStateOf(false) }
    var showEditDialog by remember { mutableStateOf(false) }
    var editingDebt by remember { mutableStateOf<Debt?>(null) }
    var partialPaymentDebt by remember { mutableStateOf<Debt?>(null) }
    var settleConfirmDebt by remember { mutableStateOf<Debt?>(null) }
    var deleteConfirmDebt by remember { mutableStateOf<Debt?>(null) }

    // حقل البحث المحلي مع مُهجّئ 300ms (Dart Timer _debounceTimer).
    var searchText by remember { mutableStateOf(state.searchQuery) }
    LaunchedEffect(searchText) {
        delay(300)
        if (searchText != state.searchQuery) viewModel.setSearchQuery(searchText)
    }

    LaunchedEffect(state.message) {
        val msg = state.message ?: return@LaunchedEffect
        snackbarColor = when (msg.kind) {
            DebtsMsgKind.DEFAULT -> null
            DebtsMsgKind.SUCCESS_GREEN -> FlutterGreen
            DebtsMsgKind.ERROR_RED -> FlutterRed
            DebtsMsgKind.ERROR_RED900 -> Red900
            DebtsMsgKind.ORANGE -> FlutterOrange
            DebtsMsgKind.BLUE -> FlutterBlue
        }
        snackbarHostState.showSnackbar(msg.text, duration = SnackbarDuration.Short)
        viewModel.consumeMessage()
    }

    // ✅ مشاركة واتساب عبر نية النظام (نظير whatsappService.sendMessage في Dart).
    LaunchedEffect(state.share) {
        val share = state.share ?: return@LaunchedEffect
        try {
            PdfExporter.openWhatsAppText(context, share.phoneE164, share.message)
            snackbarColor = FlutterGreen
            snackbarHostState.showSnackbar("تم إرسال تنبيه واتساب لـ ${share.guestName}")
        } catch (_: Exception) {
            snackbarColor = FlutterRed
            snackbarHostState.showSnackbar("تعذّر إرسال واتساب لـ ${share.guestName}")
        }
        viewModel.consumeShare()
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
                title = { Text("إدارة الديون") },
                navigationIcon = { SidebarMenuButton() },
                actions = {
                    IconButton(onClick = { showQuickAddMenu = true }) {
                        Icon(Icons.Filled.AddCircle, contentDescription = "إضافة دين جديد")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.SurfaceColor,
                    titleContentColor = AppColors.TextPrimary
                )
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            SearchAndFilters(
                searchText = searchText,
                onSearchText = { searchText = it },
                filterStatus = state.statusFilter,
                onFilterStatus = viewModel::setStatusFilter
            )

            QuickStats(state)

            when {
                state.isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                state.error != null -> Column(
                    modifier = Modifier.fillMaxSize().padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Icon(Icons.Filled.Error, contentDescription = null, tint = Red400, modifier = Modifier.size(64.dp))
                    Spacer(Modifier.height(16.dp))
                    Text("حدث خطأ في تحميل البيانات", color = Red700, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text(state.error ?: "", color = FlutterGrey)
                }
                else -> {
                    val debts = state.filtered
                    if (debts.isEmpty()) {
                        EmptyState(state.searchQuery, state.statusFilter)
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(16.dp)
                        ) {
                            items(debts, key = { it.id }) { debt ->
                                DebtCard(
                                    debt = debt,
                                    onSettle = { settleConfirmDebt = debt },
                                    onPartialPayment = { partialPaymentDebt = debt },
                                    onWhatsApp = { viewModel.sendDebtWhatsApp(debt) },
                                    onEdit = {
                                        editingDebt = debt
                                        showEditDialog = true
                                    },
                                    onDelete = { deleteConfirmDebt = debt }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // ─── قائمة الإضافة السريعة (Dart _showQuickAddMenu) ───
    if (showQuickAddMenu) {
        ModalBottomSheet(onDismissRequest = { showQuickAddMenu = false }) {
            Column(modifier = Modifier.padding(20.dp)) {
                Text("إضافة دين جديد", fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(16.dp))
                ListItem(
                    headlineContent = { Text("دين من حجز موجود") },
                    supportingContent = { Text("اختر حجز وأنشئ دين بناء على الأيام المتبقية") },
                    leadingContent = { Icon(Icons.Outlined.Hotel, contentDescription = null, tint = FlutterBlue) },
                    modifier = Modifier.clickable {
                        showQuickAddMenu = false
                        onCreateFromBooking()
                    }
                )
                ListItem(
                    headlineContent = { Text("دين يدوي") },
                    supportingContent = { Text("أدخل تفاصيل الدين يدوياً") },
                    leadingContent = { Icon(Icons.Outlined.AddCircle, contentDescription = null, tint = FlutterGreen) },
                    modifier = Modifier.clickable {
                        showQuickAddMenu = false
                        editingDebt = null
                        showEditDialog = true
                    }
                )
            }
        }
    }

    // ─── تأكيد السداد (Dart _markAsSettled) ───
    settleConfirmDebt?.let { debt ->
        AlertDialog(
            onDismissRequest = { settleConfirmDebt = null },
            title = { Text("تأكيد السداد") },
            text = { Text("هل تريد تسجيل دين \"${debt.guestName}\" كمسدد؟") },
            confirmButton = {
                Button(
                    onClick = {
                        viewModel.settleDebt(debt)
                        settleConfirmDebt = null
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = FlutterGreen)
                ) { Text("تأكيد السداد") }
            },
            dismissButton = {
                TextButton(onClick = { settleConfirmDebt = null }) { Text("إلغاء") }
            }
        )
    }

    // ─── السداد الجزئي (Dart _showPartialPaymentDialog) ───
    partialPaymentDebt?.let { debt ->
        PartialPaymentDialog(
            debt = debt,
            onDismiss = { partialPaymentDebt = null },
            onConfirm = { amount, date, note ->
                viewModel.addPartialPayment(debt, amount, date, note)
                partialPaymentDebt = null
            }
        )
    }

    // ─── حوار إضافة/تعديل دين (Dart _openDebtForm) ───
    if (showEditDialog) {
        DebtFormDialog(
            existing = editingDebt,
            onValidationError = { text, orange ->
                snackbarColor = if (orange) FlutterOrange else null
                scope.launch { snackbarHostState.showSnackbar(text) }
            },
            onDismiss = { showEditDialog = false; editingDebt = null },
            onSave = { form ->
                viewModel.saveDebt(
                    existing = editingDebt,
                    guestName = form.guestName,
                    checkinDate = form.checkinDate,
                    checkoutDate = form.checkoutDate,
                    totalAmount = form.totalAmount,
                    paidAmount = form.paidAmount,
                    debtReason = form.debtReason,
                    pledge = form.pledge,
                    pledgeType = form.pledgeType,
                    note = form.note
                )
                showEditDialog = false
                editingDebt = null
            }
        )
    }

    // ─── تأكيد الحذف (Dart _deleteDebt) ───
    deleteConfirmDebt?.let { debt ->
        AlertDialog(
            onDismissRequest = { deleteConfirmDebt = null },
            title = { Text("تأكيد الحذف") },
            text = {
                Text("هل أنت متأكد من حذف دين \"${debt.guestName}\"؟\n\nهذا الإجراء لا يمكن التراجع عنه.")
            },
            confirmButton = {
                Button(
                    onClick = {
                        viewModel.deleteDebt(debt)
                        deleteConfirmDebt = null
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = FlutterRed)
                ) { Text("حذف") }
            },
            dismissButton = {
                TextButton(onClick = { deleteConfirmDebt = null }) { Text("إلغاء") }
            }
        )
    }
}

@Composable
private fun SearchAndFilters(
    searchText: String,
    onSearchText: (String) -> Unit,
    filterStatus: String,
    onFilterStatus: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Grey50)
            .padding(16.dp)
    ) {
        OutlinedTextField(
            value = searchText,
            onValueChange = onSearchText,
            modifier = Modifier.fillMaxWidth(),
            placeholder = {
                Text("ابحث باسم النزيل أو رقم الغرفة...", color = Grey500, fontWeight = FontWeight.Normal)
            },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            shape = RoundedCornerShape(25.dp),
            textStyle = TextStyle(fontWeight = FontWeight.Bold),
            singleLine = true
        )
        Spacer(Modifier.height(12.dp))
        Row(modifier = Modifier.fillMaxWidth()) {
            FilterChipOption("الكل", "all", filterStatus, onFilterStatus, Modifier.weight(1f))
            Spacer(Modifier.width(8.dp))
            FilterChipOption("معلق", "pending", filterStatus, onFilterStatus, Modifier.weight(1f))
            Spacer(Modifier.width(8.dp))
            FilterChipOption("مسدد", "settled", filterStatus, onFilterStatus, Modifier.weight(1f))
            Spacer(Modifier.width(8.dp))
            FilterChipOption("متأخر", "overdue", filterStatus, onFilterStatus, Modifier.weight(1f))
        }
    }
}

@Composable
private fun FilterChipOption(
    label: String,
    value: String,
    selectedValue: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    FilterChip(
        selected = selectedValue == value,
        onClick = { onSelect(value) },
        label = { Text(label, fontWeight = FontWeight.Bold) },
        modifier = modifier,
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = Blue100,
            selectedLeadingIconColor = Blue700
        )
    )
}

@Composable
private fun QuickStats(state: DebtsUiState) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        StatCard("إجمالي الديون", state.totalDebts.toString(), FlutterBlue, Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        StatCard("معلق", state.pendingDebts.toString(), FlutterOrange, Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        StatCard("القيمة الإجمالية", CurrencyFormatter.formatAmount(state.totalRemaining), FlutterRed, Modifier.weight(1f))
    }
}

@Composable
private fun StatCard(title: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(8.dp))
            .border(1.dp, color.copy(alpha = 0.3f), RoundedCornerShape(8.dp))
            .padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = color)
        Spacer(Modifier.height(4.dp))
        Text(
            title,
            fontSize = 10.sp,
            color = color.copy(alpha = 0.8f),
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun EmptyState(searchQuery: String, filterStatus: String) {
    val emptyMessage = when {
        searchQuery.isNotEmpty() -> "لا توجد نتائج للبحث \"$searchQuery\""
        filterStatus != "all" -> "لا توجد ديون في هذه الفئة"
        else -> "لا توجد ديون"
    }
    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(Icons.Outlined.AccountBalance, contentDescription = null, tint = Grey400, modifier = Modifier.size(64.dp))
        Spacer(Modifier.height(16.dp))
        Text(emptyMessage, fontSize = 18.sp, color = FlutterGrey, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Text("اضغط على + لإضافة دين جديد", color = FlutterGrey, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun DebtCard(
    debt: Debt,
    onSettle: () -> Unit,
    onPartialPayment: () -> Unit,
    onWhatsApp: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    val isSettled = debt.isSettled || debt.remainingAmount <= 0
    val debtDate = HotelTimeEngine.parseDate(debt.dateRecorded.ifEmpty { debt.checkoutDate })
    val daysPassed = debtDate?.let {
        TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis() - it)
    } ?: 0L
    val isOverdue = daysPassed > 30 && !isSettled

    val cardColor: Color
    val borderColor: Color
    if (isSettled) {
        cardColor = Green50; borderColor = Green300
    } else if (isOverdue) {
        cardColor = Red50; borderColor = Red300
    } else {
        cardColor = Orange50; borderColor = Orange300
    }

    Card(
        modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp),
        colors = CardDefaults.cardColors(containerColor = cardColor),
        shape = RoundedCornerShape(8.dp),
        border = BorderStroke(1.dp, borderColor)
    ) {
        Column(modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
            // الرأس
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    debt.guestName,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
                StatusBadge(debt)
            }
            Spacer(Modifier.height(4.dp))

            // التواريخ والسبب
            Row {
                Box(Modifier.weight(1f)) {
                    InfoRow(Icons.Filled.Login, "الدخول", debtsSafeIsoToDateString(debt.checkinDate))
                }
                Box(Modifier.weight(1f)) {
                    InfoRow(Icons.Filled.Logout, "الخروج", debtsSafeIsoToDateString(debt.checkoutDate))
                }
            }

            if (debt.debtReason.isNotEmpty()) {
                Spacer(Modifier.height(2.dp))
                InfoRow(Icons.Filled.Info, "السبب", debt.debtReason)
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp), color = Grey300)

            // المبالغ
            Row {
                AmountColumn("إجمالي", CurrencyFormatter.formatAmount(debt.totalAmount), AppColors.TextPrimary, Modifier.weight(1f))
                AmountColumn("المدفوع", CurrencyFormatter.formatAmount(debt.paidAmount), Green700, Modifier.weight(1f))
                AmountColumn("المتبقي", CurrencyFormatter.formatAmount(debt.remainingAmount), Red700, Modifier.weight(1f))
            }

            // الرهن
            if (!debt.pledge.isNullOrEmpty()) {
                Spacer(Modifier.height(4.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Blue50, RoundedCornerShape(4.dp))
                        .border(1.dp, Blue200, RoundedCornerShape(4.dp))
                        .padding(horizontal = 6.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.Security, contentDescription = null, tint = Blue700, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(
                        "رهن: ${debt.pledge}" + if (!debt.pledgeType.isNullOrEmpty()) " (${debt.pledgeType})" else "",
                        fontSize = 9.sp,
                        color = Blue700,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            // الملاحظة (النص الحر فقط — النص JSON هو سجل الدفعات)
            val freeNote = debt.note?.takeIf { it.isNotEmpty() && !it.startsWith("{") }
            if (freeNote != null) {
                Spacer(Modifier.height(4.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Grey50, RoundedCornerShape(4.dp))
                        .border(1.dp, Grey200, RoundedCornerShape(4.dp))
                        .padding(horizontal = 6.dp, vertical = 4.dp)
                ) {
                    Text(freeNote, fontSize = 9.sp, fontWeight = FontWeight.Bold)
                }
            }

            PaymentHistory(debt.note)

            Spacer(Modifier.height(6.dp))

            // أزرار الإجراءات — مدمجة وصغيرة
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (!isSettled) {
                    ElevatedButton(
                        onClick = onSettle,
                        modifier = Modifier.weight(1f).height(28.dp),
                        contentPadding = PaddingValues(vertical = 4.dp, horizontal = 4.dp),
                        colors = ButtonDefaults.elevatedButtonColors(containerColor = FlutterGreen, contentColor = Color.White)
                    ) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = null, modifier = Modifier.size(12.dp))
                        Spacer(Modifier.width(2.dp))
                        Text("سداد كامل", fontSize = 9.sp, maxLines = 1)
                    }
                    Spacer(Modifier.width(4.dp))
                    ElevatedButton(
                        onClick = onPartialPayment,
                        modifier = Modifier.weight(1f).height(28.dp),
                        contentPadding = PaddingValues(vertical = 4.dp, horizontal = 4.dp),
                        colors = ButtonDefaults.elevatedButtonColors(containerColor = Blue600, contentColor = Color.White)
                    ) {
                        Icon(Icons.Filled.Payments, contentDescription = null, modifier = Modifier.size(12.dp))
                        Spacer(Modifier.width(2.dp))
                        Text("سداد جزئي", fontSize = 9.sp, maxLines = 1)
                    }
                    Spacer(Modifier.width(4.dp))
                }
                OutlinedButton(
                    onClick = onWhatsApp,
                    modifier = Modifier.weight(1f).height(28.dp),
                    contentPadding = PaddingValues(vertical = 4.dp, horizontal = 4.dp),
                    border = BorderStroke(1.dp, FlutterGreen),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = FlutterGreen)
                ) {
                    Icon(Icons.Filled.Chat, contentDescription = null, modifier = Modifier.size(12.dp), tint = FlutterGreen)
                    Spacer(Modifier.width(2.dp))
                    Text("واتساب", fontSize = 10.sp, maxLines = 1)
                }
                Spacer(Modifier.width(4.dp))
                OutlinedButton(
                    onClick = onEdit,
                    modifier = Modifier.weight(1f).height(28.dp),
                    contentPadding = PaddingValues(vertical = 4.dp, horizontal = 4.dp)
                ) {
                    Icon(Icons.Filled.Edit, contentDescription = null, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(2.dp))
                    Text("تعديل", fontSize = 10.sp, maxLines = 1)
                }
                Spacer(Modifier.width(4.dp))
                OutlinedButton(
                    onClick = onDelete,
                    modifier = Modifier.height(28.dp),
                    contentPadding = PaddingValues(4.dp),
                    border = BorderStroke(1.dp, FlutterRed),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = FlutterRed)
                ) {
                    Icon(Icons.Filled.Delete, contentDescription = null, modifier = Modifier.size(12.dp))
                }
            }
        }
    }
}

@Composable
private fun StatusBadge(debt: Debt) {
    val isSettled = debt.isSettled || debt.remainingAmount <= 0
    val debtDate = HotelTimeEngine.parseDate(debt.dateRecorded.ifEmpty { debt.checkoutDate })
    val daysPassed = debtDate?.let {
        TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis() - it)
    } ?: 0L
    val isOverdue = daysPassed > 30 && !isSettled && debt.remainingAmount > 0

    val text: String
    val color: Color
    if (isSettled) {
        text = "مسدد"; color = FlutterGreen
    } else if (isOverdue) {
        text = "متأخر ($daysPassed يوم)"; color = FlutterRed
    } else if (debt.remainingAmount > 0) {
        text = "معلق"; color = FlutterOrange
    } else {
        text = "مسدد"; color = FlutterGreen
    }

    Box(
        modifier = Modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(12.dp))
            .border(1.dp, color, RoundedCornerShape(12.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Text(text, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = color)
    }
}

@Composable
private fun InfoRow(icon: ImageVector, label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = Grey600, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(4.dp))
        Text("$label: ", color = Grey600, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        Text(value, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun AmountColumn(label: String, value: String, valueColor: Color, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Text(label, color = Grey600, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        Text(value, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = valueColor)
    }
}

@Composable
private fun PaymentHistory(rawNote: String?) {
    val payments = remember(rawNote) { parsePaymentLogForDisplay(rawNote) }
    if (payments.isEmpty()) return

    Spacer(Modifier.height(4.dp))
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Blue50, RoundedCornerShape(4.dp))
            .border(1.dp, Blue200, RoundedCornerShape(4.dp))
            .padding(horizontal = 6.dp, vertical = 4.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.History, contentDescription = null, tint = Blue700, modifier = Modifier.size(12.dp))
            Spacer(Modifier.width(4.dp))
            Text(
                "سجل الدفعات (${payments.size})",
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = Blue900
            )
        }
        Spacer(Modifier.height(2.dp))
        payments.forEach { (amount, date, note) ->
            Row(
                modifier = Modifier.padding(vertical = 1.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "${debtsSafeIsoToDateString(date)}" + if (note.isNotEmpty()) " — $note" else "",
                    fontSize = 9.sp,
                    color = Blue800,
                    modifier = Modifier.weight(1f),
                    maxLines = 1
                )
                Text(
                    "- ${CurrencyFormatter.formatAmount(amount)}",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = Green700
                )
            }
        }
    }
}

/** Parses the JSON payment log for display (Dart _parsePaymentHistory). */
private fun parsePaymentLogForDisplay(rawNote: String?): List<Triple<Double, String, String>> {
    if (rawNote.isNullOrEmpty() || !rawNote.startsWith("{")) return emptyList()
    return try {
        val root = com.google.gson.JsonParser.parseString(rawNote).asJsonObject
        val arr = root.getAsJsonArray("payments") ?: return emptyList()
        arr.mapNotNull { el ->
            val obj = el.asJsonObject
            val amount = obj.get("amount")?.asDouble ?: return@mapNotNull null
            Triple(amount, obj.get("date")?.asString ?: "", obj.get("note")?.asString ?: "")
        }
    } catch (_: Exception) {
        emptyList()
    }
}

// ─── حوار السداد الجزئي ───

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PartialPaymentDialog(
    debt: Debt,
    onDismiss: () -> Unit,
    onConfirm: (Double, String, String) -> Unit
) {
    var amount by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var selectedDateMillis by remember { mutableStateOf(System.currentTimeMillis()) }
    val dateText = utcDateText(selectedDateMillis)
    var showDatePicker by remember { mutableStateOf(false) }

    if (showDatePicker) {
        val pickerState = rememberDatePickerState(initialSelectedDateMillis = selectedDateMillis)
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        pickerState.selectedDateMillis?.let { selectedDateMillis = it }
                        showDatePicker = false
                    }
                ) { Text("موافق") }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) { Text("إلغاء") }
            }
        ) {
            DatePicker(state = pickerState, showModeToggle = false)
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Payments, contentDescription = null, tint = FlutterBlue)
                Spacer(Modifier.width(8.dp))
                Text("سداد جزئي")
            }
        },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                Text("النزيل: ${debt.guestName}", fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp))
                Text("إجمالي الدين: ${CurrencyFormatter.formatAmount(debt.totalAmount)}")
                Text("المدفوع: ${CurrencyFormatter.formatAmount(debt.paidAmount)}")
                Text(
                    "المتبقي: ${CurrencyFormatter.formatAmount(debt.remainingAmount)}",
                    fontWeight = FontWeight.Bold,
                    color = FlutterRed
                )
                HorizontalDivider()
                Text("مبلغ الدفعة:", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp))
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { ch -> ch.isDigit() || ch == '.' } },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("0") },
                    leadingIcon = { Icon(Icons.Filled.AttachMoney, contentDescription = null, modifier = Modifier.size(18.dp)) },
                    suffix = { Text("ريال") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold)
                )
                Spacer(Modifier.height(8.dp))
                Text("تاريخ الدفعة:", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp))
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { showDatePicker = true }
                ) {
                    OutlinedTextField(
                        value = dateText,
                        onValueChange = {},
                        readOnly = true,
                        modifier = Modifier.fillMaxWidth(),
                        leadingIcon = { Icon(Icons.Filled.CalendarToday, contentDescription = null, modifier = Modifier.size(16.dp)) },
                        textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    )
                }
                Spacer(Modifier.height(8.dp))
                Text("ملاحظة (اختياري):", fontSize = 12.sp)
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("مثلاً: دفعة أولى") },
                    singleLine = true,
                    textStyle = TextStyle(fontSize = 12.sp)
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val parsed = CurrencyFormatter.parseAmount(amount) ?: 0.0
                    onConfirm(parsed, dateText, note)
                },
                colors = ButtonDefaults.buttonColors(containerColor = FlutterBlue)
            ) { Text("تسجيل الدفعة") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

// ─── حوار إضافة/تعديل دين (Dart _openDebtForm) ───

private data class DebtForm(
    val guestName: String,
    val checkinDate: String,
    val checkoutDate: String,
    val totalAmount: Double,
    val paidAmount: Double,
    val debtReason: String,
    val pledge: String?,
    val pledgeType: String?,
    val note: String?
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DebtFormDialog(
    existing: Debt?,
    onValidationError: (String, Boolean) -> Unit,
    onDismiss: () -> Unit,
    onSave: (DebtForm) -> Unit
) {
    var guestName by remember { mutableStateOf(existing?.guestName ?: "") }
    var checkinDate by remember { mutableStateOf(debtsSafeIsoToDateString(existing?.checkinDate)) }
    var checkoutDate by remember { mutableStateOf(debtsSafeIsoToDateString(existing?.checkoutDate)) }
    var total by remember { mutableStateOf(existing?.let { CurrencyFormatter.formatAmount(it.totalAmount) } ?: "0") }
    var paid by remember { mutableStateOf(existing?.let { CurrencyFormatter.formatAmount(it.paidAmount) } ?: "0") }
    // Dart recalculate(): remaining = total - paid (clamp 0) — يُعاد حسابه حياً.
    val totalParsed = CurrencyFormatter.parseAmount(total) ?: 0.0
    val paidParsed = CurrencyFormatter.parseAmount(paid) ?: 0.0
    val remaining = (totalParsed - paidParsed).coerceAtLeast(0.0)
    var debtReason by remember { mutableStateOf(existing?.debtReason ?: "عدم سداد قيمة أيام إضافية") }
    var pledge by remember { mutableStateOf(existing?.pledge ?: "") }
    var pledgeType by remember { mutableStateOf(existing?.pledgeType ?: "") }
    var note by remember { mutableStateOf(existing?.note?.takeIf { !it.startsWith("{") } ?: "") }

    var pickField by remember { mutableStateOf<String?>(null) } // "checkin" | "checkout"

    if (pickField != null) {
        val initial = HotelTimeEngine.parseDate(if (pickField == "checkin") checkinDate else checkoutDate)
            ?: System.currentTimeMillis()
        val pickerState = rememberDatePickerState(initialSelectedDateMillis = initial)
        DatePickerDialog(
            onDismissRequest = { pickField = null },
            confirmButton = {
                TextButton(
                    onClick = {
                        pickerState.selectedDateMillis?.let { picked ->
                            val text = utcDateText(picked)
                            if (pickField == "checkin") checkinDate = text else checkoutDate = text
                        }
                        pickField = null
                    }
                ) { Text("موافق") }
            },
            dismissButton = { TextButton(onClick = { pickField = null }) { Text("إلغاء") } }
        ) {
            DatePicker(state = pickerState, showModeToggle = false)
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                if (existing == null) "إضافة دين جديد" else "تعديل الدين",
                fontSize = 14.sp, fontWeight = FontWeight.Bold
            )
        },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                OutlinedTextField(
                    value = guestName,
                    onValueChange = { guestName = it },
                    label = { Text("اسم النزيل*", fontSize = 13.sp, fontWeight = FontWeight.Bold) },
                    textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold),
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                Spacer(Modifier.height(12.dp))
                Row {
                    Box(modifier = Modifier.weight(1f).clickable { pickField = "checkin" }) {
                        OutlinedTextField(
                            value = checkinDate,
                            onValueChange = {},
                            readOnly = true,
                            enabled = false,
                            label = { Text("تاريخ الدخول", fontSize = 13.sp, fontWeight = FontWeight.Bold) },
                            textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AppColors.TextPrimary),
                            modifier = Modifier.fillMaxWidth(),
                            suffix = { Icon(Icons.Filled.CalendarToday, contentDescription = null, modifier = Modifier.size(18.dp)) },
                            singleLine = true,
                            colors = OutlinedTextFieldDefaults.colors(
                                disabledContainerColor = Color.Transparent,
                                disabledTextColor = AppColors.TextPrimary,
                                disabledBorderColor = Grey500,
                                disabledLabelColor = Grey600,
                                disabledSuffixColor = AppColors.TextPrimary
                            )
                        )
                    }
                    Spacer(Modifier.width(8.dp))
                    Box(modifier = Modifier.weight(1f).clickable { pickField = "checkout" }) {
                        OutlinedTextField(
                            value = checkoutDate,
                            onValueChange = {},
                            readOnly = true,
                            enabled = false,
                            label = { Text("تاريخ الخروج", fontSize = 13.sp, fontWeight = FontWeight.Bold) },
                            textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AppColors.TextPrimary),
                            modifier = Modifier.fillMaxWidth(),
                            suffix = { Icon(Icons.Filled.CalendarToday, contentDescription = null, modifier = Modifier.size(18.dp)) },
                            singleLine = true,
                            colors = OutlinedTextFieldDefaults.colors(
                                disabledContainerColor = Color.Transparent,
                                disabledTextColor = AppColors.TextPrimary,
                                disabledBorderColor = Grey500,
                                disabledLabelColor = Grey600,
                                disabledSuffixColor = AppColors.TextPrimary
                            )
                        )
                    }
                }
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = debtReason,
                    onValueChange = { debtReason = it },
                    label = { Text("سبب الدين", fontSize = 13.sp, fontWeight = FontWeight.Bold) },
                    textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold),
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                Spacer(Modifier.height(12.dp))
                Row {
                    OutlinedTextField(
                        value = total,
                        onValueChange = { total = it.filter { ch -> ch.isDigit() || ch == '.' } },
                        label = { Text("إجمالي المبلغ*", fontSize = 13.sp, fontWeight = FontWeight.Bold) },
                        textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold),
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                    )
                    Spacer(Modifier.width(8.dp))
                    OutlinedTextField(
                        value = paid,
                        onValueChange = { paid = it.filter { ch -> ch.isDigit() || ch == '.' } },
                        label = { Text("المدفوع", fontSize = 13.sp, fontWeight = FontWeight.Bold) },
                        textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold),
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                    )
                }
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = CurrencyFormatter.formatAmount(remaining),
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("المتبقي", fontSize = 13.sp, fontWeight = FontWeight.Bold) },
                    textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold),
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                Spacer(Modifier.height(12.dp))
                Row {
                    OutlinedTextField(
                        value = pledge,
                        onValueChange = { pledge = it },
                        label = { Text("الرهن", fontSize = 13.sp, fontWeight = FontWeight.Bold) },
                        textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold),
                        modifier = Modifier.weight(1f),
                        singleLine = true
                    )
                    Spacer(Modifier.width(8.dp))
                    OutlinedTextField(
                        value = pledgeType,
                        onValueChange = { pledgeType = it },
                        label = { Text("نوع الرهن", fontSize = 13.sp, fontWeight = FontWeight.Bold) },
                        textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold),
                        modifier = Modifier.weight(1f),
                        singleLine = true
                    )
                }
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("ملاحظة إضافية", fontSize = 13.sp, fontWeight = FontWeight.Bold) },
                    textStyle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold),
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                    maxLines = 2
                )
            }
        },
        confirmButton = {
            Button(onClick = {
                // ✅ التحقق داخل الحوار قبل الإغلاق (نفس رسائل Dart).
                val name = guestName.trim()
                if (name.isEmpty()) {
                    onValidationError("يرجى إدخال اسم النزيل", false)
                    return@Button
                }
                val t = CurrencyFormatter.parseAmount(total) ?: 0.0
                if (t <= 0) {
                    onValidationError("يجب إدخال مبلغ الدين الكلي أكبر من صفر", false)
                    return@Button
                }
                val p = CurrencyFormatter.parseAmount(paid) ?: 0.0
                if (p > t) {
                    onValidationError("المبلغ المدفوع لا يمكن أن يتجاوز إجمالي الدين", true)
                    return@Button
                }
                onSave(
                    DebtForm(
                        guestName = name,
                        checkinDate = checkinDate.trim().ifEmpty {
                            HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10)
                        },
                        checkoutDate = checkoutDate.trim().ifEmpty {
                            HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10)
                        },
                        totalAmount = t,
                        paidAmount = p,
                        debtReason = debtReason.trim(),
                        pledge = pledge.trim().ifEmpty { null },
                        pledgeType = pledgeType.trim().ifEmpty { null },
                        note = note.trim().ifEmpty { null }
                    )
                )
            }) { Text(if (existing == null) "إضافة الدين" else "تحديث الدين") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}
