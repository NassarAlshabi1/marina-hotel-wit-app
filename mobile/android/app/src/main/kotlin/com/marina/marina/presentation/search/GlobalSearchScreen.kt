package com.marina.marina.presentation.search

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.Assignment
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.ManageSearch
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PieChart
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DateRangePicker
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDateRangePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.data.local.entity.BookingEntity
import com.marina.marina.data.local.entity.DebtEntity
import com.marina.marina.data.local.entity.EmployeeEntity
import com.marina.marina.data.local.entity.ExpenseEntity
import com.marina.marina.data.local.entity.GuestInfoEntity
import com.marina.marina.data.local.entity.InventoryItemEntity
import com.marina.marina.data.local.entity.PaymentEntity
import com.marina.marina.data.local.entity.RoomEntity
import com.marina.marina.data.local.entity.SalaryWithdrawalEntity
import com.marina.marina.data.search.GlobalSearchHit
import com.marina.marina.data.search.SearchEntityKind
import com.marina.marina.presentation.common.formatQuantity
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import java.text.DecimalFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * شاشة البحث الشامل — port 1:1 من `mobile/lib/screens/search/global_search_screen.dart`
 * (فرع feat/cloudflare-sync-execution).
 *
 * العقد:
 * - debounce 300ms وحد أدنى حرفان — لا استعلام لكل ضغطة.
 * - النتائج مجمعة بالكيان مع الإجمالي الصادق (قد يتجاوز المعروض).
 * - رقائق تصفية بالكيان (تُبنى من صلاحيات المستخدم — النوع غير
 *   المسموح لا يظهر أصلاً) + نطاق زمني اختياري (الكل افتراضياً).
 * - لوحة تفصيل للسجل عند النقر — بحثٌ للقراءة والسياق، التعديل في
 *   شاشاته الأصلية.
 * - للمدير: مفتاحا إظهار المحذوف والملغاة/المعلقة (تدقيق).
 */

// ─────────────────────── خرائط عرض الكيانات ───────────────────────

fun kindLabel(kind: SearchEntityKind): String = when (kind) {
    SearchEntityKind.booking -> "الحجوزات"
    SearchEntityKind.guestInfo -> "بطاقات الضيوف"
    SearchEntityKind.payment -> "المدفوعات"
    SearchEntityKind.expense -> "المصروفات"
    SearchEntityKind.withdrawal -> "سحبيات الرواتب"
    SearchEntityKind.debt -> "الديون"
    SearchEntityKind.employee -> "الموظفون"
    SearchEntityKind.room -> "الغرف"
    SearchEntityKind.inventoryItem -> "المخزون"
    SearchEntityKind.blacklist -> "القائمة السوداء"
}

fun kindIcon(kind: SearchEntityKind): ImageVector = when (kind) {
    SearchEntityKind.booking -> Icons.Outlined.Assignment
    SearchEntityKind.guestInfo -> Icons.Outlined.Badge
    SearchEntityKind.payment -> Icons.Outlined.Payments
    SearchEntityKind.expense -> Icons.Outlined.AccountBalanceWallet
    SearchEntityKind.withdrawal -> Icons.Outlined.Payments
    SearchEntityKind.debt -> Icons.Outlined.PieChart
    SearchEntityKind.employee -> Icons.Outlined.Person
    SearchEntityKind.room -> Icons.Outlined.ManageSearch
    SearchEntityKind.inventoryItem -> Icons.Outlined.Inventory2
    SearchEntityKind.blacklist -> Icons.Outlined.Block
}

fun kindColor(kind: SearchEntityKind): Color = when (kind) {
    SearchEntityKind.booking -> Color(0xFF3F51B5)   // Colors.indigo
    SearchEntityKind.guestInfo -> Color(0xFF009688) // Colors.teal
    SearchEntityKind.payment -> Color(0xFF4CAF50)   // Colors.green
    SearchEntityKind.expense -> Color(0xFFFF9800)   // Colors.orange
    SearchEntityKind.withdrawal -> Color(0xFF2196F3) // Colors.blue
    SearchEntityKind.debt -> Color(0xFF9C27B0)      // Colors.purple
    SearchEntityKind.employee -> Color(0xFF795548)  // Colors.brown
    SearchEntityKind.room -> Color(0xFF0097A7)      // Colors.cyan.shade700
    SearchEntityKind.inventoryItem -> Color(0xFFFF5722) // Colors.deepOrange
    SearchEntityKind.blacklist -> Color(0xFFF44336) // Colors.red
}

private val currencyFmt = DecimalFormat("#,##0")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlobalSearchScreen(
    onBack: () -> Unit = {},
    viewModel: GlobalSearchViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showAdminMenu by remember { mutableStateOf(false) }
    var showDatePicker by remember { mutableStateOf(false) }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("البحث الشامل", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    actions = {
                        if (state.isAdmin) {
                            IconButton(onClick = { showAdminMenu = true }) {
                                Icon(Icons.Outlined.Tune, contentDescription = "خيارات المدير")
                            }
                            DropdownMenu(expanded = showAdminMenu, onDismissRequest = { showAdminMenu = false }) {
                                DropdownMenuItem(
                                    text = { Text("إظهار المحذوف") },
                                    leadingIcon = { Checkbox(checked = state.includeDeleted, onCheckedChange = null) },
                                    onClick = {
                                        showAdminMenu = false
                                        viewModel.toggleIncludeDeleted()
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("إظهار الملغاة والمعلقة") },
                                    leadingIcon = { Checkbox(checked = state.includeInactivePayments, onCheckedChange = null) },
                                    onClick = {
                                        showAdminMenu = false
                                        viewModel.toggleIncludeInactivePayments()
                                    }
                                )
                            }
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
                SearchField(state = state, onChanged = viewModel::onQueryChanged, onClear = viewModel::clearQuery, onSubmit = viewModel::submitSearch)
                DateChips(state = state, onSelect = viewModel::setDateMode, onPickCustom = { showDatePicker = true })
                KindChips(state = state, onSelectAll = viewModel::selectAllKinds, onToggle = viewModel::toggleKind)
                HorizontalDivider(thickness = 1.dp, color = AppColors.DividerColor)
                Box(modifier = Modifier.fillMaxSize()) {
                    when {
                        state.isBelowMinQuery -> EmptyStateView(
                            icon = Icons.Outlined.ManageSearch,
                            title = "ابدأ البحث",
                            message = "اكتب حرفين على الأقل للبحث في كل بيانات النظام."
                        )
                        state.searching && state.results == null -> Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center
                        ) { CircularProgressIndicator() }
                        state.results == null -> Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center
                        ) { CircularProgressIndicator() }
                        state.results!!.isEmpty -> EmptyStateView(
                            icon = Icons.Outlined.SearchOff,
                            title = "لا توجد نتائج",
                            message = "لم يُعثر على مطابقات لهذا البحث ضمن النطاق المحدد."
                        )
                        else -> ResultsList(state = state)
                    }
                }
            }
        }
    }

    if (showDatePicker) {
        val pickerState = rememberDateRangePickerState()
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        val start = pickerState.selectedStartDateMillis
                        val end = pickerState.selectedEndDateMillis
                        if (start != null && end != null) {
                            val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                            viewModel.setCustomRange(fmt.format(Date(start)), fmt.format(Date(end)))
                        }
                        showDatePicker = false
                    },
                    enabled = pickerState.selectedStartDateMillis != null && pickerState.selectedEndDateMillis != null
                ) { Text("تحديد") }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) { Text("إلغاء") }
            }
        ) {
            DateRangePicker(state = pickerState, title = {
                Text(
                    "نطاق البحث",
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    style = AppTypography.titleMedium
                )
            })
        }
    }
}

@Composable
private fun SearchField(
    state: GlobalSearchUiState,
    onChanged: (String) -> Unit,
    onClear: () -> Unit,
    onSubmit: () -> Unit
) {
    OutlinedTextField(
        value = state.text,
        onValueChange = onChanged,
        modifier = Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 8.dp, bottom = 4.dp),
        placeholder = {
            Text("ابحث في كل البيانات: اسم، غرفة، رقم هوية، مبلغ…", fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        },
        leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
        trailingIcon = {
            when {
                state.searching -> CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                state.text.isNotEmpty() -> IconButton(onClick = onClear) {
                    Icon(Icons.Filled.Clear, contentDescription = "مسح")
                }
            }
        },
        singleLine = true,
        shape = RoundedCornerShape(12.dp)
    )
}

@Composable
private fun DateChips(
    state: GlobalSearchUiState,
    onSelect: (SearchDateMode) -> Unit,
    onPickCustom: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(38.dp)
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        listOf(
            SearchDateMode.ALL,
            SearchDateMode.TODAY,
            SearchDateMode.WEEK,
            SearchDateMode.MONTH
        ).forEach { mode ->
            FilterChip(
                selected = state.dateMode == mode,
                onClick = { onSelect(mode) },
                label = { Text(mode.label) }
            )
        }
        if (state.dateMode == SearchDateMode.CUSTOM) {
            FilterChip(
                selected = true,
                onClick = {},
                label = { Text(state.dateModeLabel) }
            )
        }
        FilterChip(
            selected = false,
            onClick = onPickCustom,
            label = { Text("مخصص") }
        )
    }
}

@Composable
private fun KindChips(
    state: GlobalSearchUiState,
    onSelectAll: () -> Unit,
    onToggle: (SearchEntityKind) -> Unit
) {
    val results = state.results
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(40.dp)
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 10.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        FilterChip(
            selected = state.selectedKinds.isEmpty(),
            onClick = onSelectAll,
            label = { Text("الكل") }
        )
        SearchEntityKind.entries
            .filter { state.allowedKinds.contains(it) }
            .forEach { kind ->
                val total = results?.totals?.get(kind) ?: 0
                FilterChip(
                    selected = state.selectedKinds.contains(kind),
                    onClick = { onToggle(kind) },
                    label = {
                        Text(
                            if (results != null && total > 0) "${kindLabel(kind)} ($total)" else kindLabel(kind),
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                )
            }
    }
}

@Composable
private fun ResultsList(state: GlobalSearchUiState) {
    val results = state.results ?: return
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        results.hits.forEach { (kind, hits) ->
            val total = results.totals[kind] ?: hits.size
            item(key = "kind_${kind.name}") {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(24.dp)
                            .background(kindColor(kind).copy(alpha = 0.12f), CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(kindIcon(kind), contentDescription = null, modifier = Modifier.size(14.dp), tint = kindColor(kind))
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(kindLabel(kind), fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        if (hits.size < total) "${hits.size} من $total" else "$total",
                        fontSize = 10.sp,
                        color = Color(0xFF757575),
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
            items(count = hits.size, key = { i -> "${kind.name}_${hits[i].kind.name}_${hits[i].id}_$i" }) { i ->
                Box(modifier = Modifier.padding(horizontal = 10.dp, vertical = 2.dp)) {
                    HitCard(hit = hits[i])
                }
            }
        }
        item(key = "footer") {
            Text(
                "${results.totalHits} نتيجة معروضة" +
                    if (results.elapsedMs > 0) " في ${results.elapsedMs} م.ث" else "",
                fontSize = 10.sp,
                color = Color(0xFF9E9E9E),
                modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HitCard(hit: GlobalSearchHit) {
    val context = LocalContext.current
    val color = kindColor(hit.kind)
    var showDetails by remember { mutableStateOf(false) }

    Card(
        elevation = CardDefaults.cardElevation(defaultElevation = 0.5.dp),
        shape = RoundedCornerShape(10.dp),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        modifier = Modifier.fillMaxWidth().clickable { showDetails = true }
    ) {
        Column(modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(kindIcon(hit.kind), contentDescription = null, modifier = Modifier.size(15.dp), tint = color)
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    hit.title,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                hit.amount?.let { amount ->
                    Text(
                        currencyFmt.format(amount),
                        fontWeight = FontWeight.Bold,
                        fontSize = 12.sp,
                        color = if (amount < 0) Color(0xFFF44336) else Color(0xFF4CAF50)
                    )
                }
            }
            Spacer(modifier = Modifier.height(4.dp))
            Row {
                Text(
                    listOf(hit.subtitle, hit.dayKey ?: "")
                        .filter { it.isNotEmpty() }
                        .joinToString(" • "),
                    fontSize = 10.sp,
                    color = Color(0xFF757575),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (hit.matchedFields.isNotEmpty()) {
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    hit.matchedFields.forEach { field ->
                        Text(
                            field,
                            fontSize = 9.sp,
                            color = color,
                            modifier = Modifier
                                .background(color.copy(alpha = 0.08f), RoundedCornerShape(6.dp))
                                .padding(horizontal = 6.dp, vertical = 1.dp)
                        )
                    }
                }
            }
        }
    }

    if (showDetails) {
        val rows = detailRowsFor(hit)
        ModalBottomSheet(onDismissRequest = { showDetails = false }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 24.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(kindIcon(hit.kind), contentDescription = null, modifier = Modifier.size(20.dp), tint = kindColor(hit.kind))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        hit.title,
                        fontWeight = FontWeight.Bold,
                        fontSize = 15.sp,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        kindLabel(hit.kind),
                        fontSize = 10.sp,
                        color = kindColor(hit.kind),
                        fontWeight = FontWeight.Bold
                    )
                }
                HorizontalDivider(modifier = Modifier.padding(vertical = 10.dp), color = AppColors.DividerColor)
                rows.forEach { (label, value) ->
                    if (value.isNotEmpty() && value != "—") {
                        Row(modifier = Modifier.padding(bottom = 8.dp)) {
                            Text(
                                label,
                                fontSize = 11.sp,
                                color = Color(0xFF757575),
                                modifier = Modifier.width(110.dp)
                            )
                            Text(value, fontSize = 12.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyStateView(icon: ImageVector, title: String, message: String) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(42.dp), tint = Color(0xFFBDBDBD))
        Spacer(modifier = Modifier.height(10.dp))
        Text(title, fontWeight = FontWeight.Bold, fontSize = 14.sp, color = AppColors.TextPrimary)
        Spacer(modifier = Modifier.height(4.dp))
        Text(message, fontSize = 11.sp, color = AppColors.TextSecondary, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}

// ─────────────────────── لوحة التفصيل ───────────────────────

/** نظير `_detailRowsFor` — صفوف التفصيل لكل نوع سجل. */
private fun detailRowsFor(hit: GlobalSearchHit): List<Pair<String, String>> {
    fun fmt(value: Double): String = currencyFmt.format(value)
    val rows: List<Pair<String, String>> = when (val record = hit.record) {
        is BookingEntity -> listOf(
            "رقم الحجز" to "#${record.id.toString().padStart(6, '0')}",
            "النزيل" to record.guestName,
            "الهاتف" to record.guestPhone,
            "رقم الهوية" to record.guestIdNumber,
            "الجنسية" to record.guestNationality,
            "الغرفة" to record.roomNumber,
            "الدخول" to record.checkinDate,
            "الخروج" to (record.checkoutDate ?: record.actualCheckout ?: "—"),
            "الحالة" to record.status,
            "الإجمالي المستحق" to fmt(record.totalDueCached),
            "المدفوع" to fmt(record.totalPaidCached),
            "المتبقي" to fmt(record.remainingBalanceCached),
            "ملاحظات" to (record.notes ?: "")
        )
        is GuestInfoEntity -> listOf(
            "الضيف" to record.guestName,
            "رقم الهوية" to record.idNumber,
            "نوع الهوية" to record.idType,
            "الجنسية" to record.nationality,
            "الهاتف" to (record.guestPhone ?: ""),
            "الغرفة" to record.roomNumber,
            "المحافظة" to (record.governorate ?: ""),
            "جهة الإصدار" to (record.issuePlace ?: ""),
            "ملاحظات" to (record.notes ?: "")
        )
        is PaymentEntity -> buildList {
            add("المبلغ" to fmt(record.amount))
            add("التاريخ" to record.paymentDate)
            add("اليوم الفندقي" to (record.hotelDayKey ?: "—"))
            add("الغرفة" to (record.roomNumber ?: ""))
            add("طريقة الدفع" to record.paymentMethod)
            add("نوع الإيراد" to record.revenueType)
            add("المستلم" to (record.receivedByName ?: ""))
            add("رقم المرجع" to (record.referenceNumber ?: ""))
            if (record.isVoided) add("الحالة" to "ملغاة (${record.voidReason ?: ""})")
            if (record.isPendingBalance) add("الحالة" to "رصيد معلق")
            add("ملاحظات" to (record.notes ?: ""))
        }
        is ExpenseEntity -> buildList {
            add("الوصف" to record.description)
            add("النوع" to record.expenseType)
            add("المبلغ" to fmt(record.amount))
            add("التاريخ" to record.date)
            add("اليوم الفندقي" to (record.hotelDayKey ?: "—"))
            if (record.isAutoGenerated) add("مصدر السجل" to "مولّد تلقائياً")
        }
        is SalaryWithdrawalEntity -> listOf(
            "الموظف" to hit.title,
            "المبلغ" to fmt(record.amount),
            "التاريخ" to SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(record.withdrawDate)),
            "اليوم الفندقي" to (record.hotelDayKey ?: "—"),
            "السبب" to (record.reason ?: ""),
            "النوع" to record.withdrawalType,
            "الوصف" to (record.description ?: "")
        )
        is DebtEntity -> listOf(
            "المدين" to record.guestName,
            "الهاتف" to (record.guestPhone ?: ""),
            "السبب" to record.debtReason,
            "إجمالي الدين" to fmt(record.totalAmount),
            "المسدد" to fmt(record.paidAmount),
            "المتبقي" to fmt(record.remainingAmount),
            "تاريخ التسجيل" to record.paymentDate,
            "الحالة" to (if (record.isSettled == 1) "مسدد" else "قائم"),
            "الرهان" to (record.pledge ?: ""),
            "ملاحظات" to (record.note ?: "")
        )
        is EmployeeEntity -> listOf(
            "الاسم" to record.name,
            "الوظيفة" to record.position,
            "الحالة" to record.status,
            "الراتب الأساسي" to fmt(record.basicSalary),
            "الهاتف" to record.phone,
            "الرقم الوظيفي" to (record.employeeID ?: ""),
            "تاريخ التعيين" to record.hireDate
        )
        is RoomEntity -> listOf(
            "الغرفة" to record.roomNumber,
            "النوع" to record.type,
            "الحالة" to record.status,
            "السعر" to fmt(record.price),
            "الصيانة" to (if (record.requiresMaintenance) "تحتاج صيانة" else "لا")
        )
        is InventoryItemEntity -> listOf(
            "الصنف" to record.name,
            "التصنيف" to (record.category ?: ""),
            "الكمية" to "${formatQuantity(record.currentQuantity)} ${record.unit}",
            "الحد الأدنى" to "${formatQuantity(record.minimumQuantity)} ${record.unit}"
        )
        else -> listOf("المعرف" to "${hit.id}")
    }
    return rows.filter { it.second.isNotEmpty() && it.second != "—" }
}
