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
import com.marina.marina.components.SidebarMenuButton
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import java.util.concurrent.TimeUnit

@Composable
fun DebtsListScreen(
    onCreateFromBooking: () -> Unit = {},
    viewModel: DebtsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var showQuickAddMenu by remember { mutableStateOf(false) }
    var editingDebt by remember { mutableStateOf<Debt?>(null) }
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
                    title = { Text("إدارة الديون", style = AppTypography.titleLarge) },
                    navigationIcon = { SidebarMenuButton() },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            floatingActionButton = {
                // Dart debts_list l.78-84, 736-778 — the add button opens a
                // TWO-option menu: debt from an existing booking / manual debt.
                FloatingActionButton(
                    onClick = { showQuickAddMenu = true },
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
                    DebtStat("إجمالي الديون", "${state.totalCount}", Modifier.weight(1f))
                    DebtStat("معلقة", "${state.pendingCount}", Modifier.weight(1f))
                    DebtStat("القيمة الإجمالية", CurrencyFormatter.formatAmount(state.totalRemaining), Modifier.weight(1f))
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
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("لا توجد ديون", style = AppTypography.bodyLarge, color = AppColors.TextSecondary)
                            Text(
                                if (state.statusFilter == "all") "ابدأ بتسجيل دين جديد من زر الإضافة"
                                else "لا توجد ديون تطابق هذا الفلتر",
                                style = AppTypography.bodySmall, color = AppColors.TextSecondary
                            )
                        }
                    }
                    else -> LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        contentPadding = PaddingValues(bottom = 88.dp)
                    ) {
                        items(state.filtered, key = { it.id }) { debt ->
                            DebtCard(
                                debt = debt,
                                viewModel = viewModel,
                                onSettle = { settleConfirmDebt = debt },
                                onPartial = { partialPaymentDebt = debt },
                                onEdit = { editingDebt = debt },
                                onDelete = { deleteConfirmDebt = debt }
                            )
                        }
                    }
                }
            }
        }
    }

    // Dart quick-add menu (l.736-778): from-booking vs manual.
    if (showQuickAddMenu) {
        AlertDialog(
            onDismissRequest = { showQuickAddMenu = false },
            title = { Text("تسجيل دين جديد") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("اختر طريقة تسجيل الدين:", style = AppTypography.bodyMedium)
                    OutlinedButton(onClick = {
                        showQuickAddMenu = false
                        onCreateFromBooking()
                    }, modifier = Modifier.fillMaxWidth()) {
                        Text("دين من حجز موجود", fontSize = 13.sp, color = AppColors.PrimaryColor)
                    }
                    OutlinedButton(onClick = {
                        showQuickAddMenu = false
                        showAddDialog = true
                    }, modifier = Modifier.fillMaxWidth()) {
                        Text("دين يدوي", fontSize = 13.sp, color = AppColors.InfoColor)
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showQuickAddMenu = false }) { Text("إلغاء") }
            }
        )
    }

    if (showAddDialog) {
        DebtDialog(
            debt = null,
            onDismiss = { showAddDialog = false },
            onSave = { viewModel.saveDebt(it); showAddDialog = false }
        )
    }

    editingDebt?.let { debt ->
        DebtDialog(
            debt = debt,
            onDismiss = { editingDebt = null },
            onSave = { viewModel.updateDebt(it); editingDebt = null }
        )
    }

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

    settleConfirmDebt?.let { debt ->
        AlertDialog(
            onDismissRequest = { settleConfirmDebt = null },
            title = { Text("تسديد الدين بالكامل") },
            text = { Text("سيتم تسوية دين ${debt.guestName} بمبلغ ${CurrencyFormatter.formatAmount(debt.remainingAmount)} ريال. المتابعة؟") },
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
            text = { Text("سيتم حذف دين ${debt.guestName} بمبلغ ${CurrencyFormatter.formatAmount(debt.remainingAmount)} ريال. لا يمكن التراجع عنه. المتابعة؟") },
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

/** Dart overdue rule (l.669-676): unsettled AND >30 days since dateRecorded. */
private fun overdueDays(debt: Debt): Int {
    if (debt.isSettled) return 0
    val recorded = HotelTimeEngine.parseDate(
        debt.dateRecorded.ifBlank { debt.checkoutDate }
    ) ?: return 0
    val days = TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis() - recorded).toInt()
    return if (days > 30) days else 0
}

@Composable
private fun DebtCard(
    debt: Debt,
    viewModel: DebtsViewModel,
    onSettle: () -> Unit,
    onPartial: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    val overdue = overdueDays(debt)
    val (stripeColor, statusLabel) = when {
        debt.isSettled -> AppColors.SuccessColor to "مسدد"
        overdue > 0 -> AppColors.DangerColor to "متأخر ($overdue يوم)"
        else -> AppColors.WarningColor to "معلق"
    }
    // Dart l.848-976 — the instalment log lives inside the note's JSON.
    val (originalNote, paymentLog) = viewModel.parsePaymentLog(debt.note)

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

                // Dart l.420-438 — stay period when known.
                if (debt.checkinDate.isNotBlank() || debt.checkoutDate.isNotBlank()) {
                    Text(
                        "الفترة: ${debt.checkinDate.take(10)} → ${debt.checkoutDate.take(10)}",
                        style = AppTypography.labelSmall, color = AppColors.TextSecondary
                    )
                }

                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    DebtAmountCell("الإجمالي", CurrencyFormatter.formatAmount(debt.totalAmount))
                    DebtAmountCell("المدفوع", CurrencyFormatter.formatAmount(debt.paidAmount))
                    DebtAmountCell(
                        "المتبقي",
                        CurrencyFormatter.formatAmount(debt.remainingAmount),
                        if (debt.remainingAmount > 0) AppColors.DangerColor else AppColors.SuccessColor
                    )
                }

                // Dart pledge box (l.522-549).
                if (!debt.pledge.isNullOrBlank()) {
                    Text(
                        "رهن: ${debt.pledge}" + (debt.pledgeType?.takeIf { it.isNotBlank() }?.let { " ($it)" } ?: ""),
                        style = AppTypography.bodySmall,
                        color = AppColors.InfoColor,
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(AppColors.InfoColor.copy(alpha = 0.1f), RoundedCornerShape(8.dp))
                            .padding(8.dp)
                    )
                }

                // Dart note box (l.551-570) — renders the ORIGINAL note only
                // (the JSON payload is rendered as the log below).
                if (originalNote.isNotBlank()) {
                    Text("📝 $originalNote", style = AppTypography.labelSmall, color = AppColors.TextSecondary, maxLines = 2)
                }

                // Dart instalment log (l.848-901).
                if (paymentLog.isNotEmpty()) {
                    Column(
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(AppColors.LightGray.copy(alpha = 0.4f), RoundedCornerShape(8.dp))
                            .padding(8.dp)
                    ) {
                        Text("سجل الدفعات (${paymentLog.size})", style = AppTypography.labelMedium, fontWeight = FontWeight.Bold)
                        paymentLog.forEach { (amount, date, note) ->
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(
                                    "$date${if (note.isNotBlank()) " — $note" else ""}",
                                    style = AppTypography.labelSmall, color = AppColors.TextSecondary
                                )
                                Text(CurrencyFormatter.formatAmount(amount), style = AppTypography.labelSmall, color = AppColors.SuccessColor)
                            }
                        }
                    }
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
                    TextButton(onClick = onEdit) {
                        Text("تعديل", fontSize = 12.sp, color = AppColors.InfoColor)
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

/**
 * Dart partial-payment dialog (l.983-1127): guest financial summary, amount,
 * a payment DATE (default today), and an optional note.
 */
@Composable
private fun PartialPaymentDialog(
    debt: Debt,
    onDismiss: () -> Unit,
    onConfirm: (Double, String, String) -> Unit
) {
    var amount by remember { mutableStateOf("") }
    var date by remember { mutableStateOf(HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10)) }
    var note by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("دفعة جزئية — ${debt.guestName}") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                // Dart guest summary lines.
                Text("الإجمالي: ${CurrencyFormatter.formatAmount(debt.totalAmount)} ريال", style = AppTypography.bodySmall)
                Text("المدفوع: ${CurrencyFormatter.formatAmount(debt.paidAmount)} ريال", style = AppTypography.bodySmall, color = AppColors.SuccessColor)
                Text("المتبقي: ${CurrencyFormatter.formatAmount(debt.remainingAmount)} ريال", style = AppTypography.bodySmall, color = AppColors.DangerColor)
                HorizontalDivider(color = AppColors.DividerColor)
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { ch -> ch.isDigit() } },
                    label = { Text("مبلغ الدفعة (ريال)") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = date,
                    onValueChange = { date = it },
                    label = { Text("تاريخ الدفعة (yyyy-MM-dd)") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("ملاحظة (اختياري)") },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val value = amount.toDoubleOrNull() ?: return@TextButton
                    if (value <= 0 || value > debt.remainingAmount) return@TextButton
                    onConfirm(value, date, note)
                }
            ) { Text("تسجيل", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

/**
 * Dart manual debt form (l.1206-1586) — full field set: guest, stay dates,
 * reason (default عدم سداد قيمة أيام إضافية), total, paid (auto-remaining),
 * pledge + pledge type, note. Doubles as the EDIT dialog (prefilled).
 */
@Composable
private fun DebtDialog(
    debt: Debt?,
    onDismiss: () -> Unit,
    onSave: (Debt) -> Unit
) {
    var guestName by remember { mutableStateOf(debt?.guestName ?: "") }
    var checkin by remember { mutableStateOf(debt?.checkinDate?.take(10) ?: "") }
    var checkout by remember { mutableStateOf(debt?.checkoutDate?.take(10) ?: "") }
    var reason by remember { mutableStateOf(debt?.debtReason ?: "عدم سداد قيمة أيام إضافية") }
    var total by remember { mutableStateOf(if ((debt?.totalAmount ?: 0.0) > 0) debt!!.totalAmount.toInt().toString() else "") }
    var paid by remember { mutableStateOf(if ((debt?.paidAmount ?: 0.0) > 0) debt!!.paidAmount.toInt().toString() else "0") }
    var pledge by remember { mutableStateOf(debt?.pledge ?: "") }
    var pledgeType by remember { mutableStateOf(debt?.pledgeType ?: "") }
    var note by remember { mutableStateOf(debt?.note ?: "") }
    var validationError by remember { mutableStateOf<String?>(null) }

    val totalValue = total.toDoubleOrNull() ?: 0.0
    val paidValue = paid.toDoubleOrNull() ?: 0.0
    val remaining = (totalValue - paidValue).coerceAtLeast(0.0)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (debt == null) "دين يدوي جديد" else "تعديل الدين", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = guestName,
                    onValueChange = { guestName = it },
                    label = { Text("اسم الضيف *") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = checkin,
                    onValueChange = { checkin = it },
                    label = { Text("تاريخ الوصول (yyyy-MM-dd)") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = checkout,
                    onValueChange = { checkout = it },
                    label = { Text("تاريخ المغادرة (yyyy-MM-dd)") },
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
                    label = { Text("المبلغ الإجمالي (ريال) *") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = paid,
                    onValueChange = { paid = it.filter { ch -> ch.isDigit() } },
                    label = { Text("المدفوع (ريال)") },
                    singleLine = true
                )
                // Dart l.1259-1268 — live auto-computed remaining.
                Text(
                    "المتبقي: ${CurrencyFormatter.formatAmount(remaining)} ريال",
                    style = AppTypography.bodySmall,
                    color = if (remaining > 0) AppColors.DangerColor else AppColors.SuccessColor
                )
                OutlinedTextField(
                    value = pledge,
                    onValueChange = { pledge = it },
                    label = { Text("الرهن (اختياري)") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = pledgeType,
                    onValueChange = { pledgeType = it },
                    label = { Text("نوع الرهن (اختياري)") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("ملاحظات (اختياري)") },
                    minLines = 2
                )
                if (validationError != null) {
                    Text(validationError!!, color = AppColors.DangerColor, style = AppTypography.bodySmall)
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    // Dart l.1458-1492 — validation with visible messages.
                    if (guestName.isBlank()) {
                        validationError = "يرجى إدخال اسم الضيف"
                        return@TextButton
                    }
                    if (totalValue <= 0) {
                        validationError = "يرجى إدخال مبلغ إجمالي صحيح"
                        return@TextButton
                    }
                    if (paidValue > totalValue) {
                        validationError = "المدفوع لا يمكن أن يتجاوز الإجمالي"
                        return@TextButton
                    }
                    val today = HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10)
                    onSave(
                        (debt ?: Debt()).copy(
                            guestName = guestName.trim(),
                            checkinDate = checkin.trim(),
                            checkoutDate = checkout.trim(),
                            debtReason = reason.trim(),
                            totalAmount = totalValue,
                            paidAmount = paidValue,
                            remainingAmount = remaining,
                            isSettled = remaining <= 0,
                            pledge = pledge.trim().ifBlank { null },
                            pledgeType = pledgeType.trim().ifBlank { null },
                            note = note.trim().ifBlank { null },
                            dateRecorded = debt?.dateRecorded?.ifBlank { null } ?: today,
                            paymentDate = debt?.paymentDate?.ifBlank { null } ?: today
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
