package com.marina.marina.presentation.settings.backup

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * تبويب رفع بيانات جداول المزامنة إلى Cloudflare D1 — نقل
 * CloudflareD1Tab (cloudflare_d1_tab.dart) 1:1: بطاقة الاتصال،
 * إعدادات الحساب/القاعدة/التوكن/وسم الجهاز، فحص الاتصال والصلاحيات،
 * قائمة الجداول المحلية بالأعداد مع تحديد الكل/لا شيء، تنبيه Outbox،
 * الرفع بتقدمه وإيقافه، ونتيجة الرفع بأخطائها وتحذيراتها.
 */
@Composable
fun CloudflareD1Tab(
    viewModel: CloudflareD1ViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showConfirmUpload by remember { mutableStateOf(false) }

    val d1Set = state.d1Tables?.toSet()
    val missingInD1 = state.missingInD1()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp)
    ) {
        // بطاقة الاتصال التلقائي — نظير CloudflareAutoConnectionCard
        item {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            ) {
                Row(
                    Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.CloudUpload, contentDescription = null)
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(
                            "اتصال Worker السحابي",
                            fontWeight = FontWeight.Bold,
                            fontSize = 14.sp
                        )
                        Text(
                            "اعتمادات مزامنة Cloudflare محفوظة على هذا الجهاز — " +
                                "الرفع المباشر أدناه يحتاج توكن D1 مستقلاً",
                            fontSize = 12.sp
                        )
                    }
                }
            }
        }
        item {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                ),
                modifier = Modifier.padding(top = 8.dp)
            ) {
                Row(
                    Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.Dns, contentDescription = null)
                    Spacer(Modifier.width(12.dp))
                    Text(
                        "رفع البيانات إلى Cloudflare D1",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
        item {
            Text(
                "ينقل هذا التبويب بيانات جداول المزامنة (كيانات مزامنة " +
                    "Cloudflare حصراً) إلى قاعدة Cloudflare D1 كنسخة استشارية على " +
                    "السحابة. " +
                    "القراءة من القاعدة المحلية فقط، والكتابة بأسلوب INSERT OR " +
                    "REPLACE الآمن. القائمة السوداء blacklist كيان بلا جدول " +
                    "محلي فتُجسَّد من ملاحظات الورديات الموسومة إلى جدولها في " +
                    "D1، أما hotel_day_ledger (محلي-فقط) وجداول البنية المحلية " +
                    "(outbox، sync_remote_meta، sync_state، sync_log، …) " +
                    "فتُستبعد كلياً.",
                fontSize = 13.sp,
                modifier = Modifier.padding(top = 8.dp)
            )
        }
        if (state.outboxPending > 0) {
            item {
                Text(
                    "تنبيه استشاري: توجد ${state.outboxPending} عملية في Outbox غير مُسلّمة — " +
                        "يمكنك المتابعة لكن يُفضّل تفريغ الرفع الاعتيادي أولاً.",
                    color = Color(0xFFEF6C00),
                    fontSize = 13.sp,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }

        // ── الإعدادات ──
        item {
            Card(Modifier.padding(top = 16.dp)) {
                Column(Modifier.padding(16.dp)) {
                    Text("إعدادات الاتصال", style = MaterialTheme.typography.titleSmall)
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = state.accountId,
                        onValueChange = { v ->
                            viewModel.updateConnection(v, state.databaseId, state.apiToken, state.deviceLabel)
                        },
                        label = { Text("Account ID") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(10.dp))
                    OutlinedTextField(
                        value = state.databaseId,
                        onValueChange = { v ->
                            viewModel.updateConnection(state.accountId, v, state.apiToken, state.deviceLabel)
                        },
                        label = { Text("Database ID (uuid)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(10.dp))
                    OutlinedTextField(
                        value = state.apiToken,
                        onValueChange = { v ->
                            viewModel.updateConnection(state.accountId, state.databaseId, v, state.deviceLabel)
                        },
                        label = { Text("API Token (صلاحية D1 Edit يُنصح بها)") },
                        singleLine = true,
                        visualTransformation = if (state.obscureToken)
                            PasswordVisualTransformation() else VisualTransformation.None,
                        trailingIcon = {
                            androidx.compose.material3.IconButton(
                                onClick = { viewModel.toggleObscureToken() }
                            ) {
                                Icon(
                                    if (state.obscureToken) Icons.Filled.VisibilityOff
                                    else Icons.Filled.Visibility,
                                    contentDescription = null
                                )
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(10.dp))
                    OutlinedTextField(
                        value = state.deviceLabel,
                        onValueChange = { v ->
                            viewModel.updateConnection(state.accountId, state.databaseId, state.apiToken, v)
                        },
                        label = { Text("وسم الجهاز (اختياري — يُسجل مع النسخة)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp)) {
                        OutlinedButton(
                            onClick = { viewModel.save() },
                            enabled = !(state.probing || state.uploading || state.loadingSettings)
                        ) {
                            Icon(Icons.Filled.Save, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("حفظ")
                        }
                        Button(
                            onClick = { viewModel.probe() },
                            enabled = !(state.probing || state.uploading || state.loadingSettings)
                        ) {
                            if (state.probing) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp
                                )
                            } else {
                                Icon(Icons.Filled.WifiTethering, contentDescription = null, modifier = Modifier.size(18.dp))
                            }
                            Spacer(Modifier.width(6.dp))
                            Text("فحص الاتصال والصلاحيات")
                        }
                    }
                }
            }
        }

        // ── نتيجة الفحص ──
        state.probeResult?.let { probe ->
            item {
                Card(Modifier.padding(top = 12.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        ProbeRow(probe.tokenValid, "التوكن صالح وفعّال", "التوكن غير صالح")
                        ProbeRow(
                            probe.databaseReachable,
                            "القاعدة متاحة: ${probe.databaseName ?: state.databaseId}",
                            "القاعدة غير موجودة في الحساب"
                        )
                        ProbeRow(
                            probe.dmlAllowed,
                            "صلاحية الكتابة (DML) متاحة — الرفع ممكن",
                            "صلاحية الكتابة (DML) محجوبة",
                            detail = probe.dmlError
                        )
                        ProbeRow(
                            probe.ddlAllowed,
                            "صلاحية إنشاء الجداول (DDL) متاحة",
                            "إنشاء الجداول (DDL) محجوب — لا يمنع الرفع؛ المخطط موجود مسبقاً"
                        )
                        state.d1Tables?.let { tables ->
                            Text(
                                "جداول D1: ${tables.size} — " +
                                    "مغطاة محلياً: ${state.localTables.count { d1Set?.contains(it.name) == true }}",
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(top = 6.dp)
                            )
                        }
                    }
                }
            }
        }

        // ── الجداول المحلية ──
        item {
            Card(Modifier.padding(top = 16.dp)) {
                Column(Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "جداول المزامنة السحابية " +
                                "(${state.selected.size}/${state.localTables.size} محددة — " +
                                "${state.selectedRows} صف)",
                            style = MaterialTheme.typography.titleSmall,
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(
                            onClick = { viewModel.selectAll() },
                            enabled = state.localTables.isNotEmpty()
                        ) { Text("الكل") }
                        TextButton(
                            onClick = { viewModel.selectNone() },
                            enabled = state.localTables.isNotEmpty()
                        ) { Text("لا شيء") }
                    }
                    if (missingInD1.isNotEmpty()) {
                        Text(
                            "تنبيه: ${missingInD1.size} جدولاً محدداً غير موجود في D1 " +
                                "(ستفشل): ${missingInD1.take(5).joinToString("، ")}",
                            color = Color(0xFFEF6C00),
                            fontSize = 13.sp,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                    }
                    if (state.loadingTables) {
                        Box(Modifier.fillMaxWidth().padding(20.dp)) {
                            CircularProgressIndicator(Modifier.align(Alignment.Center))
                        }
                    } else {
                        Column {
                            state.localTables.forEach { t ->
                                val existsInD1 = d1Set == null || d1Set.contains(t.name)
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Checkbox(
                                        checked = state.selected.contains(t.name),
                                        onCheckedChange = { checked ->
                                            viewModel.toggleTable(t.name)
                                        },
                                        enabled = !state.uploading
                                    )
                                    Text(t.name, modifier = Modifier.weight(1f), fontSize = 14.sp)
                                    Text(
                                        "${t.rowCount} صف" +
                                            if (existsInD1) "" else " — غير موجود في D1",
                                        fontSize = 12.sp,
                                        color = if (existsInD1) BackupUi.grey600 else Color(0xFFEF6C00)
                                    )
                                }
                            }
                        }
                    }
                    TextButton(
                        onClick = { viewModel.loadLocalTables() },
                        enabled = !(state.loadingTables || state.uploading)
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("تحديث قائمة الجداول والأعداد")
                    }
                }
            }
        }

        // ── الرفع ──
        if (state.uploading) {
            item {
                Column(Modifier.padding(top = 16.dp)) {
                    LinearProgressIndicator(
                        progress = { state.progress.toFloat() },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(10.dp))
                    Text(state.stage, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                    Spacer(Modifier.height(12.dp))
                }
            }
        }
        item {
            Row {
                Button(
                    onClick = { showConfirmUpload = true },
                    enabled = !(state.uploading || state.localTables.isEmpty() ||
                        !(state.probeResult?.dmlAllowed ?: false)),
                    modifier = Modifier.weight(1f)
                ) {
                    if (state.uploading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                    } else {
                        Icon(Icons.Filled.CloudUpload, contentDescription = null)
                    }
                    Spacer(Modifier.width(8.dp))
                    Text(if (state.uploading) "جاري الرفع..." else "رفع البيانات المحددة الآن")
                }
                if (state.uploading) {
                    Spacer(Modifier.width(10.dp))
                    OutlinedButton(onClick = { viewModel.cancelUpload() }) {
                        Icon(Icons.Filled.Stop, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text("إيقاف")
                    }
                }
            }
        }
        if (state.probeResult != null && !(state.probeResult?.dmlAllowed ?: false)) {
            item {
                Text(
                    "لا يمكن الرفع: صلاحية الكتابة غير متاحة بالتوكن الحالي.",
                    color = MaterialTheme.colorScheme.error,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }

        // ── نتيجة الرفع ──
        state.result?.let { result ->
            item {
                Card(
                    Modifier.padding(top = 16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = if (result.ok) Color(0xFFE8F5E9) else Color(0xFFFFEBEE)
                    )
                ) {
                    Column(Modifier.padding(12.dp)) {
                        Text(
                            when {
                                result.cancelled -> "أُوقف الرفع جزئياً"
                                result.ok -> "اكتمل الرفع بنجاح"
                                else -> "اكتمل مع أخطاء"
                            },
                            style = MaterialTheme.typography.titleSmall
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "جداول: ${result.tablesDone} — صفوف: ${result.rowsUploaded} — " +
                                "نداءات: ${result.apiCalls} — " +
                                "الزمن: ${result.elapsedMs / 1000}ث",
                            fontSize = 13.sp
                        )
                        result.warnings.take(3).forEach { w ->
                            Text(w, color = Color(0xFFEF6C00), fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
                        }
                        result.errors.take(5).forEach { e ->
                            Text(
                                e,
                                color = MaterialTheme.colorScheme.error,
                                fontSize = 12.sp,
                                modifier = Modifier.padding(top = 4.dp)
                            )
                        }
                    }
                }
            }
        }

        // ── سجل الأخطاء ──
        if (state.logs.isNotEmpty()) {
            item {
                Card(Modifier.padding(top = 8.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        state.logs.forEach { line ->
                            Text(
                                line,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(vertical = 2.dp)
                            )
                        }
                    }
                }
            }
        }

        item { Spacer(Modifier.height(24.dp)) }
    }

    // حوار التأكيد — نفس نصوص Dart
    if (showConfirmUpload) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showConfirmUpload = false },
            title = { Text("تأكيد الرفع إلى Cloudflare D1") },
            text = {
                Text(
                    "سيتم رفع ${state.selected.size} جدولاً (${state.selectedRows} صفاً) إلى قاعدة " +
                        "D1 المحددة باستخدام INSERT OR REPLACE.\n\n" +
                        "• لا يُحذف أي سجل موجود في D1 غير موجود محلياً.\n" +
                        "• إعادة الرفع آمنة (نفس البيانات تستبدل نفسها).\n" +
                        "• يُنصح بعدد صفوف كبير بألا تكون هناك عمليات كتابة كثيرة أثناء الرفع."
                )
            },
            dismissButton = {
                TextButton(onClick = { showConfirmUpload = false }) { Text("إلغاء") }
            },
            confirmButton = {
                Button(onClick = {
                    showConfirmUpload = false
                    viewModel.startUpload()
                }) { Text("رفع الآن") }
            }
        )
    }
}

/** صف نتيجة فحص — نظير _probeRow بنفس النصوص والألوان. */
@Composable
private fun ProbeRow(ok: Boolean, okText: String, failText: String, detail: String? = null) {
    Row(
        Modifier.padding(vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            if (ok) Icons.Filled.CheckCircle else Icons.Filled.Cancel,
            contentDescription = null,
            tint = if (ok) Color(0xFF4CAF50) else Color(0xFFF44336),
            modifier = Modifier.size(18.dp)
        )
        Spacer(Modifier.width(8.dp))
        Column {
            Text(if (ok) okText else failText, fontSize = 14.sp)
            if (!ok && !detail.isNullOrEmpty()) {
                Text(
                    detail,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}
