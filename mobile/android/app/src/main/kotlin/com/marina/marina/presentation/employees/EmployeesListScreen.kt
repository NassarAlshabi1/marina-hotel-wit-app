package com.marina.marina.presentation.employees

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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun EmployeesListScreen(
    viewModel: EmployeesViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var editingEmployee by remember { mutableStateOf<Employee?>(null) }
    var withdrawingEmployee by remember { mutableStateOf<Employee?>(null) }
    var terminateEmployee by remember { mutableStateOf<Employee?>(null) }

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
                    title = { Text("الموظفون (${state.activeCount})", style = AppTypography.titleLarge) },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            floatingActionButton = {
                FloatingActionButton(
                    onClick = { showAddDialog = true },
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
                    placeholder = { Text("بحث بالاسم أو المنصب...") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp)
                )

                Spacer(modifier = Modifier.height(10.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("active" to "النشطون", "terminated" to "منتهية خدمتهم", "all" to "الكل").forEach { (key, label) ->
                        FilterChip(
                            selected = state.statusFilter == key,
                            onClick = { viewModel.setStatusFilter(key) },
                            label = { Text(label, fontSize = 12.sp) }
                        )
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                Card(
                    colors = CardDefaults.cardColors(containerColor = AppColors.AccentSoft),
                    shape = RoundedCornerShape(10.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp).fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("إجمالي الرواتب الشهرية:", style = AppTypography.bodyMedium)
                        Text(
                            "${state.totalSalaries.toInt()} ريال",
                            style = AppTypography.titleSmall,
                            fontWeight = FontWeight.Bold,
                            color = AppColors.TextPrimary
                        )
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        "تعذر تحميل الموظفين: ${state.error}",
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor,
                        modifier = Modifier.padding(16.dp)
                    )
                    state.filtered.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        contentAlignment = Alignment.Center
                    ) { Text("لا يوجد موظفون", style = AppTypography.bodyLarge, color = AppColors.TextSecondary) }
                    else -> LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        contentPadding = PaddingValues(bottom = 88.dp)
                    ) {
                        items(state.filtered, key = { it.employee.id }) { item ->
                            EmployeeCard(
                                item = item,
                                onEdit = { editingEmployee = item.employee },
                                onWithdraw = { withdrawingEmployee = item.employee },
                                onTerminate = {
                                    if (StatusUtils.isEmployeeActive(item.employee.status)) {
                                        terminateEmployee = item.employee
                                    } else {
                                        viewModel.reactivateEmployee(item.employee)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showAddDialog) {
        EmployeeDialog(
            employee = null,
            onDismiss = { showAddDialog = false },
            onSave = { viewModel.saveEmployee(it); showAddDialog = false }
        )
    }

    editingEmployee?.let { employee ->
        EmployeeDialog(
            employee = employee,
            onDismiss = { editingEmployee = null },
            onSave = { viewModel.saveEmployee(it); editingEmployee = null }
        )
    }

    withdrawingEmployee?.let { employee ->
        WithdrawalDialog(
            employee = employee,
            onDismiss = { withdrawingEmployee = null },
            onConfirm = { amount, type, reason ->
                viewModel.addWithdrawal(employee, amount, type, reason)
                withdrawingEmployee = null
            }
        )
    }

    terminateEmployee?.let { employee ->
        var reason by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { terminateEmployee = null },
            title = { Text("إنهاء خدمة الموظف") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("سيتم إنهاء خدمة ${employee.name}. المتابعة؟")
                    OutlinedTextField(
                        value = reason,
                        onValueChange = { reason = it },
                        label = { Text("سبب الإنهاء (اختياري)") },
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.terminateEmployee(employee, reason)
                    terminateEmployee = null
                }) { Text("إنهاء الخدمة", color = AppColors.DangerColor) }
            },
            dismissButton = {
                TextButton(onClick = { terminateEmployee = null }) { Text("إلغاء") }
            }
        )
    }
}

@Composable
private fun EmployeeCard(
    item: EmployeeWithWithdrawals,
    onEdit: () -> Unit,
    onWithdraw: () -> Unit,
    onTerminate: () -> Unit
) {
    val employee = item.employee
    val isActive = StatusUtils.isEmployeeActive(employee.status)
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(employee.name, style = AppTypography.titleMedium, fontWeight = FontWeight.Bold)
                    Text(employee.position, style = AppTypography.bodySmall, color = AppColors.TextSecondary)
                }
                Box(
                    modifier = Modifier
                        .background(
                            if (isActive) AppColors.SuccessColor.copy(alpha = 0.15f) else AppColors.DangerColor.copy(alpha = 0.15f),
                            RoundedCornerShape(6.dp)
                        )
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        if (isActive) "نشط" else "منتهي",
                        fontSize = 11.sp,
                        color = if (isActive) AppColors.SuccessColor else AppColors.DangerColor,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                EmpCell("الراتب", "${employee.basicSalary.toInt()} ريال")
                EmpCell("إجمالي المسحوب", "${item.totalWithdrawn.toInt()}")
                EmpCell("عدد العمليات", "${item.withdrawals.size}")
                employee.hireDate.takeIf { it.isNotBlank() }?.let {
                    EmpCell("التعيين", it.take(10))
                }
            }

            if (employee.phone.isNotBlank()) {
                Text("📱 ${employee.phone}", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
            }

            HorizontalDivider(color = AppColors.DividerColor)

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedButton(onClick = onWithdraw, modifier = Modifier.weight(1f)) {
                    Text("سلفة / سحب", fontSize = 12.sp)
                }
                TextButton(onClick = onEdit) { Text("تعديل", fontSize = 12.sp, color = AppColors.InfoColor) }
                TextButton(onClick = onTerminate) {
                    Text(
                        if (isActive) "إنهاء" else "تنشيط",
                        fontSize = 12.sp,
                        color = if (isActive) AppColors.DangerColor else AppColors.SuccessColor
                    )
                }
            }
        }
    }
}

@Composable
private fun EmpCell(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = AppTypography.titleSmall, fontWeight = FontWeight.SemiBold, color = AppColors.TextPrimary)
        Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary)
    }
}

@Composable
private fun WithdrawalDialog(
    employee: Employee,
    onDismiss: () -> Unit,
    onConfirm: (Double, String, String?) -> Unit
) {
    var amount by remember { mutableStateOf("") }
    var type by remember { mutableStateOf("سلفة") }
    var reason by remember { mutableStateOf("") }
    val types = listOf("سلفة", "سحب راتب", "خصم")

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("عملية مالية — ${employee.name}") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    types.forEach { t ->
                        FilterChip(selected = type == t, onClick = { type = t }, label = { Text(t, fontSize = 12.sp) })
                    }
                }
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { ch -> ch.isDigit() } },
                    label = { Text("المبلغ (ريال)") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = reason,
                    onValueChange = { reason = it },
                    label = { Text("ملاحظات (اختياري)") },
                    singleLine = true
                )
                Text(
                    "تاريخ اليوم الفندقي: ${HotelTimeEngine.currentHotelDayKey()}",
                    style = AppTypography.labelSmall,
                    color = AppColors.TextSecondary
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val value = amount.toDoubleOrNull() ?: return@TextButton
                    onConfirm(value, type, reason.ifBlank { null })
                }
            ) { Text("تسجيل", color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

@Composable
private fun EmployeeDialog(
    employee: Employee?,
    onDismiss: () -> Unit,
    onSave: (Employee) -> Unit
) {
    var name by remember { mutableStateOf(employee?.name ?: "") }
    var position by remember { mutableStateOf(employee?.position?.takeIf { it.isNotBlank() && !it.contains("employed") } ?: "موظف") }
    var salary by remember { mutableStateOf(if ((employee?.basicSalary ?: 0.0) > 0) employee!!.basicSalary.toInt().toString() else "") }
    var phone by remember { mutableStateOf(employee?.phone ?: "") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (employee == null) "إضافة موظف" else "تعديل الموظف", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("الاسم") }, singleLine = true)
                OutlinedTextField(value = position, onValueChange = { position = it }, label = { Text("المنصب") }, singleLine = true)
                OutlinedTextField(
                    value = salary,
                    onValueChange = { salary = it.filter { ch -> ch.isDigit() } },
                    label = { Text("الراتب الأساسي (ريال)") },
                    singleLine = true
                )
                OutlinedTextField(value = phone, onValueChange = { phone = it }, label = { Text("الهاتف") }, singleLine = true)
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (name.isBlank()) return@TextButton
                    onSave(
                        (employee ?: Employee()).copy(
                            name = name.trim(),
                            position = position.trim(),
                            basicSalary = salary.toDoubleOrNull() ?: 0.0,
                            phone = phone.trim(),
                            status = employee?.status?.ifBlank { "نشط" } ?: "نشط"
                        )
                    )
                }
            ) { Text("حفظ", color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}
