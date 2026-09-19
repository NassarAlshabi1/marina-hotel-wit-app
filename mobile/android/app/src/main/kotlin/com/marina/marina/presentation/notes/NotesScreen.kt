package com.marina.marina.presentation.notes

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.ShiftNote
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun NotesScreen(
    viewModel: NotesViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var editingNote by remember { mutableStateOf<ShiftNote?>(null) }
    var deleteConfirmNote by remember { mutableStateOf<ShiftNote?>(null) }

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
                    title = { Text("ملاحظات الورديات", style = AppTypography.titleLarge) },
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
                TabRow(selectedTabIndex = state.tab) {
                    Tab(
                        selected = state.tab == 0,
                        onClick = { viewModel.setTab(0) },
                        text = { Text("الكل (${state.notes.size})") }
                    )
                    Tab(
                        selected = state.tab == 1,
                        onClick = { viewModel.setTab(1) },
                        text = { Text("غير مقروءة (${state.unreadCount})") }
                    )
                    Tab(
                        selected = state.tab == 2,
                        onClick = { viewModel.setTab(2) },
                        text = { Text("عالية (${state.highCount})") }
                    )
                }

                Spacer(modifier = Modifier.height(10.dp))

                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        "تعذر تحميل الملاحظات: ${state.error}",
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor,
                        modifier = Modifier.padding(16.dp)
                    )
                    state.filtered.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        contentAlignment = Alignment.Center
                    ) { Text("لا توجد ملاحظات", style = AppTypography.bodyLarge, color = AppColors.TextSecondary) }
                    else -> LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(bottom = 88.dp)
                    ) {
                        items(state.filtered, key = { it.id }) { note ->
                            NoteCard(
                                note = note,
                                onMarkRead = { viewModel.markRead(note) },
                                onEdit = { editingNote = note },
                                onDelete = { deleteConfirmNote = note }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showAddDialog) {
        NoteDialog(
            note = null,
            onDismiss = { showAddDialog = false },
            onSave = { viewModel.saveNote(it); showAddDialog = false }
        )
    }

    editingNote?.let { note ->
        NoteDialog(
            note = note,
            onDismiss = { editingNote = null },
            onSave = { viewModel.saveNote(it); editingNote = null }
        )
    }

    deleteConfirmNote?.let { note ->
        AlertDialog(
            onDismissRequest = { deleteConfirmNote = null },
            title = { Text("حذف الملاحظة") },
            text = { Text("سيتم حذف \"${note.title}\". المتابعة؟") },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteNote(note); deleteConfirmNote = null }) {
                    Text("حذف", color = AppColors.DangerColor)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteConfirmNote = null }) { Text("إلغاء") }
            }
        )
    }
}

private val dateFormat = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.US)

@Composable
private fun NoteCard(
    note: ShiftNote,
    onMarkRead: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    val priorityColor = when (note.priority.lowercase()) {
        "high" -> AppColors.DangerColor
        "medium" -> AppColors.WarningColor
        else -> AppColors.SuccessColor
    }
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(modifier = Modifier.height(intrinsicSize = IntrinsicSize.Min)) {
            Box(
                modifier = Modifier
                    .width(6.dp)
                    .fillMaxHeight()
                    .background(priorityColor)
            )
            Column(modifier = Modifier.padding(12.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (!note.isRead) {
                            Box(
                                modifier = Modifier
                                    .size(8.dp)
                                    .background(AppColors.InfoColor, CircleShape)
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                        }
                        Text(
                            note.title,
                            style = AppTypography.titleSmall,
                            fontWeight = FontWeight.Bold,
                            textDecoration = if (note.isRead) TextDecoration.LineThrough else null,
                            color = if (note.isRead) AppColors.TextSecondary else AppColors.TextPrimary
                        )
                    }
                    Text(
                        if (note.createdAt > 0) dateFormat.format(Date(note.createdAt)) else "",
                        style = AppTypography.labelSmall,
                        color = AppColors.TextSecondary
                    )
                }
                Text(note.content, style = AppTypography.bodyMedium, color = AppColors.TextSecondary, maxLines = 3)
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (!note.isRead) {
                        TextButton(onClick = onMarkRead) { Text("تم القراءة", fontSize = 11.sp, color = AppColors.SuccessColor) }
                    }
                    TextButton(onClick = onEdit) { Text("تعديل", fontSize = 11.sp, color = AppColors.InfoColor) }
                    TextButton(onClick = onDelete) { Text("حذف", fontSize = 11.sp, color = AppColors.DangerColor) }
                }
            }
        }
    }
}

@Composable
private fun NoteDialog(
    note: ShiftNote?,
    onDismiss: () -> Unit,
    onSave: (ShiftNote) -> Unit
) {
    var title by remember { mutableStateOf(note?.title ?: "") }
    var content by remember { mutableStateOf(note?.content ?: "") }
    var priority by remember { mutableStateOf(note?.priority ?: "medium") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (note == null) "ملاحظة جديدة" else "تعديل الملاحظة", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("العنوان") }, singleLine = true)
                OutlinedTextField(
                    value = content,
                    onValueChange = { content = it },
                    label = { Text("المحتوى") },
                    minLines = 3
                )
                Text("الأولوية", style = AppTypography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("low" to "منخفضة", "medium" to "متوسطة", "high" to "عالية").forEach { (key, label) ->
                        FilterChip(selected = priority == key, onClick = { priority = key }, label = { Text(label, fontSize = 12.sp) })
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (title.isBlank()) return@TextButton
                    onSave(
                        (note ?: ShiftNote()).copy(
                            title = title.trim(),
                            content = content.trim(),
                            priority = priority
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
