package com.marina.marina.presentation.expenses

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.presentation.reports.ReportDateRange
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.components.MarinaTopAppBar
import com.marina.marina.components.SidebarMenuButton
import java.util.Calendar

/**
 * Expenses list — Kotlin port of `expenses_list.dart`
 * (feat/cloudflare-sync-execution) built on the same screen skeleton as
 * [com.marina.marina.presentation.employees.EmployeesListScreen].
 *
 * Contract carried over from Dart:
 *  - hotel-day range query (14:01 → 14:00) through the repository
 *  - type dropdown minus سلفة with custom-type display protection
 *  - رواتب branch: employee dropdown (dedup + مؤرشف marker) + action
 *    dropdown (سلفة / سحب من الراتب / خصم من الراتب)
 *  - in-dialog validation before closing (employee required, amount > 0)
 *  - delete = mirror first, then the expense (repository transaction)
 *  - permission gates expenses.create/update/delete
 */
@Composable
fun ExpensesListScreen(
    viewModel: ExpensesViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showAddDialog by remember { mutableStateOf(false) }
    var editingExpense by remember { mutableStateOf<Expense?>(null) }
    var deleteConfirmExpense by remember { mutableStateOf<Expense?>(null) }
    // Dart l.970-983: a linked archived (soft-deleted) employee is resolved
    // through the raw lookup and shown with a (مؤرشف) marker.
    var archivedEmployee by remember { mutableStateOf<Employee?>(null) }

    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.consumeMessage()
        }
    }

    LaunchedEffect(editingExpense?.id, state.employees.size) {
        val linkedId = editingExpense?.relatedId
        archivedEmployee = if (linkedId != null && state.employees.none { it.id == linkedId }) {
            viewModel.getArchivedEmployee(linkedId)
        } else {
            null
        }
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                MarinaTopAppBar(
                    title = { Text("المصروفات", style = AppTypography.titleLarge) },
                    navigationIcon = { SidebarMenuButton() },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            floatingActionButton = {
                // Dart l.121-126: the add action is permission-gated.
                FloatingActionButton(
                    onClick = { if (state.canCreate) showAddDialog = true },
                    containerColor = if (state.canCreate) AppColors.PrimaryActionColor else AppColors.TextSecondary,
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
                // Dart _buildSearchBar (l.381-447) — debounce lives in the ViewModel.
                OutlinedTextField(
                    value = state.searchQuery,
                    onValueChange = viewModel::setSearchQuery,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("ابحث بالوصف أو النوع...") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp)
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Dart _buildTypeFilterRow (l.449-537) — dropdown + clear.
                ExpenseTypeFilterRow(
                    options = state.typeOptions,
                    selected = state.selectedType,
                    onSelect = viewModel::selectType
                )

                Spacer(modifier = Modifier.height(6.dp))

                // Dart _buildCompactFiltersCard (l.539-611) — from/to hotel-day chips.
                DateRangeFilterRow(
                    range = state.range,
                    filterActive = state.filterActive,
                    onPick = viewModel::setRange,
                    onClear = viewModel::clearDateFilter
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Dart _buildCompactSummaryCard (l.613-683).
                OutlinedCard(
                    colors = CardDefaults.cardColors(containerColor = AppColors.AccentSoft),
                    shape = RoundedCornerShape(10.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp).fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("${state.filteredCount} عملية", style = AppTypography.bodyMedium)
                        Text(
                            "${CurrencyFormatter.formatAmount(state.filteredTotal)} ريال",
                            style = AppTypography.titleSmall,
                            fontWeight = FontWeight.Bold,
                            color = AppColors.DangerColor
                        )
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        state.error!!,
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor,
                        modifier = Modifier.padding(16.dp)
                    )
                    state.expenses.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        // Dart l.188-190.
                        Text("لا توجد مصروفات ضمن الفترة", style = AppTypography.bodyLarge, color = AppColors.TextSecondary)
                    }
                    else -> LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(bottom = 88.dp)
                    ) {
                        items(state.expenses, key = { it.id }) { expense ->
                            ExpenseCard(
                                expense = expense,
                                employeeName = state.employees.find { it.id == expense.relatedId }?.name,
                                canUpdate = state.canUpdate,
                                canDelete = state.canDelete,
                                onEdit = { editingExpense = expense },
                                onDelete = { deleteConfirmExpense = expense }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showAddDialog) {
        ExpenseDialog(
            expense = null,
            typeOptions = state.typeOptions,
            availableEmployees = state.availableEmployees,
            archivedEmployee = null,
            onDismiss = { showAddDialog = false },
            onSave = { type, action, employee, amount, description, dateKey ->
                viewModel.saveExpense(null, type, action, employee, amount, description, dateKey)
                showAddDialog = false
            }
        )
    }

    editingExpense?.let { expense ->
        ExpenseDialog(
            expense = expense,
            typeOptions = state.typeOptions,
            availableEmployees = state.availableEmployees,
            archivedEmployee = archivedEmployee,
            onDismiss = { editingExpense = null },
            onSave = { type, action, employee, amount, description, dateKey ->
                viewModel.saveExpense(expense, type, action, employee, amount, description, dateKey)
                editingExpense = null
            }
        )
    }

    // Dart _deleteExpense confirm (l.827-848).
    deleteConfirmExpense?.let { expense ->
        AlertDialog(
            onDismissRequest = { deleteConfirmExpense = null },
            title = { Text("تأكيد الحذف") },
            text = {
                Text(
                    "هل تريد حذف المصروف \"${expense.description.ifBlank { "مصروف بدون وصف" }}\" " +
                        "بمبلغ ${CurrencyFormatter.formatAmount(expense.amount)}؟"
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteExpense(expense)
                    deleteConfirmExpense = null
                }) { Text("حذف", color = AppColors.DangerColor, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { deleteConfirmExpense = null }) { Text("إلغاء") }
            }
        )
    }
}

/** Dart _buildTypeFilterRow — dropdown of dynamic types + a clear affordance. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExpenseTypeFilterRow(
    options: List<String>,
    selected: String?,
    onSelect: (String?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = AppColors.SurfaceColor,
        border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.DividerColor),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 10.dp)) {
            Text("النوع:", fontSize = 12.sp, color = AppColors.TextSecondary)
            ExposedDropdownMenuBox(
                expanded = expanded,
                onExpandedChange = { expanded = it },
                modifier = Modifier.weight(1f).padding(start = 8.dp)
            ) {
                Text(
                    text = selected ?: "كل الأنواع",
                    style = AppTypography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (selected == null) AppColors.TextSecondary else AppColors.TextPrimary,
                    modifier = Modifier
                        .menuAnchor()
                        .fillMaxWidth()
                        .padding(vertical = 10.dp)
                )
                ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    DropdownMenuItem(
                        text = { Text("كل الأنواع", fontSize = 12.sp, color = AppColors.TextSecondary) },
                        onClick = {
                            onSelect(null)
                            expanded = false
                        }
                    )
                    options.forEach { type ->
                        DropdownMenuItem(
                            text = { Text(type, fontSize = 12.sp) },
                            onClick = {
                                onSelect(type)
                                expanded = false
                            }
                        )
                    }
                }
            }
            if (selected != null) {
                TextButton(onClick = { onSelect(null) }) {
                    Text("✕", fontSize = 12.sp, color = AppColors.DangerColor)
                }
            }
        }
    }
}

/**
 * Dart _buildCompactFiltersCard + _pickDate (l.302-378, 539-611): from snaps
 * to 14:01, to snaps to 14:00:59, and the two auto-correct each other —
 * the same rules ReportDateFilter applies for report screens.
 */
@Composable
private fun DateRangeFilterRow(
    range: ReportDateRange,
    filterActive: Boolean,
    onPick: (ReportDateRange) -> Unit,
    onClear: () -> Unit
) {
    val context = LocalContext.current
    val todayKey = HotelTimeEngine.currentHotelDayKey()
    val fromDisplay = if (filterActive) range.fromHotelDayKey else todayKey
    val toDisplay = if (filterActive) range.toHotelDayKey else todayKey

    fun pick(isFrom: Boolean) {
        val initialCal = Calendar.getInstance().apply {
            timeInMillis = if (isFrom) range.from else range.to
        }
        android.app.DatePickerDialog(
            context,
            { _, y, m, d ->
                val picked = Calendar.getInstance().apply {
                    set(y, m, d, HotelTimeEngine.BOUNDARY_HOUR, HotelTimeEngine.BOUNDARY_MINUTE, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                if (isFrom) {
                    // "من" = بداية اليوم الفندقي (14:01) — Dart l.319-346.
                    val newFrom = picked.timeInMillis
                    val newTo = if (newFrom > range.to) {
                        picked.add(Calendar.DAY_OF_YEAR, 1)
                        picked.set(Calendar.HOUR_OF_DAY, HotelTimeEngine.BOUNDARY_HOUR)
                        picked.set(Calendar.MINUTE, HotelTimeEngine.BOUNDARY_MINUTE - 1)
                        picked.set(Calendar.SECOND, 59)
                        picked.timeInMillis
                    } else {
                        range.to
                    }
                    onPick(ReportDateRange(newFrom, newTo))
                } else {
                    // "إلى" = نهاية اليوم الفندقي (14:00:59) — Dart l.347-374.
                    picked.set(Calendar.MINUTE, HotelTimeEngine.BOUNDARY_MINUTE - 1)
                    picked.set(Calendar.SECOND, 59)
                    picked.set(Calendar.MILLISECOND, 999)
                    val newTo = picked.timeInMillis
                    val newFrom = if (newTo < range.from) {
                        picked.add(Calendar.DAY_OF_YEAR, -1)
                        picked.set(Calendar.HOUR_OF_DAY, HotelTimeEngine.BOUNDARY_HOUR)
                        picked.set(Calendar.MINUTE, HotelTimeEngine.BOUNDARY_MINUTE)
                        picked.set(Calendar.SECOND, 0)
                        picked.set(Calendar.MILLISECOND, 0)
                        picked.timeInMillis
                    } else {
                        range.from
                    }
                    onPick(ReportDateRange(newFrom, newTo))
                }
            },
            initialCal.get(Calendar.YEAR),
            initialCal.get(Calendar.MONTH),
            initialCal.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    Surface(
        shape = RoundedCornerShape(10.dp),
        color = AppColors.SurfaceColor,
        border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.DividerColor),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            Text("📅", fontSize = 12.sp)
            AssistChip(
                onClick = { pick(isFrom = true) },
                label = { Text("من $fromDisplay", fontSize = 11.sp, color = AppColors.InfoColor) }
            )
            AssistChip(
                onClick = { pick(isFrom = false) },
                label = { Text("إلى $toDisplay", fontSize = 11.sp, color = AppColors.InfoColor) }
            )
            Spacer(modifier = Modifier.weight(1f))
            if (filterActive) {
                TextButton(onClick = onClear) {
                    Text("✕", fontSize = 12.sp, color = AppColors.DangerColor)
                }
            }
        }
    }
}

@Composable
private fun ExpenseCard(
    expense: Expense,
    employeeName: String?,
    canUpdate: Boolean,
    canDelete: Boolean,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    // Dart _buildExpenseCard (l.685-793): description (or fallback), amount,
    // type chip, date, employee; edit/delete gated by permissions.
    OutlinedCard(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.5.dp),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    expense.description.ifBlank { "مصروف بدون وصف" },
                    style = AppTypography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    "${CurrencyFormatter.formatAmount(expense.amount)} ريال",
                    style = AppTypography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.DangerColor
                )
                if (canUpdate) {
                    TextButton(onClick = onEdit) {
                        Text("تعديل", fontSize = 11.sp, color = AppColors.InfoColor)
                    }
                }
                if (canDelete) {
                    TextButton(onClick = onDelete) {
                        Text("حذف", fontSize = 11.sp, color = AppColors.DangerColor)
                    }
                }
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(
                    modifier = Modifier
                        .background(AppColors.DangerColor.copy(alpha = 0.12f), RoundedCornerShape(6.dp))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        expense.expenseType,
                        fontSize = 11.sp,
                        color = AppColors.DangerColor,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Text(
                    expense.date.take(10).replace("-", "/"),
                    style = AppTypography.labelSmall,
                    color = AppColors.TextSecondary
                )
                employeeName?.let {
                    Text(
                        "👤 $it",
                        style = AppTypography.labelSmall,
                        color = AppColors.TextSecondary,
                        maxLines = 1
                    )
                }
            }
            Text(
                "اليوم الفندقي: ${expense.hotelDayKey ?: "—"}",
                style = AppTypography.labelSmall,
                color = AppColors.TextSecondary
            )
        }
    }
}

/**
 * Dart _edit dialog (l.887-1199): type dropdown with the salary branch
 * (employee + transaction type), amount/description/date fields, and the
 * in-dialog validation (employee required for رواتب, amount > 0).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExpenseDialog(
    expense: Expense?,
    typeOptions: List<String>,
    availableEmployees: List<Employee>,
    archivedEmployee: Employee?,
    onDismiss: () -> Unit,
    onSave: (selectedType: String, salaryAction: String?, employee: Employee?, amount: Double, description: String, pickedDateKey: String) -> Unit
) {
    // Dart l.928-937: a salary-typed expense opens as نوع=رواتب + mapped action.
    val initialIsSalary = isSalaryAction(expense?.expenseType)
    var selectedType by remember {
        mutableStateOf(if (initialIsSalary) SALARY_TYPE else expense?.expenseType ?: "اخرى")
    }
    var salaryAction by remember {
        mutableStateOf(
            if (initialIsSalary) mapExpenseTypeToSalaryAction(expense!!.expenseType) else SALARY_WITHDRAW_ACTION
        )
    }
    var selectedEmployeeId by remember { mutableStateOf(expense?.relatedId) }
    var amount by remember {
        mutableStateOf(if ((expense?.amount ?: 0.0) > 0) CurrencyFormatter.formatAmount(expense!!.amount) else "")
    }
    var description by remember { mutableStateOf(expense?.description ?: "") }
    // Dart l.913-926: new expenses default to the current HOTEL day.
    var pickedDateKey by remember {
        mutableStateOf(expense?.date?.take(10) ?: HotelTimeEngine.currentHotelDayKey())
    }
    var error by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current

    // Dart l.1009-1018 — the legacy/custom type is appended dynamically so
    // the dropdown never shows a blank value for an existing expense.
    val dialogTypeOptions = remember(typeOptions, selectedType) {
        if (selectedType != SALARY_TYPE && !isSalaryAction(selectedType) &&
            typeOptions.none { it.trim() == selectedType.trim() }
        ) {
            typeOptions + selectedType
        } else {
            typeOptions
        }
    }

    fun resolveEmployee(): Employee? =
        selectedEmployeeId?.let { id ->
            availableEmployees.find { it.id == id }
                ?: archivedEmployee?.takeIf { it.id == id }
        }

    fun pickDate() {
        val initial = HotelTimeEngine.parseDate("$pickedDateKey 14:01:00") ?: System.currentTimeMillis()
        val cal = Calendar.getInstance().apply { timeInMillis = initial }
        android.app.DatePickerDialog(
            context,
            { _, y, m, d ->
                pickedDateKey = "%04d-%02d-%02d".format(y, m + 1, d)
            },
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH),
            cal.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (expense == null) "إضافة مصروف" else "تعديل مصروف", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                TypeDropdown(
                    label = "نوع المصروف",
                    options = dialogTypeOptions,
                    selected = selectedType,
                    onSelect = { value ->
                        selectedType = value
                        if (value == SALARY_TYPE) {
                            // Dart l.1032-1036: preselect the first employee.
                            if (selectedEmployeeId == null) {
                                selectedEmployeeId = availableEmployees.firstOrNull()?.id
                            }
                        } else {
                            // Dart l.1037-1039.
                            selectedEmployeeId = null
                            salaryAction = SALARY_WITHDRAW_ACTION
                        }
                    }
                )

                if (selectedType == SALARY_TYPE) {
                    // Dart l.1044-1102 — the salary branch.
                    if (availableEmployees.isEmpty() && archivedEmployee == null) {
                        Text("لا يوجد موظفين مسجلين حالياً.", style = AppTypography.bodyMedium)
                    } else {
                        EmployeeDropdown(
                            label = "اسم الموظف",
                            employees = availableEmployees,
                            archived = archivedEmployee,
                            selectedId = selectedEmployeeId,
                            onSelect = { selectedEmployeeId = it }
                        )
                        TypeDropdown(
                            label = "نوع المعاملة",
                            options = SALARY_ACTIONS,
                            selected = salaryAction,
                            onSelect = { salaryAction = it }
                        )
                    }
                }

                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { ch -> ch.isDigit() || ch == '.' } },
                    label = { Text("المبلغ") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text("الوصف") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedCard(onClick = { pickDate() }, modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier.padding(12.dp).fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("التاريخ", style = AppTypography.bodyMedium)
                        Text(pickedDateKey, style = AppTypography.bodyMedium, fontWeight = FontWeight.Bold)
                    }
                }

                error?.let {
                    Text(it, color = AppColors.DangerColor, style = AppTypography.bodySmall)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                // Dart l.1152-1180 — validation happens INSIDE the dialog so
                // it never closes silently on invalid input.
                val parsedAmount = CurrencyFormatter.parseAmount(amount) ?: 0.0
                if (selectedType == SALARY_TYPE && resolveEmployee() == null) {
                    error = "يجب اختيار موظف عند اختيار نوع المصروف \"رواتب\""
                    return@TextButton
                }
                if (parsedAmount <= 0.0) {
                    error = "يجب إدخال مبلغ أكبر من صفر"
                    return@TextButton
                }
                error = null
                onSave(
                    selectedType,
                    if (selectedType == SALARY_TYPE) salaryAction else null,
                    resolveEmployee(),
                    parsedAmount,
                    description.trim(),
                    pickedDateKey
                )
            }) { Text("حفظ", color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

/** النمط الموحد للقوائم — نظير DropdownButtonFormField في Dart. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TypeDropdown(
    label: String,
    options: List<String>,
    selected: String,
    onSelect: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .menuAnchor()
                .fillMaxWidth()
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option) },
                    onClick = {
                        onSelect(option)
                        expanded = false
                    }
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EmployeeDropdown(
    label: String,
    employees: List<Employee>,
    archived: Employee?,
    selectedId: Long?,
    onSelect: (Long?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedLabel = employees.find { it.id == selectedId }?.name
        ?: archived?.takeIf { it.id == selectedId }?.let { "${it.name} (مؤرشف)" }
        ?: ""
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = selectedLabel,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .menuAnchor()
                .fillMaxWidth()
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            archived?.let { emp ->
                DropdownMenuItem(
                    text = { Text("${emp.name} (مؤرشف)") },
                    onClick = {
                        onSelect(emp.id)
                        expanded = false
                    }
                )
            }
            employees.forEach { emp ->
                DropdownMenuItem(
                    text = { Text(emp.name) },
                    onClick = {
                        onSelect(emp.id)
                        expanded = false
                    }
                )
            }
        }
    }
}
