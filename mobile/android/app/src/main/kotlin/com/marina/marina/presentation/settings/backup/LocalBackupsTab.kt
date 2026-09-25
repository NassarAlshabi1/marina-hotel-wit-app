package com.marina.marina.presentation.settings.backup

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.outlined.Backup
import androidx.compose.material.icons.filled.DataUsage
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FilePresent
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.GridOn
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.SdStorage
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.data.backup.BackupFormat
import com.marina.marina.data.backup.BackupState
import com.marina.marina.data.backup.LocalBackupFile
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * تبويب النسخ المحلية — نقل LocalBackupsTab (local_backups_tab.dart)
 * 1:1: بطاقة معلومات التخزين، أزرار الإجراءات السريعة (نسخ الآن /
 * استيراد نسخة / تصدير Excel)، بطاقة آخر نسخة، قائمة النسخ مع قائمة
 * منبثقة (استعادة/مشاركة/حذف)، وطبقة التقدم السفلية.
 */
@Composable
fun LocalBackupsTab(
    viewModel: BackupViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var restoreTarget by remember { mutableStateOf<LocalBackupFile?>(null) }
    var deleteTarget by remember { mutableStateOf<LocalBackupFile?>(null) }

    // منتقي الملفات للاستيراد — نظير file_picker في Dart
    val importLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) viewModel.importBackupFromFile(uri)
    }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                BackupUi.spacingMD.dp
            ),
            verticalArrangement = Arrangement.spacedBy(BackupUi.spacingSM.dp)
        ) {
            // معلومات التخزين
            item { StorageInfoCard(state, viewModel) }
            item { Spacer(Modifier.height(BackupUi.spacingLG.dp - 8.dp)) }

            // أزرار الإجراءات السريعة
            item { QuickActionsRow(state, viewModel, importLauncher) }
            item { Spacer(Modifier.height(BackupUi.spacingLG.dp - 8.dp)) }

            // آخر نسخة محلية
            if (state.lastLocalBackupTime != null) {
                item { LastBackupCard(state.lastLocalBackupTime!!, viewModel) }
                item { Spacer(Modifier.height(BackupUi.spacingLG.dp - 8.dp)) }
            }

            // قائمة النسخ المحلية
            item {
                BackupSectionHeader(
                    title = "النسخ المحلية (${state.localBackups.size})",
                    icon = Icons.Filled.PhoneAndroid,
                    action = {
                        IconButton(
                            onClick = { viewModel.checkStoragePermissions() },
                            enabled = !state.isWorking
                        ) {
                            Icon(Icons.Filled.Refresh, contentDescription = "تحديث")
                        }
                    }
                )
            }

            if (state.localBackups.isEmpty()) {
                item { EmptyBackupsCard() }
            } else {
                items(state.localBackups.size) { index ->
                    val backup = state.localBackups[index]
                    BackupItem(
                        backup = backup,
                        onRestore = { restoreTarget = backup },
                        onShare = { viewModel.shareLocalBackup(backup.filePath) },
                        onDelete = { deleteTarget = backup }
                    )
                }
            }

            item { Spacer(Modifier.height(80.dp)) }
        }

        // شريط التقدم السفلي — نظير _buildProgressOverlay
        if (state.isWorking && state.progress != null) {
            Column(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    // ✅ (2026-09-25) surface من الثيم بدل أبيض صلب — كان يكسر الوضع الداكن.
                    .background(MaterialTheme.colorScheme.surface)
                    .padding(16.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp
                    )
                    Spacer(Modifier.width(12.dp))
                    Text(
                        state.message ?: "جاري المعالجة...",
                        fontSize = 13.sp,
                        modifier = Modifier.weight(1f)
                    )
                }
                Spacer(Modifier.height(8.dp))
                LinearProgressIndicator(
                    progress = { (state.progress ?: 0.0).toFloat() },
                    trackColor = BackupUi.grey100,
                    color = BackupUi.backupColor,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }

    // حوار تأكيد الاستعادة — نفس نصوص Dart
    restoreTarget?.let { backup ->
        AlertDialog(
            onDismissRequest = { restoreTarget = null },
            title = { Text("تأكيد الاستعادة") },
            text = {
                Text(
                    "سيتم استبدال جميع البيانات الحالية ببيانات النسخة الاحتياطية.\n\n" +
                        "الملف: ${backup.fileName}\n" +
                        "التاريخ: ${formatDateTime(backup.createdTime)}\n" +
                        "الحجم: ${viewModel.formatSize(backup.sizeBytes)}"
                )
            },
            dismissButton = {
                TextButton(onClick = { restoreTarget = null }) { Text("إلغاء") }
            },
            confirmButton = {
                Button(
                    onClick = {
                        restoreTarget = null
                        viewModel.restoreFromLocalBackup(backup.filePath)
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFFF9800),
                        contentColor = Color.White
                    )
                ) { Text("استعادة") }
            }
        )
    }

    // حوار تأكيد الحذف — نفس نصوص Dart
    deleteTarget?.let { backup ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text("حذف نسخة احتياطية") },
            text = {
                Text(
                    "هل أنت متأكد من حذف:\n${backup.fileName}؟\n\n" +
                        "لا يمكن التراجع عن هذا الإجراء."
                )
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) { Text("إلغاء") }
            },
            confirmButton = {
                Button(
                    onClick = {
                        deleteTarget = null
                        viewModel.deleteLocalBackup(backup.filePath)
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFF44336),
                        contentColor = Color.White
                    )
                ) { Text("حذف") }
            }
        )
    }
}

/** بطاقة معلومات التخزين — نظير _buildStorageInfoCard. */
@Composable
private fun StorageInfoCard(state: BackupState, viewModel: BackupViewModel) {
    Card(
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(BackupUi.radiusLG.dp)
    ) {
        Column(Modifier.padding(BackupUi.spacingMD.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.SdStorage,
                    contentDescription = null,
                    tint = if (state.hasStoragePermission) Color(0xFF4CAF50) else Color(0xFFF44336),
                    modifier = Modifier.size(BackupUi.iconSizeMD.dp)
                )
                Spacer(Modifier.width(BackupUi.spacingSM.dp))
                Text("تخزين الجهاز", fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                if (!state.hasStoragePermission) {
                    TextButton(onClick = { viewModel.checkStoragePermissions() }) {
                        Icon(
                            Icons.Filled.LockOpen,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(Modifier.width(4.dp))
                        Text("منح الأذونات", color = Color(0xFFF44336))
                    }
                }
            }
            Spacer(Modifier.height(BackupUi.spacingMD.dp))
            InfoRow("المسار", state.backupFolderPath ?: "جاري التحميل...", Icons.Filled.Folder)
            InfoRow("عدد النسخ", "${state.backupsCount} نسخة", Icons.Filled.Layers)
            InfoRow(
                "المساحة المستخدمة",
                "${state.totalSizeMb} ميجابايت",
                Icons.Filled.DataUsage
            )
        }
    }
}

/** أزرار الإجراءات السريعة — نظير _buildQuickActionsRow. */
@Composable
private fun QuickActionsRow(
    state: BackupState,
    viewModel: BackupViewModel,
    importLauncher: androidx.activity.compose.ManagedActivityResultLauncher<Array<String>, android.net.Uri?>
) {
    val busy = state.isWorking || state.isExportingExcel
    Column {
        Row {
            ElevatedButton(
                onClick = { viewModel.createLocalBackup() },
                enabled = !busy,
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.elevatedButtonColors(
                    containerColor = BackupUi.backupColor,
                    contentColor = Color.White
                )
            ) {
                if (state.isWorking) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Color.White
                    )
                } else {
                    Icon(Icons.Filled.Backup, contentDescription = null)
                }
                Spacer(Modifier.width(8.dp))
                Text("نسخ الآن")
            }
            Spacer(Modifier.width(BackupUi.spacingMD.dp))
            OutlinedButton(
                onClick = { importLauncher.launch(arrayOf("*/*")) },
                enabled = !busy,
                modifier = Modifier.weight(1f)
            ) {
                Icon(Icons.Filled.FileDownload, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("استيراد نسخة")
            }
        }
        Spacer(Modifier.height(BackupUi.spacingMD.dp))
        OutlinedButton(
            onClick = { viewModel.exportDatabaseToExcel() },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth()
        ) {
            if (state.isExportingExcel) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
            } else {
                Icon(Icons.Filled.GridOn, contentDescription = null)
            }
            Spacer(Modifier.width(8.dp))
            Text(if (state.isExportingExcel) "جاري التصدير..." else "تصدير قاعدة البيانات إلى Excel")
        }
    }
}

/** بطاقة آخر نسخة محلية — نظير _buildLastBackupCard. */
@Composable
private fun LastBackupCard(lastBackupTime: Long, viewModel: BackupViewModel) {
    Card(
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(BackupUi.radiusLG.dp)
    ) {
        Row(Modifier.padding(BackupUi.spacingMD.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Filled.History,
                contentDescription = null,
                tint = Color(0xFF42A5F5),
                modifier = Modifier.size(BackupUi.iconSizeMD.dp)
            )
            Spacer(Modifier.width(BackupUi.spacingSM.dp))
            Column {
                Text("آخر نسخة محلية", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.height(2.dp))
                Text(
                    "${viewModel.relativeTime(lastBackupTime)} - ${formatDateTime(lastBackupTime)}",
                    fontSize = 12.sp,
                    color = BackupUi.grey600
                )
            }
        }
    }
}

/** حالة فارغة — نظير _buildEmptyState. */
@Composable
private fun EmptyBackupsCard() {
    Card(
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(BackupUi.radiusLG.dp)
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                Icons.Outlined.Backup,
                contentDescription = null,
                tint = BackupUi.grey400,
                modifier = Modifier.size(48.dp)
            )
            Spacer(Modifier.height(BackupUi.spacingMD.dp))
            Text(
                "لا توجد نسخ احتياطية محلية",
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = BackupUi.grey700
            )
            Spacer(Modifier.height(BackupUi.spacingSM.dp))
            Text(
                "اضغط \"نسخ الآن\" لإنشاء أول نسخة احتياطية",
                fontSize = 13.sp,
                color = BackupUi.grey500,
                textAlign = TextAlign.Center
            )
        }
    }
}

/** عنصر نسخة في القائمة — نظير _buildBackupItem. */
@Composable
private fun BackupItem(
    backup: LocalBackupFile,
    onRestore: () -> Unit,
    onShare: () -> Unit,
    onDelete: () -> Unit
) {
    var menuOpen by remember { mutableStateOf(false) }
    val formatLabel = if (backup.format == BackupFormat.sqlite) "SQLite" else "JSON"

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = BackupUi.spacingSM.dp)
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            // leading — أيقونة الملف على خلفية خضراء شفافة
            Box(
                Modifier
                    .background(Color(0x1A4CAF50), RoundedCornerShape(BackupUi.radiusMD.dp))
                    .padding(BackupUi.spacingSM.dp)
            ) {
                Icon(Icons.Filled.FilePresent, contentDescription = null, tint = Color(0xFF4CAF50))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        backup.metadata?.deviceInfo ?: "نسخة محلية",
                        fontWeight = FontWeight.W600,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    Spacer(Modifier.width(8.dp))
                    Box(
                        Modifier
                            .background(Color(0x1A2196F3), RoundedCornerShape(4.dp))
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    ) {
                        Text(
                            formatLabel,
                            fontSize = 10.sp,
                            color = Color(0xFF1976D2),
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
                Spacer(Modifier.height(4.dp))
                Text(formatDateTime(backup.createdTime), fontSize = 12.sp)
                Row {
                    Text(formatSize(backup.sizeBytes), fontSize = 11.sp)
                    backup.metadata?.let { meta ->
                        Spacer(Modifier.width(8.dp))
                        Text("${meta.totalRecords} سجل", fontSize = 11.sp)
                        Spacer(Modifier.width(8.dp))
                        Text(
                            "v${meta.databaseVersion}",
                            fontSize = 11.sp,
                            color = BackupUi.grey500
                        )
                    }
                }
            }
            // قائمة منبثقة (استعادة/مشاركة/حذف) — نظير PopupMenuButton
            Box {
                IconButton(onClick = { menuOpen = true }) {
                    Icon(Icons.Filled.MoreVert, contentDescription = "خيارات")
                }
                androidx.compose.material3.DropdownMenu(
                    expanded = menuOpen,
                    onDismissRequest = { menuOpen = false }
                ) {
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("استعادة") },
                        leadingIcon = { Icon(Icons.Filled.Restore, null, modifier = Modifier.size(20.dp)) },
                        onClick = { menuOpen = false; onRestore() }
                    )
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("مشاركة") },
                        leadingIcon = { Icon(Icons.Filled.Share, null, modifier = Modifier.size(20.dp)) },
                        onClick = { menuOpen = false; onShare() }
                    )
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("حذف", color = Color(0xFFF44336)) },
                        leadingIcon = {
                            Icon(
                                Icons.Filled.Delete,
                                null,
                                modifier = Modifier.size(20.dp),
                                tint = Color(0xFFF44336)
                            )
                        },
                        onClick = { menuOpen = false; onDelete() }
                    )
                }
            }
        }
    }
}

/** formatDateTime — نظير DateTimeFormatter.formatDateTime في Dart. */
internal fun formatDateTime(millis: Long): String =
    SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date(millis))

private fun formatSize(bytes: Long): String =
    com.marina.marina.data.backup.FileSizeFormatter.formatBytes(bytes)
