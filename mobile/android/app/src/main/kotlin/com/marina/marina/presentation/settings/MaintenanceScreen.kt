package com.marina.marina.presentation.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.marina.marina.components.MarinaBackButton
import com.marina.marina.components.MarinaTopAppBar
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.domain.util.HotelTimeEngine
import java.text.NumberFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MaintenanceScreen(
    onBack: () -> Unit,
    onOpenSyncHealth: () -> Unit,
    onOpenDiagnostics: () -> Unit,
    onOpenBackup: () -> Unit,
    viewModel: MaintenanceViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(viewModel) { viewModel.refresh() }
    Scaffold(topBar = {
        MarinaTopAppBar(title = { Text("الصيانة") },
            navigationIcon = { MarinaBackButton(onClick = onBack) },
            actions = {
                IconButton(onClick = viewModel::refresh, enabled = !state.loading) {
                    Icon(Icons.Default.Refresh, contentDescription = "تحديث فحص الصيانة")
                }
            })
    }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                MaintenanceCard("فحص محلي آمن") {
                    Text("هذه الشاشة للقراءة فقط: لا تحذف البيانات، ولا تصلح الروابط تلقائياً، ولا تشغّل المزامنة.")
                    Text("نتائج لحظة الفحص وليست مراقبة مباشرة؛ اضغط تحديث بعد المزامنة.",
                        style = MaterialTheme.typography.bodySmall)
                }
            }
            if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            state.error?.let { error -> item {
                MaintenanceCard("تعذر التحديث") {
                    Text(error, color = MaterialTheme.colorScheme.error)
                    Text("الأرقام السابقة، إن ظهرت، ليست نتيجة فحص جديد.")
                    TextButton(onClick = viewModel::refresh, enabled = !state.loading) { Text("إعادة المحاولة") }
                }
            } }
            state.report?.let { report ->
                item {
                    MaintenanceCard("قاعدة البيانات") {
                        Text("إصدار القاعدة: ${report.schemaVersion} • الإصدار المتوقع: ${AppDatabase.SCHEMA_VERSION}")
                        Text("وقت الفحص: ${HotelTimeEngine.formatDisplay(report.capturedAt)}")
                        Text("هذا فحص محدد للأعداد والروابط، وليس ضماناً شاملاً لسلامة القاعدة أو بيانات الخادم.",
                            style = MaterialTheme.typography.bodySmall)
                    }
                }
                item {
                    MaintenanceCard("المزامنة وروابط UUID") {
                        MaintenanceCount("سجلات في الحجر الصحي", report.counts.quarantined)
                        MaintenanceCount("سجلات تنتظر روابط الآباء", report.counts.pendingLinks)
                        MaintenanceCount("ترحيل رواتب بلا employee_uuid", report.counts.missingCarryEmployeeUuid)
                        MaintenanceCount("دفعات رواتب بلا cycle_uuid", report.counts.missingPaymentCycleUuid)
                        Text("عدادات UUID تخص السجلات غير المحذوفة فقط، ولا تفحص صحة كل UUID موجود.",
                            style = MaterialTheme.typography.bodySmall)
                    }
                }
                item {
                    MaintenanceCard("مبالغ دورات الرواتب") {
                        MaintenanceCount("عدد الدورات غير المحذوفة", report.salary.cycles)
                        MaintenanceCount("المتوقع — expected_amount (ر.ي)", report.salary.expected)
                        MaintenanceCount("المدفوع — actual_paid (ر.ي)", report.salary.paid)
                        MaintenanceCount("المتبقي — remaining_amount (ر.ي)", report.salary.remaining)
                        Text("إجماليات الأعمدة المحفوظة لجميع الدورات غير المحذوفة؛ ليست تقرير فترة ولا إعادة حساب للأرصدة.",
                            style = MaterialTheme.typography.bodySmall)
                    }
                }
                item {
                    MaintenanceCard("الحجر الصحي") {
                        Text("تُعرض أسباب الرفض فقط، دون حمولة السجلات أو بيانات الضيوف. لا تُحذف الأدلة ولا يعاد تطبيقها من هنا.")
                        if (report.counts.quarantined == 0L) Text("لا توجد سجلات محجورة.")
                        else Text("الصفحة ${report.page + 1} • المعروض ${report.rows.size} من ${report.counts.quarantined}")
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            TextButton(onClick = viewModel::previousPage, enabled = !state.loading && report.page > 0) {
                                Text("السابق")
                            }
                            TextButton(onClick = viewModel::nextPage, enabled = !state.loading && report.hasNext) {
                                Text("التالي")
                            }
                        }
                    }
                }
                items(report.rows, key = { "${it.entity.length}:${it.entity}${it.recordKey}" }) { row ->
                    MaintenanceCard(row.entity) {
                        Text("المعرف: ${row.recordKey.take(80)}", style = MaterialTheme.typography.bodySmall)
                        Text(row.reason, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
            item {
                MaintenanceCard("أدوات مرتبطة") {
                    TextButton(onClick = onOpenSyncHealth) { Text("حالة المزامنة") }
                    TextButton(onClick = onOpenDiagnostics) { Text("سجل أخطاء المزامنة") }
                    TextButton(onClick = onOpenBackup) { Text("النسخ الاحتياطي والاستعادة") }
                }
            }
        }
    }
}

@Composable
private fun MaintenanceCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    OutlinedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}

@Composable
private fun MaintenanceCount(label: String, value: Long) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, modifier = Modifier.weight(1f))
        Text(NumberFormat.getIntegerInstance(Locale.US).format(value), style = MaterialTheme.typography.titleSmall)
    }
}
