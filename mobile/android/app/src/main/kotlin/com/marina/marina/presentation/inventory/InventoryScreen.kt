package com.marina.marina.presentation.inventory

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
import com.marina.marina.domain.model.InventoryItem
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun InventoryScreen(
    viewModel: InventoryViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var movementItem by remember { mutableStateOf<InventoryItem?>(null) }
    var movementType by remember { mutableStateOf("in") }
    var deleteConfirmItem by remember { mutableStateOf<InventoryItem?>(null) }

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
                    title = { Text("المخزون", style = AppTypography.titleLarge) },
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
                    placeholder = { Text("بحث بالاسم أو التصنيف...") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp)
                )

                Spacer(modifier = Modifier.height(10.dp))

                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    InvStat("العناصر", "${state.itemCount}", Modifier.weight(1f))
                    InvStat("تحت الحد الأدنى", "${state.lowStockCount}", Modifier.weight(1f), warning = state.lowStockCount > 0)
                }

                Spacer(modifier = Modifier.height(10.dp))

                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        "تعذر تحميل المخزون: ${state.error}",
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor,
                        modifier = Modifier.padding(16.dp)
                    )
                    state.filtered.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        contentAlignment = Alignment.Center
                    ) { Text("لا توجد عناصر", style = AppTypography.bodyLarge, color = AppColors.TextSecondary) }
                    else -> LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(bottom = 88.dp)
                    ) {
                        items(state.filtered, key = { it.id }) { item ->
                            InventoryItemCard(
                                item = item,
                                onIn = { movementItem = item; movementType = "in" },
                                onOut = { movementItem = item; movementType = "out" },
                                onStocktaking = { movementItem = item; movementType = "adjustment" },
                                onDelete = { deleteConfirmItem = item }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showAddDialog) {
        ItemDialog(
            onDismiss = { showAddDialog = false },
            onSave = { viewModel.addItem(it); showAddDialog = false }
        )
    }

    movementItem?.let { item ->
        MovementDialog(
            item = item,
            type = movementType,
            onDismiss = { movementItem = null },
            onConfirm = { quantity, note ->
                viewModel.recordMovement(item, movementType, quantity, note)
                movementItem = null
            }
        )
    }

    deleteConfirmItem?.let { item ->
        AlertDialog(
            onDismissRequest = { deleteConfirmItem = null },
            title = { Text("حذف العنصر") },
            text = { Text("سيتم حذف \"${item.name}\" من المخزون. المتابعة؟") },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteItem(item); deleteConfirmItem = null }) {
                    Text("حذف", color = AppColors.DangerColor)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteConfirmItem = null }) { Text("إلغاء") }
            }
        )
    }
}

@Composable
private fun InventoryItemCard(
    item: InventoryItem,
    onIn: () -> Unit,
    onOut: () -> Unit,
    onStocktaking: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(item.name, style = AppTypography.titleSmall, fontWeight = FontWeight.Bold)
                        if (item.isLowStock) {
                            Spacer(modifier = Modifier.width(6.dp))
                            Box(
                                modifier = Modifier
                                    .background(AppColors.DangerColor.copy(alpha = 0.15f), RoundedCornerShape(6.dp))
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            ) {
                                Text("منخفض", fontSize = 10.sp, color = AppColors.DangerColor, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                    Text(
                        listOfNotNull(item.category, "الوحدة: ${item.unit}").joinToString(" • "),
                        style = AppTypography.labelSmall,
                        color = AppColors.TextSecondary
                    )
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        "${item.currentQuantity.toInt()}",
                        style = AppTypography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = if (item.isLowStock) AppColors.DangerColor else AppColors.SuccessColor
                    )
                    Text("الحد: ${item.minimumQuantity.toInt()}", style = AppTypography.labelSmall, color = AppColors.TextSecondary)
                }
            }

            HorizontalDivider(color = AppColors.DividerColor)

            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Button(
                    onClick = onIn,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.SuccessColor),
                    contentPadding = PaddingValues(vertical = 4.dp)
                ) { Text("وارد", fontSize = 12.sp, color = Color.White) }
                Button(
                    onClick = onOut,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.WarningColor),
                    contentPadding = PaddingValues(vertical = 4.dp)
                ) { Text("صرف", fontSize = 12.sp, color = Color.White) }
                OutlinedButton(
                    onClick = onStocktaking,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(vertical = 4.dp)
                ) { Text("جرد", fontSize = 12.sp) }
                TextButton(onClick = onDelete, contentPadding = PaddingValues(vertical = 4.dp)) {
                    Text("حذف", fontSize = 12.sp, color = AppColors.DangerColor)
                }
            }
        }
    }
}

@Composable
private fun InvStat(label: String, value: String, modifier: Modifier = Modifier, warning: Boolean = false) {
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
            Text(
                value,
                style = AppTypography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = if (warning) AppColors.DangerColor else AppColors.PrimaryColor
            )
            Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary)
        }
    }
}

@Composable
private fun ItemDialog(
    onDismiss: () -> Unit,
    onSave: (InventoryItem) -> Unit
) {
    var name by remember { mutableStateOf("") }
    var unit by remember { mutableStateOf("قطعة") }
    var category by remember { mutableStateOf("") }
    var opening by remember { mutableStateOf("") }
    var minimum by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("إضافة عنصر للمخزون", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("اسم العنصر") }, singleLine = true)
                OutlinedTextField(value = unit, onValueChange = { unit = it }, label = { Text("الوحدة") }, singleLine = true)
                OutlinedTextField(
                    value = category,
                    onValueChange = { category = it },
                    label = { Text("التصنيف (اختياري)") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = opening,
                    onValueChange = { opening = it.filter { ch -> ch.isDigit() } },
                    label = { Text("الرصيد الافتتاحي") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = minimum,
                    onValueChange = { minimum = it.filter { ch -> ch.isDigit() } },
                    label = { Text("حد التنبيه الأدنى") },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (name.isBlank()) return@TextButton
                    onSave(
                        InventoryItem(
                            name = name.trim(),
                            unit = unit.trim().ifBlank { "قطعة" },
                            category = category.trim().ifBlank { null },
                            currentQuantity = opening.toDoubleOrNull() ?: 0.0,
                            minimumQuantity = minimum.toDoubleOrNull() ?: 0.0
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

@Composable
private fun MovementDialog(
    item: InventoryItem,
    type: String,
    onDismiss: () -> Unit,
    onConfirm: (Double, String?) -> Unit
) {
    var quantity by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }

    val title = when (type) {
        "in" -> "وارد — ${item.name}"
        "out" -> "صرف — ${item.name}"
        else -> "جرد — ${item.name}"
    }
    val quantityLabel = when (type) {
        "adjustment" -> "الكمية الفعلية بعد الجرد"
        else -> "الكمية (${item.unit})"
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "الرصيد الحالي: ${item.currentQuantity.toInt()} ${item.unit}",
                    style = AppTypography.bodyMedium,
                    color = AppColors.TextSecondary
                )
                OutlinedTextField(
                    value = quantity,
                    onValueChange = { quantity = it.filter { ch -> ch.isDigit() || ch == '.' } },
                    label = { Text(quantityLabel) },
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
                    val value = quantity.toDoubleOrNull() ?: return@TextButton
                    onConfirm(value, note.ifBlank { null })
                }
            ) { Text("تأكيد", color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}
