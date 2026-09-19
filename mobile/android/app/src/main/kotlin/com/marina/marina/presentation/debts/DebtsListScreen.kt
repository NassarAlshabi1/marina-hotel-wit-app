package com.marina.marina.presentation.debts

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
import com.marina.marina.domain.model.Debt
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun DebtsListScreen(
    viewModel: DebtsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var partialPaymentDebt by remember { mutableStateOf<Debt?>(null) }
    var settleConfirmDebt by remember { mutableStateOf<Debt?>(null) }
    var deleteConfirmDebt by remember { mutableStateOf<Debt?>(null) }

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
                    title = { Text("الديون", style = AppTypography.titleLarge) },
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
                    placeholder = { Text("بحث باسم الضيف...") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp)
                )

                Spacer(modifier = Modifier.height(10.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(
                        "all" to "الكل",
                        "pending" to "معلقة",
                        "settled" to "مسددة",
                        "overdue" to "متأخرة"
                    ).forEach { (key, label) ->
                        FilterChip(
                            selected = state.statusFilter == key,
                            onClick = { viewModel.setStatusFilter(key) },
                            label = { Text(label, fontSize = 12.sp) }
                        )
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    DebtStat("العدد", "${state.totalCount}", Modifier.weight(1f))
                    DebtStat("معلقة", "${state.pendingCount}", Modifier.weight(1f))
                    DebtStat("إجمالي المتبقي", "${state.totalRemaining.toInt()}", Modifier.weight(1f))
                }

                Spacer(modifier = Modifier.height(10.dp))

                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        "تعذر تحميل الديون: ${state.error}",
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor,
                        modifier = Modifier.padding(16.dp)
                    )
                    state.filtered.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        contentAlignment = Alignment.Center
                    ) { Text("لا توجد ديون", style = AppTypography.bodyLarge, color = AppColors.TextSecondary) }
                    else -> LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        contentPadding = PaddingValues(bottom = 88.dp)
                    ) {
                        items(state.filtered, key = { it.id }) { debt ->
                            DebtCard(
                                debt = debt,
                                onSettle = { settleConfirmDebt = debt },
                                onPartial = { partialPaymentDebt = debt },
                                onDelete = { deleteConfirmDebt = debt }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showAddDialog) {
        DebtDialog(
            onDismiss = { showAddDialog = false },
            onSave = { viewModel.saveDebt(it); showAddDialog = false }
        )
    }

    partialPaymentDebt?.let { debt ->
        PartialPaymentDialog(
            debt = debt,
            onDismiss = { partialPaymentDebt = null },
            onConfirm = { amount ->
                viewModel.addPartialPayment(debt, amount)
                partialPaymentDebt = null
            }
        )
    }

    settleConfirmDebt?.let { debt ->
        AlertDialog(
            onDismissRequest = { settleConfirmDebt = null },
            title = { Text("تسديد الدين بالكامل") },
            text = { Text("سيتم تسوية دين ${debt.guestName} بمبلغ ${debt.remainingAmount.toInt()} ريال. المتابعة؟") },
            confirmButton = {
                TextButton(onClick = { viewModel.settleDebt(debt); settleConfirmDebt = null }) {
                    Text("تسديد", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { settleConfirmDebt = null }) { Text("إلغاء") }
            }
        )
    }

    deleteConfirmDebt?.let { debt ->
        AlertDialog(
            onDismissRequest = { deleteConfirmDebt = null },
            title = { Text("حذف الدين") },
            text = { Text("سيتم حذف دين ${debt.guestName} نهائياً. المتابعة؟") },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteDebt(debt); deleteConfirmDebt = null }) {
                    Text("حذف", color = AppColors.DangerColor)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteConfirmDebt = null }) { Text("إلغاء") }
            }
        )
    }
}

@Composable
private fun DebtCard(
    debt: Debt,
    onSettle: () -> Unit,
    onPartial: () -> Unit,
    onDelete: () -> Unit
) {
    val (stripeColor, statusLabel) = when {
        debt.isSettled -> AppColors.SuccessColor to "مسدد"
        else -> AppColors.WarningColor to "معلق"
    }
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(modifier = Modifier.height(intrinsicSize = IntrinsicSize.Min)) {
            Box(
                modifier = Modifier
                    .width(6.dp)
                    .fillMaxHeight()
                    .background(stripeColor)
            )
            Column(modifier = Modifier.padding(14.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(debt.guestName.ifBlank { "ضيف" }, style = AppTypography.titleMedium, fontWeight = FontWeight.Bold)
                    DebtStatusBadge(statusLabel, stripeColor)
                }

                if (debt.debtReason.isNotBlank()) {
                    Text("السبب: ${debt.debtReason}", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
                }

                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    DebtAmountCell("الإجمالي", "${debt.totalAmount.toInt()}")
                    DebtAmountCell("المدفوع", "${debt.paidAmount.toInt()}")
                    DebtAmountCell(
                        "المتبقي",
                        "${debt.remainingAmount.toInt()}",
                        if (debt.remainingAmount > 0) AppColors.DangerColor else AppColors.SuccessColor
                    )
                }

                if (debt.note?.isNotBlank() == true) {
                    Text("📝 ${debt.note}", style = AppTypography.labelSmall, color = AppColors.TextSecondary, maxLines = 2)
                }

                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (!debt.isSettled) {
                        OutlinedButton(onClick = onPartial, modifier = Modifier.weight(1f)) {
                            Text("دفعة جزئية", fontSize = 12.sp)
                        }
                        OutlinedButton(onClick = onSettle, modifier = Modifier.weight(1f)) {
                            Text("تسديد كامل", fontSize = 12.sp, color = AppColors.SuccessColor)
                        }
                    }
                    TextButton(onClick = onDelete) {
                        Text("حذف", fontSize = 12.sp, color = AppColors.DangerColor)
                    }
                }
            }
        }
    }
}

@Composable
private fun DebtStatusBadge(label: String, color: Color) {
    Box(
        modifier = Modifier
            .background(color.copy(alpha = 0.15f), RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 3.dp)
    ) {
        Text(label, fontSize = 11.sp, color = color, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun DebtAmountCell(label: String, value: String, valueColor: Color = AppColors.TextPrimary) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = AppTypography.titleSmall, fontWeight = FontWeight.Bold, color = valueColor)
        Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary)
    }
}

@Composable
private fun DebtStat(label: String, value: String, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(10.dp)
    ) {
        Column(
            modifier = Modifier.padding(vertical = 10.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value, style = AppTypography.titleMedium, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
            Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary)
        }
    }
}

@Composable
private fun PartialPaymentDialog(
    debt: Debt,
    onDismiss: () -> Unit,
    onConfirm: (Double) -> Unit
) {
    var amount by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("دفعة جزئية — ${debt.guestName}") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("المتبقي: ${debt.remainingAmount.toInt()} ريال", style = AppTypography.bodyMedium, color = AppColors.TextSecondary)
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { ch -> ch.isDigit() } },
                    label = { Text("مبلغ الدفعة (ريال)") },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val value = amount.toDoubleOrNull() ?: return@TextButton
                    onConfirm(value)
                }
            ) { Text("تسجيل", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

@Composable
private fun DebtDialog(
    onDismiss: () -> Unit,
    onSave: (Debt) -> Unit
) {
    var guestName by remember { mutableStateOf("") }
    var reason by remember { mutableStateOf("") }
    var total by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("تسجيل دين جديد", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = guestName,
                    onValueChange = { guestName = it },
                    label = { Text("اسم الضيف") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = reason,
                    onValueChange = { reason = it },
                    label = { Text("سبب الدين") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = total,
                    onValueChange = { total = it.filter { ch -> ch.isDigit() } },
                    label = { Text("المبلغ الإجمالي (ريال)") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("ملاحظات (اختياري)") },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val totalValue = total.toDoubleOrNull() ?: return@TextButton
                    if (guestName.isBlank() || totalValue <= 0) return@TextButton
                    onSave(
                        Debt(
                            guestName = guestName.trim(),
                            debtReason = reason.trim(),
                            totalAmount = totalValue,
                            paidAmount = 0.0,
                            remainingAmount = totalValue,
                            isSettled = false,
                            note = note.ifBlank { null }
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
