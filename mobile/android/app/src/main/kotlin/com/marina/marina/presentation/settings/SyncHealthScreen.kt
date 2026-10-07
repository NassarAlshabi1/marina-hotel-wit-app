package com.marina.marina.presentation.settings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.marina.marina.components.MarinaBackButton
import com.marina.marina.components.MarinaTopAppBar
import com.marina.marina.data.diagnostics.SyncHealthLevel
import com.marina.marina.domain.util.HotelTimeEngine
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SyncHealthScreen(
    onBack: () -> Unit,
    onOpenDiagnostics: () -> Unit,
    onOpenSettings: () -> Unit,
    viewModel: SyncHealthViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val sync by viewModel.syncState.collectAsStateWithLifecycle()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle, viewModel) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (isActive) {
                viewModel.refresh().join()
                delay(30_000)
            }
        }
    }
    Scaffold(topBar = {
        MarinaTopAppBar(title = { Text("حالة المزامنة") },
            navigationIcon = { MarinaBackButton(onClick = onBack) },
            actions = {
                IconButton(onClick = { viewModel.refresh() }, enabled = !state.loading) {
                    Icon(Icons.Default.Refresh, contentDescription = "تحديث حالة المزامنة")
                }
            })
    }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            if (state.error != null) item {
                HealthCard("تعذر تحديث التقرير") {
                    Text(state.error.orEmpty(), color = MaterialTheme.colorScheme.error)
                    Text("لا تعتبر الأرقام السابقة تقريراً محدثاً.")
                    TextButton(onClick = { viewModel.refresh() }) { Text("إعادة المحاولة") }
                }
            }
            item {
                HealthCard("المحرك الآن") {
                    Text(when {
                        sync.isSyncing -> sync.lastMessage.ifBlank { "المزامنة جارية" }
                        sync.isError -> sync.lastMessage
                        else -> "لا توجد عملية مزامنة جارية"
                    })
                    if (sync.isSyncing) LinearProgressIndicator(Modifier.fillMaxWidth())
                    Text("المزامنة السحابية: ${when (state.enabled) { true -> "مفعّلة"; false -> "معطّلة"; null -> "لم تُقرأ بعد" }}")
                    Text("آخر رفع ناجح: ${timestamp(state.lastPush)}")
                    Text("آخر سحب ناجح: ${timestamp(state.lastPull)}")
                    Text("هذه حالة محلية، وليست فحص اتصال مباشر بالخادم.", style = MaterialTheme.typography.bodySmall)
                }
            }
            state.report?.let { report ->
                item {
                    HealthCard("الحالة العامة") {
                        Text(report.level.label, style = MaterialTheme.typography.headlineSmall,
                            color = if (report.level in listOf(SyncHealthLevel.ERROR, SyncHealthLevel.CRITICAL))
                                MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
                        Text("آخر تحديث: ${timestamp(report.timestamp)}")
                    }
                }
                item {
                    HealthCard("صندوق الصادر (Outbox)") {
                        HealthRow("معلق", report.pending)
                        HealthRow("قيد المعالجة", report.processing)
                        HealthRow("فشل", report.failed)
                        HealthRow("مكتمل — السجلات المحتفظ بها فقط", report.completed)
                        HealthRow("عالق في المعالجة لأكثر من 5 دقائق", report.stuck)
                        Text("عمر أقدم تغيير غير مسلّم: ${report.oldestAgeMs?.let { "${it / 60_000} دقيقة" } ?: "لا يوجد وقت معروف"}")
                    }
                }
                item {
                    HealthCard("التغييرات غير المسلّمة حسب الكيان") {
                        if (report.entities.isEmpty()) Text("لا توجد تغييرات محلية غير مسلّمة")
                        report.entities.forEach { (entity, count) -> HealthRow(entity, count) }
                    }
                }
                item {
                    HealthCard("الجداول المزامَنة — عدد السجلات (${report.tables.size})") {
                        report.tables.forEach { (entity, count) ->
                            // -1 = الجدول غير موجود محلياً (ترحيل ناقص/نسخة أقدم)
                            HealthRow(entity, count, unknown = count < 0)
                        }
                        Text("كل الكيانات الـ24 التي يسحبها المحرك — لا قائمة جزئية.", style = MaterialTheme.typography.bodySmall)
                        Text("يشمل السجلات المحذوفة ناعماً؛ ليست أحجاماً بالبايت.", style = MaterialTheme.typography.bodySmall)
                    }
                }
                if (report.quarantined > 0) {
                    item {
                        HealthCard("سجلات معزولة (فشل تطبيقها عند السحب)") {
                            HealthRow("معزول", report.quarantined)
                            Text(
                                "تُعاد محاولة تطبيقها من حمولتها المحفوظة في كل دورة سحب، " +
                                    "ولا توقف تقدم بقية الجداول.",
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                    }
                }
                item {
                    HealthCard("سلامة العلاقات") {
                        HealthRow("انتهاكات SQLite FK", report.fkViolations)
                        Text("يفحص القيود المعرّفة في SQLite فقط؛ لا يثبت سلامة كل الروابط المنطقية أو بيانات الخادم.", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            item {
                HealthCard("أدوات المتابعة") {
                    TextButton(onClick = onOpenDiagnostics) { Text("سجل أخطاء المزامنة (${state.errorCount})") }
                    TextButton(onClick = onOpenSettings) { Text("فتح إعدادات المزامنة") }
                }
            }
        }
    }
}

private fun timestamp(value: Long): String = if (value > 0) HotelTimeEngine.formatDisplay(value) else "لم يُسجل بعد"

@Composable
private fun HealthCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    OutlinedCard(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}

@Composable
private fun HealthRow(label: String, count: Long, unknown: Boolean = false) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, modifier = Modifier.weight(1f))
        Text(
            if (unknown) "غير متاح" else count.toString(),
            style = MaterialTheme.typography.titleSmall,
            color = if (unknown) MaterialTheme.colorScheme.outline else Color.Unspecified
        )
    }
}
