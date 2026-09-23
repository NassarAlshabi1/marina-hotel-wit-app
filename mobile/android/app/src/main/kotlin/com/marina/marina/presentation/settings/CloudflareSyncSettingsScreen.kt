package com.marina.marina.presentation.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.BatterySaver
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.FlashOn
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Login
import androidx.compose.material.icons.filled.ManageAccounts
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material.icons.filled.PendingActions
import androidx.compose.material.icons.filled.PersonOutline
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.ui.theme.AppColors

/**
 * ✅ (2026-09-24) شاشة «إعدادات المزامنة» — نقل 1:1 لـ
 * unified_sync_settings_screen.dart (فرع feat/cloudflare-sync-execution):
 *
 *  1. نظرة عامة — حالة المزامنة (آخر مزامنة · الاتصال · المعلّق).
 *  2. تسجيل الدخول إلى Cloudflare — الحالة + «إدارة تسجيل الدخول».
 *  3. الإعدادات العامة — مزامنة تلقائية · عند البدء · فترة المزامنة.
 *  4. خيارات متقدمة — الأداء والبطارية · المزامنة الذكية · نطاق Worker
 *     مخصّص (فحص ping بمهلة 8s + حفظ + مسح).
 *  5. Cloudflare Sync — التفعيل + المزامنة الفورية (Realtime).
 *  6. أدوات المزامنة اليدوية — سحب دلتا · سحب كامل (بتأكيد) · رفع محلي.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloudflareSyncSettingsScreen(
    onBack: () -> Unit = {},
    onOpenCloudflareLogin: () -> Unit = {},
    viewModel: CloudflareSyncSettingsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showIntervalDialog by remember { mutableStateOf(false) }
    var showFullPullConfirm by remember { mutableStateOf(false) }

    // سناك-بار النتائج — ألوان النجاح/الفشل نفس SnackBar في Dart.
    LaunchedEffect(state.snackbar) {
        val message = state.snackbar ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(
            message = message.text,
            duration = SnackbarDuration.Short,
            withDismissAction = true
        )
        viewModel.consumeSnackbar()
    }

    Scaffold(
        containerColor = AppColors.BackgroundColor,
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("إعدادات المزامنة", style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "رجوع")
                    }
                },
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
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // ─── 1) نظرة عامة ────────────────────────────────────
            SectionCard {
                SectionHeader(icon = Icons.Default.Info, title = "حالة المزامنة", tint = SyncColor)
                InfoRow(
                    label = "آخر مزامنة",
                    value = state.lastSyncText,
                    icon = Icons.Default.Schedule
                )
                InfoRow(
                    label = "حالة الاتصال",
                    value = when (state.isConnected) {
                        true -> "متصل بالسحابة"
                        false -> "غير متصل"
                        null -> "جارٍ الفحص…"
                    },
                    icon = Icons.Default.Wifi,
                    iconColor = if (state.isConnected == true) SuccessGreen else ErrorRed
                )
                InfoRow(
                    label = "عناصر معلقة",
                    value = "${state.pendingCount}",
                    icon = Icons.Default.PendingActions,
                    iconColor = if (state.pendingCount > 0) WarningOrange else SuccessGreen
                )
            }

            // ─── 2) تسجيل الدخول إلى Cloudflare ──────────────────
            SectionCard {
                SectionHeader(icon = Icons.Default.Login, title = "تسجيل الدخول إلى Cloudflare", tint = SyncColor)
                InfoRow(
                    label = "حالة الحساب",
                    value = if (state.loggedIn) "مسجَّل الدخول" else "غير مسجَّل",
                    icon = if (state.loggedIn) Icons.Default.CheckCircle else Icons.Default.ErrorOutline,
                    iconColor = if (state.loggedIn) SuccessGreen else ErrorRed
                )
                InfoRow(
                    label = "اسم المستخدم",
                    value = state.username,
                    icon = Icons.Default.PersonOutline
                )
                state.lastError?.let { error ->
                    InfoRow(
                        label = "آخر خطأ",
                        value = error,
                        icon = Icons.Default.WarningAmber,
                        iconColor = WarningOrange
                    )
                }
                Spacer(Modifier.height(4.dp))
                Button(
                    onClick = onOpenCloudflareLogin,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = SyncColor,
                        contentColor = Color.White
                    )
                ) {
                    Icon(Icons.Default.ManageAccounts, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("إدارة تسجيل الدخول", fontSize = 13.sp)
                }
            }

            // ─── 3) الإعدادات العامة ─────────────────────────────
            SectionCard {
                SettingsSwitchRow(
                    icon = Icons.Default.Sync,
                    title = "تفعيل المزامنة التلقائية",
                    subtitle = "مزامنة البيانات تلقائياً عند التغيير",
                    checked = state.autoSyncEnabled,
                    enabled = !state.isSaving,
                    onCheckedChange = viewModel::setAutoSyncEnabled
                )
                CardDivider()
                SettingsSwitchRow(
                    icon = Icons.Default.PowerSettingsNew,
                    title = "المزامنة عند بدء التشغيل",
                    subtitle = "مزامنة البيانات عند فتح التطبيق",
                    checked = state.syncOnStartup,
                    enabled = !state.isSaving,
                    onCheckedChange = viewModel::setSyncOnStartup
                )
                CardDivider()
                // فترة المزامنة → حوار اختيار (5/15/30/60) — نفس Dart.
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(enabled = !state.isSaving) { showIntervalDialog = true }
                        .padding(horizontal = 12.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(Icons.Default.Timer, contentDescription = null, tint = AppColors.PrimaryColor, modifier = Modifier.size(22.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("فترة المزامنة", fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        Text(
                            "كل ${state.syncIntervalMinutes} دقيقة",
                            fontSize = 11.sp,
                            color = AppColors.TextSecondary
                        )
                    }
                    Text("‹", color = AppColors.TextSecondary, fontSize = 16.sp)
                }
            }

            // ─── 4) خيارات متقدمة (ظاهرة دائماً — قرار Dart 2026-09-17) ──
            SectionHeaderRow(
                title = "خيارات متقدمة",
                subtitle = "الأداء والبطارية · المزامنة الذكية · نطاق Worker"
            )

            // 4-أ) الأداء والبطارية
            SectionCard {
                SectionHeader(icon = Icons.Default.Speed, title = "الأداء والبطارية", tint = SyncColor)
                CardDivider()
                SettingsSwitchRow(
                    icon = Icons.Default.BatterySaver,
                    title = "تحسين البطارية",
                    subtitle = "تقليل استهلاك البطارية أثناء المزامنة",
                    checked = state.batteryOptimization,
                    enabled = !state.isSaving,
                    onCheckedChange = viewModel::setBatteryOptimization
                )
                CardDivider()
                SettingsSwitchRow(
                    icon = Icons.Default.Wifi,
                    title = "WiFi فقط",
                    subtitle = "مزامنة عند الاتصال بـ WiFi فقط",
                    checked = state.wifiOnly,
                    enabled = !state.isSaving,
                    onCheckedChange = viewModel::setWifiOnly
                )
            }

            // 4-ب) المزامنة الذكية
            SectionCard {
                SectionHeader(icon = Icons.Default.Psychology, title = "المزامنة الذكية", tint = Color(0xFF9C27B0))
                CardDivider()
                SettingsSwitchRow(
                    icon = Icons.Default.SmartToy,
                    title = "تفعيل المزامنة الذكية",
                    subtitle = "مزامنة تكيفية حسب الاستخدام والظروف",
                    checked = state.smartSyncEnabled,
                    enabled = !state.isSaving,
                    onCheckedChange = viewModel::setSmartSyncEnabled
                )
            }

            // 4-ج) نطاق Worker مخصّص (تجاوز الحجب)
            SectionCard {
                SectionHeader(icon = Icons.Default.Dns, title = "نطاق Worker مخصّص (تجاوز الحجب)", tint = SyncColor)
                Text(
                    "إذا كان اتصال المزامنة محبوساً (workers.dev محجوب في بعض " +
                        "الشبكات مثل اليمن): ربط دومينك بحساب Cloudflare ووجّهه " +
                        "لنفس الـ Worker، ثم ضعه هنا — يعمل التطبيق عبره تلقائياً " +
                        "ويرجع للمدمج إن تعذّر.",
                    fontSize = 11.sp,
                    color = AppColors.TextSecondary
                )
                InfoRow(
                    label = "النقطة الفعّالة الآن",
                    value = state.activeHost,
                    icon = Icons.Default.Public,
                    valueEllipsis = true
                )
                OutlinedTextField(
                    value = state.customUrlField,
                    onValueChange = viewModel::onCustomUrlFieldChange,
                    label = { Text("النطاق المخصّص (اختياري)") },
                    placeholder = { Text("api.mydomain.com") },
                    singleLine = true,
                    isError = state.endpointProbeOk == false,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    modifier = Modifier.fillMaxWidth()
                )
                state.endpointProbeResult?.let { probe ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            if (state.endpointProbeOk == true) Icons.Default.CheckCircle else Icons.Default.ErrorOutline,
                            contentDescription = null,
                            tint = if (state.endpointProbeOk == true) SuccessGreen else ErrorRed,
                            modifier = Modifier.size(16.dp)
                        )
                        Text(
                            probe,
                            fontSize = 11.sp,
                            color = if (state.endpointProbeOk == true) SuccessGreen else ErrorRed,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = viewModel::probeCustomEndpoint,
                        enabled = !state.isProbingEndpoint,
                        modifier = Modifier.weight(1f)
                    ) {
                        if (state.isProbingEndpoint) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Default.NetworkCheck, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("فحص الاتصال", fontSize = 12.sp)
                        }
                    }
                    Button(
                        onClick = viewModel::saveCustomEndpoint,
                        enabled = !state.isProbingEndpoint,
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.Save, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("حفظ", fontSize = 12.sp)
                    }
                }
                if (state.hasCustomEndpoint) {
                    TextButton(
                        onClick = viewModel::clearCustomEndpoint,
                        modifier = Modifier.align(Alignment.End)
                    ) {
                        Icon(Icons.Default.DeleteOutline, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("مسح النطاق المخصّص", fontSize = 12.sp)
                    }
                }
            }

            // ─── 5) Cloudflare Sync ──────────────────────────────
            SectionCard {
                SectionHeader(icon = Icons.Default.CloudSync, title = "Cloudflare Sync", tint = Color(0xFF2196F3))
                CardDivider()
                SettingsSwitchRow(
                    icon = Icons.Default.Cloud,
                    title = "تفعيل مزامنة Cloudflare",
                    subtitle = "مزامنة البيانات مع سحابة Cloudflare",
                    checked = state.cloudflareSyncEnabled,
                    enabled = !state.isSaving,
                    onCheckedChange = viewModel::setCloudflareSyncEnabled
                )
                CardDivider()
                SettingsSwitchRow(
                    icon = Icons.Default.FlashOn,
                    title = "المزامنة الفورية (Realtime)",
                    subtitle = "استقبال تغييرات الأجهزة الأخرى فور حدوثها عبر WebSocket " +
                        "وسحبها خلال ثوانٍ — إن تعذر الاتصال يُستخدم سحب خفيف دوري",
                    checked = state.realtimeSyncEnabled,
                    enabled = !state.isSaving,
                    onCheckedChange = viewModel::setRealtimeSyncEnabled
                )
            }

            // ─── 6) أدوات المزامنة اليدوية ───────────────────────
            SectionCard {
                SectionHeader(icon = Icons.Default.TouchApp, title = "أدوات المزامنة اليدوية", tint = SyncColor)
                CardDivider()
                ManualActionRow(
                    icon = Icons.Default.CloudDownload,
                    iconTint = Color(0xFF2196F3),
                    title = "سحب التغييرات الآن",
                    subtitle = "يجلب التغييرات الجديدة من السيرفر فقط (بدون رفع)",
                    busy = state.isManualSyncing,
                    enabled = !state.isManualSyncing,
                    onClick = viewModel::runPullNow
                )
                CardDivider()
                ManualActionRow(
                    icon = Icons.Default.Restore,
                    iconTint = Color(0xFF673AB7),
                    title = "السحب الكامل من السيرفر",
                    subtitle = "سحب فقط بدون رفع: يعيد ضبط مؤشر السحب ويجلب كل البيانات " +
                        "من السيرفر من الصفر (صفحات أكبر وأسرع)",
                    busy = state.isManualSyncing,
                    enabled = !state.isManualSyncing,
                    onClick = { showFullPullConfirm = true }
                )
                CardDivider()
                ManualActionRow(
                    icon = Icons.Default.CloudUpload,
                    iconTint = Color(0xFF009688),
                    title = "رفع التغييرات المحلية",
                    subtitle = "رفع فقط بدون سحب: يرفع كل التغييرات المحلية المعلّقة " +
                        "في outbox إلى السيرفر",
                    busy = state.isManualSyncing,
                    enabled = !state.isManualSyncing,
                    onClick = viewModel::runPushNow
                )
            }
        }
    }

    // ─── حوار فترة المزامنة (نفس _showSyncIntervalDialog) ────────
    if (showIntervalDialog) {
        AlertDialog(
            onDismissRequest = { showIntervalDialog = false },
            title = { Text("فترة المزامنة") },
            text = {
                Column {
                    CloudflareSyncSettingsViewModel.SYNC_INTERVAL_OPTIONS.forEach { minutes ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    showIntervalDialog = false
                                    viewModel.selectSyncInterval(minutes)
                                }
                                .padding(vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(
                                selected = state.syncIntervalMinutes == minutes,
                                onClick = {
                                    showIntervalDialog = false
                                    viewModel.selectSyncInterval(minutes)
                                }
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                when (minutes) {
                                    5 -> "5 دقائق"
                                    15 -> "15 دقيقة"
                                    30 -> "30 دقيقة"
                                    60 -> "ساعة واحدة"
                                    else -> "$minutes دقيقة"
                                },
                                fontSize = 14.sp
                            )
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showIntervalDialog = false }) { Text("إلغاء") }
            }
        )
    }

    // ─── حوار تأكيد السحب الكامل (نفس _confirmFullSync) ──────────
    if (showFullPullConfirm) {
        AlertDialog(
            onDismissRequest = { showFullPullConfirm = false },
            title = { Text("السحب الكامل من السيرفر؟") },
            text = {
                Text(
                    "سحب فقط بدون رفع:\n" +
                        "1. إعادة ضبط مؤشر السحب\n" +
                        "2. جلب جميع البيانات من السيرفر من الصفر\n\n" +
                        "لا يُرفع أي تغيير محلي في هذه العملية. متابعة؟"
                )
            },
            confirmButton = {
                Button(onClick = {
                    showFullPullConfirm = false
                    viewModel.runFullPull()
                }) { Text("متابعة") }
            },
            dismissButton = {
                TextButton(onClick = { showFullPullConfirm = false }) { Text("إلغاء") }
            }
        )
    }
}

// ═══════════════ مكونات مشتركة (نظائر widgets Dart) ═══════════════

/** لون المزامنة — UIConstants.syncColor في Dart. */
private val SyncColor = Color(0xFF0288D1)
private val SuccessGreen = Color(0xFF2E7D5B)
private val ErrorRed = Color(0xFFE5484D)
private val WarningOrange = Color(0xFFF57C00)

/** بطاقة قسم قياسية — نظير Card elevation:2 radiusLG في Dart. */
@Composable
private fun SectionCard(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content
        )
    }
}

/** رأس قسم داخل بطاقة — نظير صف Icon+Text في دوال _build في Dart. */
@Composable
private fun SectionHeader(icon: ImageVector, title: String, tint: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp))
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold)
    }
}

/** رأس قسم خارجي — نظير SettingsSectionHeader في Dart. */
@Composable
private fun SectionHeaderRow(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
        Text(subtitle, fontSize = 11.sp, color = AppColors.TextSecondary)
    }
}

/** صف معلومة — نظير InfoRow في Dart: تسمية + قيمة + أيقونة ملوّنة. */
@Composable
private fun InfoRow(
    label: String,
    value: String,
    icon: ImageVector,
    iconColor: Color? = null,
    valueEllipsis: Boolean = false
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = iconColor ?: AppColors.TextSecondary,
            modifier = Modifier.size(18.dp)
        )
        Text(label, fontSize = 13.sp, color = AppColors.TextSecondary)
        Spacer(Modifier.weight(1f))
        Text(
            value,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            maxLines = if (valueEllipsis) 1 else 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
            modifier = Modifier.weight(2f)
        )
    }
}

/** صف مفتاح تبديل — نظير SwitchListTile في Dart. */
@Composable
private fun SettingsSwitchRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled) { onCheckedChange(!checked) }
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(icon, contentDescription = null, tint = AppColors.PrimaryColor, modifier = Modifier.size(22.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            Text(subtitle, fontSize = 11.sp, color = AppColors.TextSecondary)
        }
        Switch(checked = checked, enabled = enabled, onCheckedChange = onCheckedChange)
    }
}

/** صف أداة يدوية — نظير ListTile مع مؤشر تحميل في trailing (Dart). */
@Composable
private fun ManualActionRow(
    icon: ImageVector,
    iconTint: Color,
    title: String,
    subtitle: String,
    busy: Boolean,
    enabled: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled) { onClick() }
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(24.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            Text(subtitle, fontSize = 11.sp, color = AppColors.TextSecondary)
        }
        if (busy) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
        } else {
            Text("‹", color = AppColors.TextSecondary, fontSize = 16.sp)
        }
    }
}

@Composable
private fun CardDivider() {
    androidx.compose.material3.HorizontalDivider(color = AppColors.DividerColor, thickness = 1.dp)
}
