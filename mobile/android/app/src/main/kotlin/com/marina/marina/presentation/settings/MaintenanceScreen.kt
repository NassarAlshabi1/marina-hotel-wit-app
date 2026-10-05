package com.marina.marina.presentation.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
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
    val repairing by viewModel.repairBusy.collectAsStateWithLifecycle()
    val busy = state.loading || repairing
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var entityMenu by remember { mutableStateOf(false) }
    var backupToken by rememberSaveable { mutableStateOf<String?>(null) }
    val reportExport = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) {
        it?.let(viewModel::exportReport)
    }
    val backupExport = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val token = backupToken
        backupToken = null
        if (uri != null && token != null) viewModel.exportBackup(token, uri)
    }
    LaunchedEffect(viewModel, repairing) { if (!repairing) viewModel.refresh() }
    Scaffold(topBar = {
        MarinaTopAppBar(title = { Text("مركز الصيانة") },
            navigationIcon = { MarinaBackButton(onClick = onBack) },
            actions = {
                IconButton(onClick = viewModel::refresh, enabled = !busy) {
                    Icon(Icons.Default.Refresh, contentDescription = "تحديث فحص الصيانة")
                }
            })
    }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            ScrollableTabRow(selectedTabIndex = tab, edgePadding = 8.dp) {
                listOf("نظرة عامة", "الحجر الصحي", "إصلاح آمن", "سجل النتائج").forEachIndexed { index, title ->
                    Tab(selected = tab == index, onClick = { tab = index }, text = { Text(title) })
                }
            }
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item {
                    Column(Modifier.fillMaxWidth().background(
                        Brush.horizontalGradient(listOf(MaterialTheme.colorScheme.primaryContainer,
                            MaterialTheme.colorScheme.secondaryContainer)), RoundedCornerShape(20.dp)
                    ).padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Default.Build, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Text("تشخيص واضح. إصلاح بموافقتك.", style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold)
                        Text("فحص محلي • معاينة قبل التنفيذ • نسخة أمان للحقول المتأثرة • سجل نتائج")
                        state.report?.let { report ->
                            Text("آخر قراءة: ${HotelTimeEngine.formatDisplay(report.capturedAt)}",
                                style = MaterialTheme.typography.bodySmall)
                        }
                        if (repairing) Text("عملية صيانة جارية؛ لا تبدأ عملية ثانية. تُحفظ النتيجة في السجل.")
                        else if (state.loading) Text("جارٍ التنفيذ… الأرقام السابقة ليست قراءة جديدة.")
                    }
                }
                if (busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                state.error?.let { message -> item {
                    MaintenanceCard("تعذر إتمام العملية") {
                        Text(message, color = MaterialTheme.colorScheme.error)
                        Text("قد تكون النتائج المعروضة قديمة. لا تفترض نجاح أي إصلاح دون سجل مكتمل.")
                        TextButton(onClick = viewModel::refresh, enabled = !busy) { Text("تحديث البيانات") }
                    }
                } }
                state.message?.let { message -> item {
                    MaintenanceCard("نتيجة العملية") { Text(message) }
                } }
                state.report?.let { report ->
                    when (tab) {
                        0 -> {
                            item {
                                MaintenanceCard("مؤشرات تحتاج المتابعة") {
                                    MaintenanceCount("سجلات محجورة", report.counts.quarantined)
                                    MaintenanceCount("بانتظار ربط الآباء", report.counts.pendingLinks)
                                    MaintenanceCount("ترحيل بلا employee_uuid", report.counts.missingCarryEmployeeUuid)
                                    MaintenanceCount("دفعات بلا cycle_uuid", report.counts.missingPaymentCycleUuid)
                                    Text("هذه أعداد فحوص محددة، وليست شهادة شاملة بصحة الأرصدة.",
                                        style = MaterialTheme.typography.bodySmall)
                                }
                            }
                            report.integrity?.let { check -> item {
                                MaintenanceCard("سلامة علاقات الرواتب") {
                                    MaintenanceCount("ترحيل مرتبط بموظف مفقود أو محذوف", check.missingEmployees)
                                    MaintenanceCount("دفعات مرتبطة بدورة مفقودة أو محذوفة", check.missingCycles)
                                    MaintenanceCount("تعارض employee_uuid مع الرابط المحلي", check.mismatchedEmployees)
                                    MaintenanceCount("تعارض cycle_uuid مع الرابط المحلي", check.mismatchedCycles)
                                    MaintenanceCount("مجموعات UUID موظفين مكررة", check.duplicateEmployeeUuids)
                                    MaintenanceCount("مجموعات UUID دورات مكررة", check.duplicateCycleUuids)
                                    Text("التعارضات والتكرارات تحتاج مراجعة يدوية؛ لا يعاد توجيه الروابط تلقائياً.")
                                }
                            } }
                            item {
                                MaintenanceCard("قاعدة البيانات") {
                                    Text("الإصدار الفعلي ${report.schemaVersion} • المتوقع ${AppDatabase.SCHEMA_VERSION}")
                                    Text("الفحص السريع يراجع بنية SQLite فقط، وقد يستغرق وقتاً مع البيانات الكبيرة.")
                                    OutlinedButton(onClick = viewModel::quickCheck, enabled = !busy) { Text("تشغيل الفحص السريع") }
                                    state.quickCheck?.let { Text(it) }
                                }
                            }
                            item {
                                MaintenanceCard("إجماليات دورات الرواتب — ر.ي") {
                                    MaintenanceCount("الدورات غير المحذوفة", report.salary.cycles)
                                    MaintenanceCount("المتوقع — expected_amount", report.salary.expected)
                                    MaintenanceCount("المدفوع — actual_paid", report.salary.paid)
                                    MaintenanceCount("المتبقي — remaining_amount", report.salary.remaining)
                                    Text("قراءة الأعمدة المحفوظة لجميع الدورات، دون إعادة حساب أو تحديد فترة.",
                                        style = MaterialTheme.typography.bodySmall)
                                }
                            }
                            item {
                                MaintenanceCard("تقرير ومتابعة") {
                                    Text("تصدير ملخص JSON يشمل الإجماليات والفحوص فقط، دون أسماء الضيوف أو حمولات الحجر الصحي.")
                                    Button(onClick = { reportExport.launch("maintenance-${report.capturedAt}.json") },
                                        enabled = !busy && state.error == null) { Text("حفظ تقرير الصيانة") }
                                    TextButton(onClick = onOpenSyncHealth) { Text("حالة المزامنة") }
                                    TextButton(onClick = onOpenDiagnostics) { Text("أخطاء المزامنة") }
                                    TextButton(onClick = onOpenBackup) { Text("النسخ الاحتياطي الكامل والاستعادة") }
                                }
                            }
                        }
                        1 -> {
                            item {
                                MaintenanceCard("البحث في الحجر الصحي") {
                                    OutlinedTextField(value = state.draftSearch, onValueChange = viewModel::editSearch,
                                        modifier = Modifier.fillMaxWidth(), singleLine = true, enabled = !busy,
                                        label = { Text("الجدول أو المعرف أو سبب الرفض") },
                                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) })
                                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Button(onClick = viewModel::search, enabled = !busy) { Text("بحث") }
                                        Box {
                                            OutlinedButton(onClick = { entityMenu = true }, enabled = !busy) {
                                                Text(state.entity ?: "كل الجداول")
                                            }
                                            DropdownMenu(expanded = entityMenu, onDismissRequest = { entityMenu = false }) {
                                                DropdownMenuItem(text = { Text("كل الجداول") }, onClick = {
                                                    entityMenu = false; viewModel.filter(null)
                                                })
                                                report.entities.forEach { entity ->
                                                    DropdownMenuItem(text = { Text(entity) }, onClick = {
                                                        entityMenu = false; viewModel.filter(entity)
                                                    })
                                                }
                                            }
                                        }
                                    }
                                    Text("${report.filteredCount} نتيجة من ${report.counts.quarantined} • الصفحة ${report.page + 1}")
                                    Text("لا تُحمّل الحمولة الخام، ولا تُحذف الأدلة، ولا يعاد تطبيقها تلقائياً.",
                                        style = MaterialTheme.typography.bodySmall)
                                }
                            }
                            if (report.rows.isEmpty()) item {
                                MaintenanceCard("لا توجد نتائج") { Text("غيّر البحث أو الجدول، أو حدّث الفحص بعد تصحيح المصدر.") }
                            }
                            report.rows.forEach { row -> item(key = "q:${row.entity.length}:${row.entity}${row.recordKey}") {
                                MaintenanceCard(row.entity) {
                                    Text("المعرف: ${row.recordKey.take(80)}", style = MaterialTheme.typography.bodySmall)
                                    Text(row.reason)
                                    TextButton(onClick = { viewModel.detail(row.entity, row.recordKey) }, enabled = !busy) {
                                        Text("التفاصيل والإجراء المقترح")
                                    }
                                }
                            } }
                            item {
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    OutlinedButton(onClick = viewModel::previousPage, enabled = !busy && report.page > 0) { Text("السابق") }
                                    OutlinedButton(onClick = viewModel::nextPage, enabled = !busy && report.hasNext) { Text("التالي") }
                                }
                            }
                        }
                        2 -> {
                            item {
                                MaintenanceCard("إصلاح ذاكرة UUID المحلية") {
                                    Text("١ • افحص الروابط المؤهلة واعرض القيم المقترحة.")
                                    Text("٢ • راجع القائمة وأكد التنفيذ خلال خمس دقائق.")
                                    Text("٣ • تحفظ نسخة أمان للحقول المتأثرة وتُفحص بصمتها قبل أي تعديل.")
                                    Text("٤ • ينفذ الإصلاح في معاملة واحدة ويسجل كل تغيير.")
                                    Text("الحد 100 حقل لكل دفعة. نسخة الأمان تخص حقول UUID وليست نسخة كاملة لقاعدة البيانات.",
                                        style = MaterialTheme.typography.bodySmall)
                                    Button(onClick = viewModel::preview, enabled = !busy) { Text("معاينة الإصلاح الآمن") }
                                }
                            }
                            item {
                                MaintenanceCard("ما لن يغيّره الإصلاح") {
                                    Text("لا تتغير المبالغ أو الأرصدة أو أرقام الآباء أو التواريخ أو الإصدارات أو طابور الرفع.")
                                    Text("يستكمل UUID الفارغ من أب محلي موجود وفريد فقط. تُستبعد السجلات المحجورة والمعلّقة وغير المرفوعة والتعارضات.")
                                    Text("عند تغير البيانات أو الجلسة، أو فشل نسخة الأمان أو التحقق، يُرفض التنفيذ. لا يجري حذف أو دمج أو إعادة تطبيق للمحجور.")
                                    TextButton(onClick = onOpenBackup) { Text("إنشاء نسخة كاملة إضافية من شاشة النسخ الاحتياطي") }
                                }
                            }
                        }
                        3 -> {
                            item { MaintenanceCard("سجل الصيانة المحلية") {
                                Text("${report.historyCount} عملية • الصفحة ${report.historyPage + 1}. الحالة غير المكتملة لا تعني النجاح، ولا يعاد تنفيذها تلقائياً.")
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    TextButton(onClick = { viewModel.historyPage(-1) }, enabled = !busy && report.historyPage > 0) { Text("الأحدث") }
                                    TextButton(onClick = { viewModel.historyPage(1) },
                                        enabled = !busy && (report.historyPage + 1) * 20 < report.historyCount) { Text("الأقدم") }
                                }
                            } }
                            if (report.history.isEmpty()) item {
                                MaintenanceCard("لم تنفذ عمليات بعد") { Text("ابدأ بمعاينة الإصلاح؛ المعاينة وحدها لا تغيّر البيانات.") }
                            }
                            report.history.forEach { run -> item(key = "run:${run.id}") {
                                MaintenanceCard(when (run.status) {
                                    "completed" -> "مكتمل"
                                    "failed" -> "فشل — لم يعتمد إصلاح"
                                    "interrupted" -> "توقف — لم يعتمد إصلاح"
                                    else -> "قيد التنفيذ أو غير مكتمل"
                                }) {
                                    Text("${HotelTimeEngine.formatDisplay(run.startedAtEpoch)} • ${run.runUuid.take(8)}")
                                    MaintenanceCount("الحقول المعتمدة", run.fixesApplied)
                                    run.errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                                    if (run.status == "completed") {
                                        Text("نسخة أمان الحقول محفوظة على هذا الجهاز؛ يتم التحقق من بصمتها قبل التصدير.",
                                            style = MaterialTheme.typography.bodySmall)
                                        TextButton(enabled = !busy, onClick = {
                                            backupToken = run.runUuid
                                            backupExport.launch("uuid-cache-${run.runUuid}.json")
                                        }) { Text("تصدير نسخة أمان الحقول") }
                                    }
                                }
                            } }
                        }
                    }
                }
            }
        }
    }
    state.detail?.let { detail ->
        AlertDialog(onDismissRequest = viewModel::dismissDetail,
            title = { Text("تفاصيل السجل المحجور") },
            text = {
                SelectionContainer {
                    Column(Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(detail.entity, style = MaterialTheme.typography.titleMedium)
                        Text(detail.recordKey)
                        Text(detail.reason)
                        Text("حجم الحمولة: ${detail.payloadCharacters} حرف — لم تُحمّل أو تُعرض")
                        Text(quarantineAdvice(detail.reason), color = MaterialTheme.colorScheme.primary)
                        Text("قد يكون السبب المعروض مختصراً؛ لا تصلح أو تحذف السجل اعتماداً على التخمين.")
                    }
                }
            }, confirmButton = { TextButton(onClick = viewModel::dismissDetail) { Text("إغلاق") } })
    }
    state.plan?.let { plan ->
        var confirmed by remember(plan.token) { mutableStateOf(false) }
        AlertDialog(onDismissRequest = { if (!busy) viewModel.dismissPlan() },
            title = { Text("معاينة ${plan.entries.size} إصلاحاً محلياً") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("ستحفظ نسخة أمان لحقول UUID قبل التعديل. لا تتغير الأرصدة ولا يرفع شيء للخادم.")
                    if (plan.hasMore) Text("توجد مرشحات إضافية؛ هذه الدفعة محدودة بمئة حقل. أعد المعاينة بعد التنفيذ.")
                    if (plan.entries.isEmpty()) Text("لا يوجد إصلاح آمن مؤكد؛ الحالات الأخرى تحتاج مراجعة يدوية.")
                    Column(Modifier.heightIn(max = 220.dp).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        plan.entries.forEach { entry ->
                            Text("${entry.table} #${entry.rowId}\n${entry.field}: فارغ ← ${entry.newValue}",
                                style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    Row {
                        Checkbox(checked = confirmed, onCheckedChange = { confirmed = it }, enabled = !busy)
                        Text("راجعت القائمة وأوافق على إصلاح الحقول المذكورة فقط؛ نسخة الأمان ليست نسخة كاملة.")
                    }
                }
            },
            confirmButton = { Button(onClick = viewModel::repair, enabled = confirmed && !busy && plan.entries.isNotEmpty()) {
                Text("حفظ نسخة الأمان ثم التنفيذ")
            } },
            dismissButton = { TextButton(onClick = viewModel::dismissPlan, enabled = !busy) { Text("إلغاء") } })
    }
}

internal fun quarantineAdvice(reason: String): String = when {
    reason.contains("missing_local_uuid") -> "تحقق من هوية السجل في المصدر. لا تُنشئ UUID بديلاً عشوائياً."
    reason.contains("unsupported_entity") || reason.contains("missing_entity") ->
        "راجع اسم الجدول وتوافق إصدار التطبيق مع مخطط الخادم قبل إعادة السحب."
    reason.contains("does not match") -> "راجع الموظف والدورة المرجعية في المصدر؛ لا تعِد توجيه العلاقة تلقائياً."
    else -> "راجع نوع الحقول والعلاقة المرجعية في المصدر، ثم صحح المصدر وأعد السحب من أدوات المزامنة."
}

@Composable
private fun MaintenanceCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    OutlinedCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
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
