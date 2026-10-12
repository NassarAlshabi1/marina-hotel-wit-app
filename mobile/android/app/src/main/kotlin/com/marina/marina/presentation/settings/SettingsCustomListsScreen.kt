package com.marina.marina.presentation.settings

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ListAlt
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.marina.marina.components.MarinaBackButton
import com.marina.marina.components.MarinaTopAppBar
import com.marina.marina.ui.components.MarinaSnackbarHost as SnackbarHost
import com.marina.marina.ui.components.MarinaSnackbarType
import com.marina.marina.ui.components.MarinaSnackbarVisuals
import com.marina.marina.data.local.entity.CustomListItemEntity
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

/**
 * SettingsCustomListsScreen — نظير Flutter `SettingsCustomListsScreen` (settings_custom_lists.dart).
 * ثلاثة تبويبات: أنواع المصروفات، أنواع الهوية، طرق الدفع.
 * كل تبويب يعرض قائمة قابلة للإدارة (إضافة/تعديل/حذف/تفعيل/تعطيل).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsCustomListsScreen(
    onBack: () -> Unit = {},
    viewModel: CustomListsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var selectedTab by remember { mutableStateOf(0) }
    var showAddDialog by remember { mutableStateOf(false) }
    var editingItem by remember { mutableStateOf<CustomListItemEntity?>(null) }
    var deleteConfirmItem by remember { mutableStateOf<CustomListItemEntity?>(null) }
    val context = LocalContext.current

    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message
        if (msg != null) {
            snackbarHostState.showSnackbar(
                MarinaSnackbarVisuals(
                    message = msg,
                    type = if (state.error != null) MarinaSnackbarType.ERROR else MarinaSnackbarType.SUCCESS
                )
            )
            viewModel.consumeMessage()
        }
    }

    val tabs = listOf(
        TabConfig("expense_type", "أنواع المصروفات", state.expenseTypes),
        TabConfig("id_type", "أنواع الهوية", state.idTypes),
        TabConfig("payment_method", "طرق الدفع", state.paymentMethods)
    )

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                MarinaTopAppBar(
                    title = { Text("إدارة القوائم المنسدلة", style = AppTypography.titleLarge) },
                    navigationIcon = { MarinaBackButton(onClick = onBack) },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                // تبويبات
                Surface(
                    color = AppColors.SurfaceColor,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        tabs.forEachIndexed { index, tab ->
                            val isSelected = selectedTab == index
                            OutlinedButton(
                                onClick = { selectedTab = index },
                                modifier = Modifier.weight(1f).fillMaxWidth(),
                                colors = androidx.compose.material3.ButtonDefaults.outlinedButtonColors(
                                    containerColor = if (isSelected) AppColors.PrimaryColor.copy(alpha = 0.1f) else AppColors.SurfaceColor,
                                    contentColor = if (isSelected) AppColors.PrimaryColor else AppColors.TextPrimary
                                ),
                                border = androidx.compose.foundation.BorderStroke(
                                    if (isSelected) 2.dp else 1.dp,
                                    if (isSelected) AppColors.PrimaryColor else AppColors.DividerColor
                                )
                            ) {
                                Text(tab.label, fontSize = 13.sp, fontWeight = FontWeight.Bold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.padding(16.dp))

                // محتوى التبويب المحدد
                val currentTab = tabs[selectedTab]
                if (state.isLoading) {
                    androidx.compose.material3.CircularProgressIndicator(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(32.dp)
                            .wrapContentSize(Alignment.Center)
                    )
                } else if (state.error != null) {
                    Text(
                        "خطأ: ${state.error}",
                        color = AppColors.DangerColor,
                        style = AppTypography.bodyMedium,
                        modifier = Modifier.padding(16.dp)
                    )
                } else {
                    CustomListTabContent(
                        listKey = currentTab.listKey,
                        items = currentTab.items,
                        onAdd = { showAddDialog = true },
                        onEdit = { editingItem = it },
                        onDelete = { deleteConfirmItem = it },
                        onToggleActive = { viewModel.toggleActive(it) }
                    )
                }
            }
        }
    }

    // حوار الإضافة/التعديل
    (editingItem ?: (if (showAddDialog) CustomListItemEntity(
        listKey = tabs[selectedTab].listKey,
        name = "",
        sortOrder = 0,
        isActive = true,
        isSystem = false
    ) else null))?.let { entity ->
        CustomListItemDialog(
            entity = entity,
            isEditing = editingItem != null,
            onDismiss = { showAddDialog = false; editingItem = null },
            onSave = { name, sortOrder, isSystem ->
                if (editingItem != null) {
                    viewModel.updateItem(editingItem!!.copy(name = name, sortOrder = sortOrder, isSystem = isSystem))
                } else {
                    viewModel.addItem(tabs[selectedTab].listKey, name, sortOrder, isSystem)
                }
                showAddDialog = false
                editingItem = null
            }
        )
    }

    // حوار تأكيد الحذف
    deleteConfirmItem?.let { item ->
        AlertDialog(
            onDismissRequest = { deleteConfirmItem = null },
            title = { Text("تأكيد الحذف", style = AppTypography.titleLarge) },
            text = { Text("هل تريد حذف \"${item.name}\"؟", style = AppTypography.bodyMedium) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteItem(item.id)
                    deleteConfirmItem = null
                }) {
                    Text("حذف", color = AppColors.DangerColor, fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteConfirmItem = null }) { Text("إلغاء") }
            }
        )
    }
}

private data class TabConfig(
    val listKey: String,
    val label: String,
    val items: List<CustomListItemEntity>
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CustomListTabContent(
    listKey: String,
    items: List<CustomListItemEntity>,
    onAdd: () -> Unit,
    onEdit: (CustomListItemEntity) -> Unit,
    onDelete: (CustomListItemEntity) -> Unit,
    onToggleActive: (CustomListItemEntity) -> Unit
) {
    val sortedItems = items.sortedWith(compareBy({ it.sortOrder }, { it.name }))
    androidx.compose.foundation.lazy.LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        items(sortedItems) { item ->
            Card(
                modifier = Modifier.fillMaxWidth(),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (item.isActive) AppColors.SurfaceColor else AppColors.SurfaceColor.copy(alpha = 0.6f)
                )
            ) {
                androidx.compose.foundation.layout.Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    androidx.compose.foundation.layout.Column(
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(
                            item.name,
                            style = AppTypography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                        )
                        Text(
                            "الترتيب: ${item.sortOrder} • ${if (item.isSystem) "نظامي" else "مخصص"} • ${if (item.isActive) "نشط" else "معطل"}",
                            style = AppTypography.labelSmall,
                            color = AppColors.TextSecondary
                        )
                    }
                    androidx.compose.foundation.layout.Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        IconButton(onClick = { onToggleActive(item) }) {
                            Icon(
                                Icons.Default.PowerSettingsNew,
                                contentDescription = if (item.isActive) "تعطيل" else "تفعيل",
                                tint = if (item.isActive) AppColors.SuccessColor else AppColors.TextSecondary
                            )
                        }
                        IconButton(onClick = { onEdit(item) }) {
                            Icon(
                                Icons.Default.Edit,
                                contentDescription = "تعديل",
                                tint = AppColors.InfoColor
                            )
                        }
                        IconButton(onClick = { onDelete(item) }) {
                            Icon(
                                Icons.Default.Delete,
                                contentDescription = "حذف",
                                tint = AppColors.DangerColor
                            )
                        }
                    }
                }
            }
        }
        if (sortedItems.isEmpty()) {
            item {
            androidx.compose.foundation.layout.Box(
                modifier = Modifier.fillMaxSize().padding(32.dp),
                contentAlignment = Alignment.Center
            ) {
                androidx.compose.foundation.layout.Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Default.ListAlt, contentDescription = null, tint = AppColors.TextSecondary, modifier = Modifier.size(48.dp))
                    Text("لا توجد عناصر", style = AppTypography.bodyLarge, color = AppColors.TextSecondary)
                    Text("اضغط + لإضافة أول عنصر", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
                }
            }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CustomListItemDialog(
    entity: CustomListItemEntity,
    isEditing: Boolean,
    onDismiss: () -> Unit,
    onSave: (name: String, sortOrder: Int, isSystem: Boolean) -> Unit
) {
    var name by remember { mutableStateOf(entity.name) }
    var sortOrder by remember { mutableStateOf(entity.sortOrder) }
    var isSystem by remember { mutableStateOf(entity.isSystem) }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (isEditing) "تعديل عنصر" else "إضافة عنصر", style = AppTypography.titleLarge) },
        text = {
            androidx.compose.foundation.layout.Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("الاسم *") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = sortOrder.toString(),
                    onValueChange = { sortOrder = it.toIntOrNull() ?: 0 },
                    label = { Text("الترتيب") },
                    singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth()
                )
                if (!isEditing) {
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        androidx.compose.material3.Switch(
                            checked = isSystem,
                            onCheckedChange = { isSystem = it },
                            modifier = Modifier.weight(1f)
                        )
                        Text("عنصر نظامي (لا يُحذف)", style = AppTypography.bodyMedium)
                    }
                }
                error?.let {
                    Text(it, color = AppColors.DangerColor, style = AppTypography.bodySmall)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                if (name.trim().isEmpty()) {
                    error = "الاسم مطلوب"
                    return@TextButton
                }
                error = null
                onSave(name.trim(), sortOrder, isSystem)
            }) {
                Text(if (isEditing) "حفظ" else "إضافة", color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}