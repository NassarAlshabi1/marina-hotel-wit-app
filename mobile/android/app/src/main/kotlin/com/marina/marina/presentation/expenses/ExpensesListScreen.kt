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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Expense
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun ExpensesListScreen(
    viewModel: ExpensesViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var editingExpense by remember { mutableStateOf<Expense?>(null) }
    var deleteConfirmExpense by remember { mutableStateOf<Expense?>(null) }

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
                    title = { Text("المصروفات", style = AppTypography.titleLarge) },
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
                    placeholder = { Text("بحث بالنوع أو الوصف...") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp)
                )

                Spacer(modifier = Modifier.height(10.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(
                        "today" to "اليوم",
                        "week" to "الأسبوع",
                        "month" to "الشهر",
                        "all" to "الكل"
                    ).forEach { (key, label) ->
                        FilterChip(
                            selected = state.typeFilter == key,
                            onClick = { viewModel.setTypeFilter(key) },
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
                        Text("إجمالي المصروفات المعروضة:", style = AppTypography.bodyMedium)
                        Text(
                            "${state.filteredTotal.toInt()} ريال (${state.filtered.size})",
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
                        "تعذر تحميل المصروفات: ${state.error}",
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor,
                        modifier = Modifier.padding(16.dp)
                    )
                    state.filtered.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        contentAlignment = Alignment.Center
                    ) { Text("لا توجد مصروفات", style = AppTypography.bodyLarge, color = AppColors.TextSecondary) }
                    else -> LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(bottom = 88.dp)
                    ) {
                        items(state.filtered, key = { it.id }) { expense ->
                            ExpenseCard(
                                expense = expense,
                                employeeName = state.employeeNames[expense.relatedId ?: -1],
                                onClick = { editingExpense = expense },
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
            onDismiss = { showAddDialog = false },
            onSave = { viewModel.saveExpense(it); showAddDialog = false }
        )
    }

    editingExpense?.let { expense ->
        ExpenseDialog(
            expense = expense,
            onDismiss = { editingExpense = null },
            onSave = { viewModel.saveExpense(it); editingExpense = null }
        )
    }

    deleteConfirmExpense?.let { expense ->
        AlertDialog(
            onDismissRequest = { deleteConfirmExpense = null },
            title = { Text("حذف المصروف") },
            text = { Text("سيتم حذف مصروف \"${expense.expenseType}\" بمبلغ ${expense.amount.toInt()} ريال. المتابعة؟") },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteExpense(expense); deleteConfirmExpense = null }) {
                    Text("حذف", color = AppColors.DangerColor)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteConfirmExpense = null }) { Text("إلغاء") }
            }
        )
    }
}

@Composable
private fun ExpenseCard(
    expense: Expense,
    employeeName: String?,
    onClick: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(12.dp).fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .background(AppColors.DangerColor.copy(alpha = 0.12f), RoundedCornerShape(6.dp))
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    ) {
                        Text(expense.expenseType, fontSize = 11.sp, color = AppColors.DangerColor, fontWeight = FontWeight.SemiBold)
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(expense.description, style = AppTypography.bodyMedium, maxLines = 1)
                }
                Spacer(modifier = Modifier.height(4.dp))
                Row {
                    Text(
                        "اليوم الفندقي: ${expense.hotelDayKey ?: "—"}",
                        style = AppTypography.labelSmall,
                        color = AppColors.TextSecondary
                    )
                    employeeName?.let {
                        Spacer(modifier = Modifier.width(12.dp))
                        Text("👤 $it", style = AppTypography.labelSmall, color = AppColors.TextSecondary)
                    }
                }
            }
            Text(
                "${expense.amount.toInt()} ريال",
                style = AppTypography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = AppColors.DangerColor
            )
            TextButton(onClick = onDelete) {
                Text("حذف", fontSize = 11.sp, color = AppColors.DangerColor)
            }
        }
    }
}

@Composable
private fun ExpenseDialog(
    expense: Expense?,
    onDismiss: () -> Unit,
    onSave: (Expense) -> Unit
) {
    var type by remember { mutableStateOf(expense?.expenseType ?: "تشغيلية") }
    var description by remember { mutableStateOf(expense?.description ?: "") }
    var amount by remember { mutableStateOf(if ((expense?.amount ?: 0.0) > 0) expense!!.amount.toInt().toString() else "") }
    var newType by remember { mutableStateOf("") }
    var showNewTypeField by remember { mutableStateOf(false) }

    val commonTypes = listOf("تشغيلية", "رواتب", "صيانة", "نظافة", "كهرباء", "ماء", "أخرى")

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (expense == null) "إضافة مصروف" else "تعديل المصروف", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("النوع", style = AppTypography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    commonTypes.take(3).forEach { t ->
                        FilterChip(selected = type == t, onClick = { type = t }, label = { Text(t, fontSize = 11.sp) })
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    commonTypes.drop(3).forEach { t ->
                        FilterChip(selected = type == t, onClick = { type = t }, label = { Text(t, fontSize = 11.sp) })
                    }
                }
                if (showNewTypeField) {
                    OutlinedTextField(
                        value = newType,
                        onValueChange = { newType = it },
                        label = { Text("نوع مخصص") },
                        singleLine = true
                    )
                    TextButton(onClick = { if (newType.isNotBlank()) { type = newType.trim(); showNewTypeField = false } }) {
                        Text("اعتماد النوع")
                    }
                } else {
                    TextButton(onClick = { showNewTypeField = true }) {
                        Text("+ نوع مخصص", fontSize = 12.sp, color = AppColors.PrimaryColor)
                    }
                }
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { ch -> ch.isDigit() } },
                    label = { Text("المبلغ (ريال)") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text("الوصف") },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val value = amount.toDoubleOrNull() ?: return@TextButton
                    onSave(
                        (expense ?: Expense()).copy(
                            expenseType = type,
                            description = description.trim(),
                            amount = value
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
