package com.marina.marina.presentation.inventory

import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.outlined.BrokenImage
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FactCheck
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.components.SidebarMenuButton
import com.marina.marina.domain.model.InventoryItem
import com.marina.marina.presentation.common.AppSnackbar
import com.marina.marina.presentation.common.AppSnackbarHost
import com.marina.marina.presentation.common.AppBarSyncIconButton
import com.marina.marina.presentation.common.AppBarSyncViewModel
import com.marina.marina.presentation.common.DartPalette
import com.marina.marina.presentation.common.formatQuantity
import com.marina.marina.presentation.common.showAppSnackbar
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import kotlinx.coroutines.launch

/**
 * شاشة المخزون — نقل 1:1 لـ inventory_screen.dart (فرع
 * feat/cloudflare-sync-execution): بطاقة صنف بأفاتار ورصيد ملوّن حسب حد
 * التنبيه، أزرار وارد/صرف/جرد، حوارات الإضافة والحركة والجرد، حالة خطأ
 * وديّة تكتشف تلف قاعدة البيانات، وزر مزامنة في شريط العنوان.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryScreen(
    viewModel: InventoryViewModel = hiltViewModel(),
    syncViewModel: AppBarSyncViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showAddDialog by remember { mutableStateOf(false) }
    var movementItem by remember { mutableStateOf<InventoryItem?>(null) }
    var movementType by remember { mutableStateOf("in") }
    var stockItem by remember { mutableStateOf<InventoryItem?>(null) }
    val scope = rememberCoroutineScope()

    fun showMessage(message: String) {
        scope.launch { snackbarHostState.showAppSnackbar(AppSnackbar(message)) }
    }

    /** نظير _showAddItemDialog مع حاجز الصلاحية الداخلي. */
    fun openAddItemDialog() {
        if (!state.canCreate) {
            showMessage("ليست لديك صلاحية إضافة أصناف للمخزون")
            return
        }
        showAddDialog = true
    }

    fun openMovementDialog(item: InventoryItem, type: String) {
        if (!state.canCreate) {
            showMessage("ليست لديك صلاحية تسجيل حركات المخزون")
            return
        }
        movementItem = item
        movementType = type
    }

    fun openStockDialog(item: InventoryItem) {
        if (!state.canUpdate) {
            showMessage("ليست لديك صلاحية اعتماد جرد المخزون")
            return
        }
        stockItem = item
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { AppSnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("المخزون", style = AppTypography.titleLarge) },
                    navigationIcon = { SidebarMenuButton() },
                    actions = {
                        // نظير SyncActionButton في AppScaffold (Dart).
                        AppBarSyncIconButton(syncViewModel, snackbarHostState)
                        IconButton(
                            onClick = { openAddItemDialog() },
                            enabled = state.canCreate
                        ) {
                            Icon(
                                Icons.Filled.Add,
                                contentDescription = "إضافة صنف",
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            floatingActionButton = {
                ExtendedFloatingActionButton(
                    onClick = { openAddItemDialog() },
                    icon = { Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp)) },
                    text = { Text("إضافة صنف") }
                )
            }
        ) { padding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                when {
                    state.isLoading -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) { CircularProgressIndicator() }

                    state.loadError != null -> InventoryErrorWidget(
                        isCorruption = InventoryViewModel.isCorruptionError(state.loadError ?: ""),
                        onResync = {
                            scope.launch {
                                snackbarHostState.showAppSnackbar(
                                    AppSnackbar("جاري إعادة المزامنة... قد يستغرق هذا بضع دقائق.")
                                )
                            }
                            viewModel.retry()
                        },
                        onRetry = { viewModel.retry() }
                    )

                    state.items.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            "لا توجد أصناف. أضف أول صنف للمخزون.",
                            style = AppTypography.bodyLarge
                        )
                    }

                    else -> LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 88.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(state.items, key = { it.id }) { item ->
                            InventoryItemCard(
                                item = item,
                                canCreate = state.canCreate,
                                canUpdate = state.canUpdate,
                                onIn = { openMovementDialog(item, "in") },
                                onOut = { openMovementDialog(item, "out") },
                                onStock = { openStockDialog(item) }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showAddDialog) {
        AddItemDialog(
            onDismiss = { showAddDialog = false },
            onSave = { name, unit, category, initial, minimum ->
                showAddDialog = false
                viewModel.addItem(name, unit, category, initial, minimum)
            }
        )
    }

    movementItem?.let { item ->
        MovementDialog(
            item = item,
            movementType = movementType,
            onDismiss = { movementItem = null },
            onSave = { quantity, note ->
                movementItem = null
                viewModel.recordMovement(item, movementType, quantity, note)
            }
        )
    }

    stockItem?.let { item ->
        StockDialog(
            item = item,
            onDismiss = { stockItem = null },
            onSave = { quantity, note ->
                stockItem = null
                viewModel.setStock(item, quantity, note)
            }
        )
    }
}

/** نظير _InventoryItemCard (inventory_screen.dart l.290-418). */
@Composable
private fun InventoryItemCard(
    item: InventoryItem,
    canCreate: Boolean,
    canUpdate: Boolean,
    onIn: () -> Unit,
    onOut: () -> Unit,
    onStock: () -> Unit
) {
    val isLow = item.minimumQuantity > 0.0 && item.currentQuantity <= item.minimumQuantity
    val balanceColor = if (isLow) DartPalette.orange800 else DartPalette.green700

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                // CircleAvatar(radius: 20) — أفاتار 40dp بخلفية فاتحة.
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .background(
                            if (isLow) DartPalette.orange50 else DartPalette.blue50,
                            CircleShape
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = if (isLow) Icons.Outlined.WarningAmber else Icons.Outlined.Inventory2,
                        contentDescription = null,
                        tint = balanceColor,
                        modifier = Modifier.size(20.dp)
                    )
                }
                Spacer(modifier = Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        item.name,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        listOfNotNull(
                            item.category?.takeIf { it.isNotEmpty() },
                            "الوحدة: ${item.unit}"
                        ).joinToString(" • "),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        fontSize = 11.sp,
                        color = DartPalette.grey
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        formatQuantity(item.currentQuantity),
                        color = balanceColor,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(item.unit, fontSize = 10.sp)
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedButton(
                    onClick = onIn,
                    enabled = canCreate,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("وارد")
                }
                OutlinedButton(
                    onClick = onOut,
                    enabled = canCreate,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Icon(Icons.Filled.Remove, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("صرف")
                }
                OutlinedButton(
                    onClick = onStock,
                    enabled = canUpdate,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Icon(Icons.Outlined.FactCheck, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("جرد")
                }
            }
            if (isLow) {
                Box(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        "تنبيه: الرصيد وصل إلى الحد الأدنى (${formatQuantity(item.minimumQuantity)})",
                        fontSize = 10.sp,
                        color = DartPalette.orange800,
                        modifier = Modifier.align(Alignment.CenterStart)
                    )
                }
            }
        }
    }
}

/**
 * نظير _buildErrorWidget (inventory_screen.dart l.75-157): حالة خطأ وديّة
 * تكتشف تلف SQLite وتعرض زر «إعادة المزامنة» + «إعادة المحاولة».
 */
@Composable
private fun InventoryErrorWidget(
    isCorruption: Boolean,
    onResync: () -> Unit,
    onRetry: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = if (isCorruption) Icons.Outlined.BrokenImage else Icons.Outlined.ErrorOutline,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = if (isCorruption) DartPalette.red400 else DartPalette.orange400
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            if (isCorruption) "تعذّر تحميل المخزون" else "تعذر تحميل المخزون",
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            if (isCorruption) {
                "قاعدة البيانات بها مشكلة في البيانات. " +
                    "يمكنك محاولة إعادة المزامنة من السحاب لإصلاح المشكلة."
            } else {
                "حدث خطأ غير متوقع أثناء تحميل بيانات المخزون."
            },
            fontSize = 14.sp,
            color = DartPalette.grey600,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(24.dp))
        if (isCorruption) {
            Button(
                onClick = onResync,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = DartPalette.blue,
                    contentColor = Color.White
                ),
                contentPadding = PaddingValues(16.dp)
            ) {
                Icon(Icons.Filled.Sync, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("إعادة المزامنة")
            }
            Spacer(modifier = Modifier.height(12.dp))
        }
        OutlinedButton(
            onClick = onRetry,
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(16.dp)
        ) {
            Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text("إعادة المحاولة")
        }
    }
}

/** نظير _showAddItemDialog (inventory_screen.dart l.159-276). */
@Composable
private fun AddItemDialog(
    onDismiss: () -> Unit,
    onSave: (name: String, unit: String, category: String, initial: Int, minimum: Int) -> Unit
) {
    var name by remember { mutableStateOf("") }
    var unit by remember { mutableStateOf("قطعة") }
    var category by remember { mutableStateOf("") }
    var initial by remember { mutableStateOf("0") }
    var minimum by remember { mutableStateOf("0") }
    var showNameError by remember { mutableStateOf(false) }
    var showInitialError by remember { mutableStateOf(false) }
    var showMinimumError by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    fun validateNonNegativeInteger(text: String): Boolean {
        val parsed = text.trim().toIntOrNull()
        return parsed == null || parsed < 0
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("إضافة صنف للمخزون") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it; showNameError = false },
                    label = { Text("اسم الصنف") },
                    isError = showNameError && name.trim().isEmpty(),
                    supportingText = {
                        if (showNameError && name.trim().isEmpty()) Text("اسم الصنف مطلوب")
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().focusRequester(focusRequester)
                )
                OutlinedTextField(
                    value = unit,
                    onValueChange = { unit = it },
                    label = { Text("الوحدة") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = category,
                    onValueChange = { category = it },
                    label = { Text("التصنيف (اختياري)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = initial,
                    onValueChange = { initial = it; showInitialError = false },
                    label = { Text("الرصيد الافتتاحي") },
                    isError = showInitialError && validateNonNegativeInteger(initial),
                    supportingText = {
                        if (showInitialError && validateNonNegativeInteger(initial)) {
                            Text("أدخل رقماً صحيحاً غير سالب")
                        }
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = minimum,
                    onValueChange = { minimum = it; showMinimumError = false },
                    label = { Text("حد التنبيه الأدنى") },
                    isError = showMinimumError && validateNonNegativeInteger(minimum),
                    supportingText = {
                        if (showMinimumError && validateNonNegativeInteger(minimum)) {
                            Text("أدخل رقماً صحيحاً غير سالب")
                        }
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val initialParsed = initial.trim().toIntOrNull()
                    val minimumParsed = minimum.trim().toIntOrNull()
                    val nameValid = name.trim().isNotEmpty()
                    val initialValid = initialParsed != null && initialParsed >= 0
                    val minimumValid = minimumParsed != null && minimumParsed >= 0
                    showNameError = !nameValid
                    showInitialError = !initialValid
                    showMinimumError = !minimumValid
                    if (nameValid && initialValid && minimumValid) {
                        onSave(name, unit, category, initialParsed ?: 0, minimumParsed ?: 0)
                    }
                }
            ) {
                Text("حفظ")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

/** نظير _showMovementDialog (inventory_screen.dart l.420-514). */
@Composable
private fun MovementDialog(
    item: InventoryItem,
    movementType: String,
    onDismiss: () -> Unit,
    onSave: (quantity: Int, note: String?) -> Unit
) {
    var quantity by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var showQuantityError by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    fun quantityInvalid(): Boolean {
        val parsed = quantity.trim().toIntOrNull()
        return parsed == null || parsed <= 0
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (movementType == "in") "إضافة وارد" else "تسجيل صرف") },
        text = {
            Column {
                Text("الصنف: ${item.name} (${formatQuantity(item.currentQuantity)} ${item.unit})")
                OutlinedTextField(
                    value = quantity,
                    onValueChange = { quantity = it; showQuantityError = false },
                    label = { Text("الكمية (${item.unit})") },
                    isError = showQuantityError && quantityInvalid(),
                    supportingText = {
                        if (showQuantityError && quantityInvalid()) Text("أدخل كمية أكبر من صفر")
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().focusRequester(focusRequester)
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("ملاحظة (اختياري)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val parsed = quantity.trim().toIntOrNull()
                    if (parsed == null || parsed <= 0) {
                        showQuantityError = true
                        return@Button
                    }
                    onSave(parsed, note)
                }
            ) {
                Text("حفظ")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

/** نظير _showStockDialog (inventory_screen.dart l.516-602). */
@Composable
private fun StockDialog(
    item: InventoryItem,
    onDismiss: () -> Unit,
    onSave: (quantity: Int, note: String?) -> Unit
) {
    var quantity by remember { mutableStateOf(formatQuantity(item.currentQuantity)) }
    var note by remember { mutableStateOf("") }
    var showQuantityError by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    fun quantityInvalid(): Boolean {
        val parsed = quantity.trim().toIntOrNull()
        return parsed == null || parsed < 0
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("جرد المخزون") },
        text = {
            Column {
                Text("الرصيد الحالي: ${formatQuantity(item.currentQuantity)} ${item.unit}")
                OutlinedTextField(
                    value = quantity,
                    onValueChange = { quantity = it; showQuantityError = false },
                    label = { Text("الرصيد الفعلي (${item.unit})") },
                    isError = showQuantityError && quantityInvalid(),
                    supportingText = {
                        if (showQuantityError && quantityInvalid()) Text("أدخل رقماً صحيحاً غير سالب")
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().focusRequester(focusRequester)
                )
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it },
                    label = { Text("ملاحظة (اختياري)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val parsed = quantity.trim().toIntOrNull()
                    if (parsed == null || parsed < 0) {
                        showQuantityError = true
                        return@Button
                    }
                    onSave(parsed, note)
                }
            ) {
                Text("اعتماد الجرد")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}
