package com.marina.marina.presentation.information

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.PictureAsPdf
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.components.SidebarMenuButton
import com.marina.marina.domain.model.GuestInfo
import com.marina.marina.presentation.common.AppSnackbar
import com.marina.marina.presentation.common.AppSnackbarHost
import com.marina.marina.presentation.common.AppBarSyncIconButton
import com.marina.marina.presentation.common.AppBarSyncViewModel
import com.marina.marina.presentation.common.SnackColors
import com.marina.marina.presentation.common.showAppSnackbar
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.util.PdfExporter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * شاشة سجل المعلومية — نقل 1:1 لـ information_screen.dart (فرع
 * feat/cloudflare-sync-execution): جدول أفقي التمرير برأس ملوّن وترتيب
 * تصاعدي لأرقام الغرف (أرقام أولاً ثم أبجدي — information_screen_sort_test)،
 * محرر إضافة/تعديل بحوار كامل مع منتقي تاريخ، حذف بتأكيد، تصدير PDF،
 * مزامنة فورية بعد كل عملية، وحوار تجاهل التغييرات عند المغادرة.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InformationScreen(
    onBack: (() -> Unit)? = null,
    viewModel: InformationViewModel = hiltViewModel(),
    syncViewModel: AppBarSyncViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var showEditor by remember { mutableStateOf(false) }
    var editorEntry by remember { mutableStateOf<GuestInfo?>(null) }
    var deleteTarget by remember { mutableStateOf<GuestInfo?>(null) }
    var showDiscardDialog by remember { mutableStateOf(false) }
    var exportingPdf by remember { mutableStateOf(false) }

    LaunchedEffect(state.snackbar) {
        state.snackbar?.let {
            snackbarHostState.showAppSnackbar(it)
            viewModel.consumeSnackbar()
        }
    }

    // نظير PopScope(canPop: !hasUnsyncedChanges) + _showDiscardDialog —
    // يتطلب تمرير onBack من NavGraph ليعمل الإغلاق الفعلي.
    BackHandler(enabled = onBack != null && state.hasUnsyncedChanges) {
        showDiscardDialog = true
    }

    val sorted = InformationViewModel.sortedByRoomNumber(state.entries)

    fun openEditor(existing: GuestInfo?) {
        editorEntry = existing
        showEditor = true
    }

    fun showSnack(message: String) {
        scope.launch { snackbarHostState.showAppSnackbar(AppSnackbar(message)) }
    }

    /** نظير _handleExport (information_screen.dart l.576-787). */
    fun handleExport(entries: List<GuestInfo>) {
        if (entries.isEmpty()) {
            showSnack("لا توجد بيانات للتصدير")
            return
        }
        // ✅ Guard ضد double-press (نفس Dart l.584).
        if (exportingPdf) return
        exportingPdf = true
        scope.launch {
            try {
                val exportEntries = InformationViewModel.sortedByRoomNumber(entries)
                val stamp = SimpleDateFormat("yyyyMMdd_HHmm", Locale.US).format(Date())
                val file = withContext(Dispatchers.IO) {
                    PdfExporter.buildReport(
                        context = context,
                        reportTitle = "سجل المعلومية",
                        periodText = null,
                        infoRows = emptyList(),
                        stats = emptyList(),
                        tables = listOf(
                            PdfExporter.PdfTable(
                                title = "سجل المعلومية",
                                headers = listOf(
                                    "#",
                                    "رقم الغرفة",
                                    "اسم النزيل",
                                    "الجنسية",
                                    "نوع الهوية",
                                    "رقم الهوية",
                                    "تاريخ الإصدار",
                                    "مكان الإصدار",
                                    "المحافظة",
                                    "الملاحظات"
                                ),
                                rows = exportEntries.mapIndexed { index, info ->
                                    listOf(
                                        "${index + 1}",
                                        safe(info.roomNumber),
                                        safe(info.guestName),
                                        safe(info.nationality),
                                        safe(info.idType),
                                        safe(info.idNumber),
                                        safe(info.issueDate),
                                        safe(info.issuePlace),
                                        safe(info.governorate),
                                        safe(info.notes)
                                    )
                                },
                                columnWeights = listOf(0.5f, 0.8f, 1.5f, 1.0f, 1.2f, 1.3f, 1.1f, 1.2f, 1.0f, 1.8f)
                            )
                        ),
                        fileName = "guest-info-$stamp.pdf"
                    )
                }
                PdfExporter.sharePdf(context, file, "سجل المعلومية")
            } catch (e: Exception) {
                showSnack("فشل تصدير الملف: ${e.message}")
            } finally {
                exportingPdf = false
            }
        }
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { AppSnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("سجل المعلومية", style = AppTypography.titleLarge) },
                    navigationIcon = { SidebarMenuButton() },
                    actions = {
                        // نظير SyncActionButton في AppScaffold (Dart).
                        AppBarSyncIconButton(syncViewModel, snackbarHostState)
                        IconButton(
                            onClick = { handleExport(state.entries) },
                            enabled = !exportingPdf && state.entries.isNotEmpty()
                        ) {
                            if (exportingPdf) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(20.dp),
                                    strokeWidth = 2.dp
                                )
                            } else {
                                Icon(
                                    Icons.Outlined.PictureAsPdf,
                                    contentDescription = "تصدير إلى PDF"
                                )
                            }
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
                    onClick = { openEditor(null) },
                    icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                    text = { Text("إضافة سجل") }
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

                    state.loadError != null -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            "حدث خطأ أثناء تحميل البيانات: ${state.loadError}",
                            textAlign = TextAlign.Center,
                            modifier = Modifier.padding(16.dp)
                        )
                    }

                    state.entries.isEmpty() -> InformationEmptyState()

                    else -> Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(12.dp)
                            .verticalScroll(rememberScrollState())
                    ) {
                        // ترتيب حسب رقم الغرفة (أرقام أولاً، ثم أبجدي) — نفس
                        // دالة ترتيب الـ PDF (Dart l.163-164).
                        InformationTable(
                            entries = sorted,
                            onEdit = { openEditor(it) },
                            onDelete = { deleteTarget = it }
                        )
                    }
                }
            }
        }
    }

    if (showEditor) {
        InformationEditorDialog(
            existing = editorEntry,
            onDismiss = { showEditor = false; editorEntry = null },
            onSave = { idType, room, guestName, nationality, idNumber, issueDate, issuePlace, governorate, notes ->
                showEditor = false
                val existing = editorEntry
                editorEntry = null
                if (existing == null) {
                    viewModel.create(room, guestName, nationality, idNumber, idType, issueDate, issuePlace, governorate, notes)
                } else {
                    viewModel.update(existing, room, guestName, nationality, idNumber, idType, issueDate, issuePlace, governorate, notes)
                }
            }
        )
    }

    deleteTarget?.let { info ->
        // نظير _confirmDelete (information_screen.dart l.519-559).
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text("حذف السجل") },
            text = { Text("سيتم حذف سجل النزيل \"${info.guestName}\"، هل أنت متأكد؟") },
            confirmButton = {
                Button(
                    onClick = {
                        deleteTarget = null
                        viewModel.delete(info)
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFFF5252), // Colors.redAccent
                        contentColor = Color.White
                    )
                ) {
                    Text("حذف")
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) { Text("إلغاء") }
            }
        )
    }

    if (showDiscardDialog) {
        // نظير _showDiscardDialog (information_screen.dart l.125-148).
        AlertDialog(
            onDismissRequest = { showDiscardDialog = false },
            title = { Text("تغييرات غير محفوظة") },
            text = { Text("هل تريد المغادرة بدون حفظ التغييرات؟") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDiscardDialog = false
                        onBack?.invoke()
                    }
                ) { Text("مغادرة") }
            },
            dismissButton = {
                TextButton(onClick = { showDiscardDialog = false }) { Text("إلغاء") }
            }
        )
    }
}

/** نظير safe() (information_screen.dart l.611-615): NULL/فارغ يصبح '-'. */
private fun safe(v: String?): String {
    if (v == null) return "-"
    val s = v.trim()
    return if (s.isEmpty()) "-" else s
}

/** نظير EmptyState(badge_outlined, l.150-159). */
@Composable
private fun InformationEmptyState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                Icons.Outlined.Badge,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = AppColors.DividerColor
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text("لا توجد سجلات للمعلومية", style = AppTypography.titleMedium, textAlign = TextAlign.Center)
            Text(
                "استخدم زر إضافة سجل لإدخال أول بيان للنزيل.",
                style = AppTypography.bodyMedium,
                color = AppColors.DividerColor,
                textAlign = TextAlign.Center
            )
        }
    }
}

private data class InfoColumn(val title: String, val width: Dp)

/**
 * نظير _buildTable (information_screen.dart l.179-312): DataTable برأس
 * ملوّن بالـ primary ونص أبيض — الأعمدة بالترتيب نفسه من اليمين.
 */
@Composable
private fun InformationTable(
    entries: List<GuestInfo>,
    onEdit: (GuestInfo) -> Unit,
    onDelete: (GuestInfo) -> Unit
) {
    val columns = listOf(
        InfoColumn("#", 44.dp),
        InfoColumn("", 56.dp),
        InfoColumn("الغرفة", 76.dp),
        InfoColumn("اسم النزيل", 140.dp),
        InfoColumn("الجنسية", 100.dp),
        InfoColumn("رقم الهوية", 120.dp),
        InfoColumn("نوع الهوية", 120.dp),
        InfoColumn("تاريخ الإصدار", 110.dp),
        InfoColumn("مكان الإصدار", 120.dp),
        InfoColumn("المحافظة", 110.dp),
        InfoColumn("الملاحظات", 170.dp)
    )

    Card(modifier = Modifier.fillMaxWidth()) {
        Row(modifier = Modifier.horizontalScroll(rememberScrollState())) {
            Column {
                Row(
                    modifier = Modifier
                        .background(AppColors.PrimaryColor)
                        .padding(vertical = 14.dp)
                ) {
                    columns.forEach { column ->
                        Box(modifier = Modifier.width(column.width)) {
                            Text(
                                column.title,
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = 14.dp)
                            )
                        }
                    }
                }
                entries.forEachIndexed { index, info ->
                    HorizontalDivider(color = AppColors.DividerColor)
                    Row(modifier = Modifier.padding(vertical = 10.dp)) {
                        columns.forEachIndexed { columnIndex, column ->
                            Box(modifier = Modifier.width(column.width)) {
                                if (columnIndex == 1) {
                                    // خلية الإجراءات — PopupMenuButton (Dart l.253-291).
                                    var menuExpanded by remember { mutableStateOf(false) }
                                    Box {
                                        IconButton(onClick = { menuExpanded = true }) {
                                            Icon(
                                                Icons.Outlined.MoreVert,
                                                contentDescription = "إجراءات",
                                                modifier = Modifier.size(20.dp)
                                            )
                                        }
                                        DropdownMenu(
                                            expanded = menuExpanded,
                                            onDismissRequest = { menuExpanded = false }
                                        ) {
                                            DropdownMenuItem(
                                                text = { Text("تعديل") },
                                                leadingIcon = {
                                                    Icon(Icons.Filled.Edit, contentDescription = null, modifier = Modifier.size(18.dp))
                                                },
                                                onClick = {
                                                    menuExpanded = false
                                                    onEdit(info)
                                                }
                                            )
                                            DropdownMenuItem(
                                                text = { Text("حذف", color = Color(0xFFF44336)) },
                                                leadingIcon = {
                                                    Icon(
                                                        Icons.Outlined.DeleteOutline,
                                                        contentDescription = null,
                                                        modifier = Modifier.size(18.dp),
                                                        tint = Color(0xFFF44336)
                                                    )
                                                },
                                                onClick = {
                                                    menuExpanded = false
                                                    onDelete(info)
                                                }
                                            )
                                        }
                                    }
                                } else {
                                    val value = when (columnIndex) {
                                        0 -> "${index + 1}"
                                        2 -> info.roomNumber
                                        3 -> info.guestName
                                        4 -> info.nationality
                                        5 -> info.idNumber
                                        6 -> info.idType
                                        7 -> info.issueDate ?: "-"
                                        8 -> info.issuePlace ?: "-"
                                        9 -> info.governorate ?: "-"
                                        else -> info.notes ?: "-"
                                    }
                                    Text(
                                        value,
                                        fontWeight = if (columnIndex == 2) FontWeight.Bold else null,
                                        modifier = Modifier.padding(horizontal = 14.dp)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * نظير _openEditor (information_screen.dart l.314-517): حوار إضافة/تعديل
 * بمطابقات تحقق «هذا الحقل مطلوب» ومنتقي تاريخ بنفس النطاق 1990–2100.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InformationEditorDialog(
    existing: GuestInfo?,
    onDismiss: () -> Unit,
    onSave: (
        idType: String, room: String, guestName: String, nationality: String,
        idNumber: String, issueDate: String, issuePlace: String, governorate: String, notes: String
    ) -> Unit
) {
    val idTypesBase = listOf(
        "بطاقة شخصية",
        "جواز سفر",
        "إقامة",
        "رخصة قيادة",
        "بطاقة عائلية",
        "شهادة ميلاد",
        "بطاقة رقم جلوس",
        "استبيان"
    )

    var idTypes by remember {
        val extra = existing?.idType
        mutableStateOf(
            if (extra != null && extra.isNotEmpty() && !idTypesBase.contains(extra)) {
                listOf(extra) + idTypesBase
            } else {
                idTypesBase
            }
        )
    }
    var selectedIdType by remember {
        mutableStateOf(
            existing?.idType?.takeIf { it.isNotEmpty() && idTypes.contains(it) } ?: idTypes.first()
        )
    }

    var room by remember { mutableStateOf(existing?.roomNumber ?: "") }
    var guestName by remember { mutableStateOf(existing?.guestName ?: "") }
    var nationality by remember {
        mutableStateOf(
            if (existing?.nationality?.isNotEmpty() == true) existing.nationality else "يمني"
        )
    }
    var idNumber by remember { mutableStateOf(existing?.idNumber ?: "") }
    var issueDate by remember { mutableStateOf(existing?.issueDate ?: "") }
    var issuePlace by remember { mutableStateOf(existing?.issuePlace ?: "") }
    var governorate by remember { mutableStateOf(existing?.governorate ?: "") }
    var notes by remember { mutableStateOf(existing?.notes ?: "") }

    var roomError by remember { mutableStateOf(false) }
    var guestNameError by remember { mutableStateOf(false) }
    var nationalityError by remember { mutableStateOf(false) }
    var idNumberError by remember { mutableStateOf(false) }

    var idTypeMenuExpanded by remember { mutableStateOf(false) }
    var showDatePicker by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (existing == null) "إضافة معلومية" else "تعديل معلومية") },
        text = {
            Column(
                modifier = Modifier
                    .widthIn(max = 420.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                OutlinedTextField(
                    value = room,
                    onValueChange = { room = it; roomError = false },
                    label = { Text("رقم الغرفة") },
                    isError = roomError && room.trim().isEmpty(),
                    supportingText = {
                        if (roomError && room.trim().isEmpty()) Text("هذا الحقل مطلوب")
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = guestName,
                    onValueChange = { guestName = it; guestNameError = false },
                    label = { Text("اسم النزيل") },
                    isError = guestNameError && guestName.trim().isEmpty(),
                    supportingText = {
                        if (guestNameError && guestName.trim().isEmpty()) Text("هذا الحقل مطلوب")
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = nationality,
                    onValueChange = { nationality = it; nationalityError = false },
                    label = { Text("الجنسية") },
                    isError = nationalityError && nationality.trim().isEmpty(),
                    supportingText = {
                        if (nationalityError && nationality.trim().isEmpty()) Text("هذا الحقل مطلوب")
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = idNumber,
                    onValueChange = { idNumber = it; idNumberError = false },
                    label = { Text("رقم الهوية") },
                    isError = idNumberError && idNumber.trim().isEmpty(),
                    supportingText = {
                        if (idNumberError && idNumber.trim().isEmpty()) Text("هذا الحقل مطلوب")
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                ExposedDropdownMenuBox(
                    expanded = idTypeMenuExpanded,
                    onExpandedChange = { idTypeMenuExpanded = it }
                ) {
                    OutlinedTextField(
                        value = selectedIdType,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("نوع الهوية") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = idTypeMenuExpanded) },
                        modifier = Modifier
                            .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                            .fillMaxWidth()
                    )
                    ExposedDropdownMenu(
                        expanded = idTypeMenuExpanded,
                        onDismissRequest = { idTypeMenuExpanded = false }
                    ) {
                        idTypes.forEach { type ->
                            DropdownMenuItem(
                                text = { Text(type) },
                                onClick = {
                                    selectedIdType = type
                                    idTypeMenuExpanded = false
                                }
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = issueDate,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("تاريخ الإصدار") },
                    trailingIcon = {
                        IconButton(onClick = { showDatePicker = true }) {
                            Icon(Icons.Filled.DateRange, contentDescription = "اختيار التاريخ")
                        }
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = issuePlace,
                    onValueChange = { issuePlace = it },
                    label = { Text("مكان الإصدار") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = governorate,
                    onValueChange = { governorate = it },
                    label = { Text("المحافظة") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("الملاحظات") },
                    minLines = 1,
                    maxLines = 3,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    roomError = room.trim().isEmpty()
                    guestNameError = guestName.trim().isEmpty()
                    nationalityError = nationality.trim().isEmpty()
                    idNumberError = idNumber.trim().isEmpty()
                    if (!roomError && !guestNameError && !nationalityError && !idNumberError) {
                        onSave(
                            selectedIdType, room, guestName, nationality,
                            idNumber, issueDate, issuePlace, governorate, notes
                        )
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

    if (showDatePicker) {
        // نظير _pickIssueDate (information_screen.dart l.561-574):
        // firstDate 1990 / lastDate 2100 وتنسيق yyyy-MM-dd.
        val initialMillis = remember(showDatePicker) {
            parseIssueDate(issueDate) ?: System.currentTimeMillis()
        }
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = initialMillis,
            yearRange = 1990..2100
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        pickerState.selectedDateMillis?.let {
                            issueDate = formatIssueDate(it)
                        }
                        showDatePicker = false
                    }
                ) { Text("موافق") }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) { Text("إلغاء") }
            }
        ) {
            DatePicker(state = pickerState)
        }
    }
}

/** DateTime.tryParse(controller.text) — يقرأ yyyy-MM-dd. */
private fun parseIssueDate(text: String): Long? {
    if (text.isBlank()) return null
    return try {
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
            isLenient = false
        }
        format.parse(text)?.time
    } catch (_: Exception) {
        null
    }
}

/** DateFormat('yyyy-MM-dd').format(picked). */
private fun formatIssueDate(millis: Long): String {
    val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }
    return format.format(Date(millis))
}
