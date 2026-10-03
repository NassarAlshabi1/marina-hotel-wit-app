package com.marina.marina.presentation.settings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.data.remote.SyncErrorRecord
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.components.MarinaBackButton
import com.marina.marina.components.MarinaTopAppBar
import com.marina.marina.components.MarinaToolbarActionButton
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SyncDiagnosticsScreen(
    onBack: () -> Unit = {},
    viewModel: SyncDiagnosticsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val clipboard = LocalClipboardManager.current
    var showClearConfirmation by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = AppColors.BackgroundColor,
        topBar = {
            MarinaTopAppBar(
                title = { Text("سجل أخطاء المزامنة", style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    MarinaBackButton(onClick = onBack)
                },
                actions = {
                    MarinaToolbarActionButton(onClick = viewModel::refresh) {
                        Icon(Icons.Default.Refresh, contentDescription = "تحديث السجل")
                    }
                    MarinaToolbarActionButton(
                        onClick = { showClearConfirmation = true },
                        enabled = state.errors.isNotEmpty(),
                        containerColor = AppColors.DangerActionColor
                    ) {
                        Icon(Icons.Default.DeleteOutline, contentDescription = "مسح السجل")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.SurfaceColor,
                    titleContentColor = AppColors.TextPrimary
                )
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                OutlinedCard(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.outlinedCardColors(containerColor = AppColors.SurfaceColor),
                    shape = RoundedCornerShape(18.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.ErrorOutline,
                                contentDescription = null,
                                tint = if (state.errors.isEmpty()) AppColors.SuccessColor else AppColors.DangerColor,
                                modifier = Modifier.size(22.dp)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                if (state.errors.isEmpty()) "لا توجد أخطاء محفوظة"
                                else "الأخطاء المحفوظة: ${state.errors.size}",
                                fontWeight = FontWeight.Bold,
                                color = AppColors.TextPrimary
                            )
                        }
                        Text(
                            "يحفظ التطبيق محلياً آخر 40 خطأ من عمليات السحب والرفع وتسجيل الدخول. " +
                                "لا تُحفظ حمولة السجلات أو رموز الدخول. افتح أي خطأ لنسخ تفاصيله وإرسالها للدعم.",
                            fontSize = 12.sp,
                            color = AppColors.TextSecondary
                        )
                    }
                }
            }

            if (state.errors.isEmpty()) {
                item {
                    OutlinedCard(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.outlinedCardColors(containerColor = AppColors.SurfaceColor)
                    ) {
                        Box(
                            modifier = Modifier.fillMaxWidth().padding(28.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("ستظهر هنا تفاصيل الخطأ عند تعذّر المزامنة.", color = AppColors.TextSecondary)
                        }
                    }
                }
            } else {
                items(state.errors, key = { it.id.ifBlank { "${it.occurredAtMillis}-${it.operation}" } }) { entry ->
                    SyncErrorCard(
                        entry = entry,
                        onCopy = {
                            clipboard.setText(AnnotatedString(entry.toDiagnosticText()))
                        }
                    )
                }
            }
        }
    }

    if (showClearConfirmation) {
        AlertDialog(
            onDismissRequest = { showClearConfirmation = false },
            title = { Text("مسح سجل الأخطاء؟") },
            text = { Text("سيُمسح سجل التشخيص المحلي فقط. لا يؤثر ذلك في بيانات الفندق أو حالة المزامنة.") },
            confirmButton = {
                Button(
                    onClick = {
                        viewModel.clearHistory()
                        showClearConfirmation = false
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = AppColors.DangerActionColor,
                        contentColor = Color.White
                    )
                ) { Text("مسح السجل") }
            },
            dismissButton = {
                TextButton(onClick = { showClearConfirmation = false }) { Text("إلغاء") }
            }
        )
    }
}

@Composable
private fun SyncErrorCard(
    entry: SyncErrorRecord,
    onCopy: () -> Unit
) {
    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.outlinedCardColors(containerColor = AppColors.SurfaceColor),
        border = BorderStroke(1.dp, AppColors.DangerColor.copy(alpha = 0.35f)),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.ErrorOutline,
                    contentDescription = null,
                    tint = AppColors.DangerColor,
                    modifier = Modifier.size(19.dp)
                )
                Spacer(Modifier.width(8.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        operationLabel(entry.operation),
                        fontWeight = FontWeight.Bold,
                        color = AppColors.DangerColor,
                        fontSize = 14.sp
                    )
                    Text(
                        formatErrorTime(entry.occurredAtMillis),
                        color = AppColors.TextSecondary,
                        fontSize = 11.sp
                    )
                }
            }

            SelectionContainer {
                Text(
                    text = entry.message,
                    color = AppColors.TextPrimary,
                    fontSize = 13.sp,
                    lineHeight = 19.sp
                )
            }

            Text(
                text = "آخر مؤشر سحب معتمد: ${entry.pullCursor}" +
                    (entry.deviceId?.takeIf { it.isNotBlank() }?.let { " · الجهاز: $it" } ?: ""),
                color = AppColors.TextSecondary,
                fontSize = 10.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onCopy) {
                    Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("نسخ التفاصيل", fontSize = 12.sp)
                }
            }
        }
    }
}

private fun operationLabel(operation: String): String = when (operation) {
    "pull_delta" -> "فشل سحب التغييرات"
    "pull_full" -> "فشل السحب الكامل"
    "push" -> "فشل رفع التغييرات"
    "login" -> "فشل تسجيل الدخول"
    else -> "خطأ مزامنة"
}

private fun formatErrorTime(timestampMillis: Long): String =
    if (timestampMillis <= 0L) "وقت غير معروف"
    else SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(timestampMillis))

private fun SyncErrorRecord.toDiagnosticText(): String = buildString {
    appendLine("العملية: ${operationLabel(operation)}")
    appendLine("الوقت: ${formatErrorTime(occurredAtMillis)}")
    appendLine("آخر مؤشر سحب معتمد: $pullCursor")
    deviceId?.takeIf { it.isNotBlank() }?.let { appendLine("الجهاز: $it") }
    append("الخطأ: $message")
}
