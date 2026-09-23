package com.marina.marina.presentation.settings

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.util.PdfExporter

/**
 * الإعدادات — 1:1 port of `settings_screen.dart`:
 * quick-stats card, four collapsible sections (إدارة البيانات / المزامنة
 * والنسخ الاحتياطي / الإشعارات والتقارير / التطبيق والخدمات), night-audit
 * dialog (إقفال اليوم), app-settings dialog and about dialog.
 */
@Composable
fun SettingsScreen(
    onNavigate: (String) -> Unit = {},
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var expandedSections by remember { mutableStateOf(setOf("data")) }
    var showNightAudit by remember { mutableStateOf(false) }
    var showAppSettings by remember { mutableStateOf(false) }
    var showAbout by remember { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.consumeMessage()
        }
    }

    fun toggleSection(key: String) {
        expandedSections = if (key in expandedSections) expandedSections - key else expandedSections + key
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("الإعدادات", style = AppTypography.titleLarge) },
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
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Quick stats card (Dart l.442-519).
                Card(
                    colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                    shape = RoundedCornerShape(12.dp),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("📊", fontSize = 16.sp)
                            Text("إحصائيات سريعة", fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            QuickStat("الغرف", "${state.roomsCount}", AppColors.PrimaryColor, Modifier.weight(1f))
                            QuickStat("النشطة", "${state.activeBookings}", AppColors.SuccessColor, Modifier.weight(1f))
                            QuickStat("الموظفين", "${state.employeesCount}", AppColors.WarningColor, Modifier.weight(1f))
                            QuickStat("المستخدمين", "${state.usersCount}", Color(0xFF7B1FA2), Modifier.weight(1f))
                        }
                    }
                }

                // Section 1 — إدارة البيانات (expanded by default).
                SettingsSection(
                    title = "إدارة البيانات", icon = "🗂️",
                    subtitle = "الموظفون · الضيوف · القوائم · الصيانة · المخزون",
                    expanded = "data" in expandedSections,
                    onToggle = { toggleSection("data") }
                ) {
                    SettingsItem("إدارة الموظفين", "إضافة وتعديل بيانات الموظفين", "👥", AppColors.PrimaryColor) { onNavigate("employees") }
                    SettingsItem("إدارة الضيوف", "عرض تاريخ وإحصائيات الضيوف", "👤", AppColors.SuccessColor) { onNavigate("information") }
                    SettingsItem("القائمة السوداء", "إضافة/إدارة الأشخاص المطلوبين", "⚖️", AppColors.DangerColor) { onNavigate("blacklist") }
                    SettingsItem("المخزون", "الأصناف والرصيد والوارد والصرف والجرد", "📦", Color(0xFF795548)) { onNavigate("inventory") }
                    SettingsItem("الاستحقاقات", "استحقاقات الرواتب للموظفين", "💵", Color(0xFF3F51B5)) { onNavigate("salary_entitlements") }
                }

                // Section 2 — المزامنة والنسخ الاحتياطي.
                SettingsSection(
                    title = "المزامنة والنسخ الاحتياطي", icon = "🔄",
                    subtitle = "Cloudflare · حالة المزامنة · النسخ المحلي",
                    expanded = "sync" in expandedSections,
                    onToggle = { toggleSection("sync") }
                ) {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = AppColors.PrimaryLight),
                        shape = RoundedCornerShape(10.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text("المزامنة السحابية (Cloudflare)", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                Text(
                                    if (state.pendingOutbox > 0) "معلّق: ${state.pendingOutbox}" else "متزامن",
                                    fontSize = 11.sp,
                                    color = if (state.pendingOutbox > 0) AppColors.WarningColor else AppColors.SuccessColor
                                )
                            }
                            Text("آخر مزامنة: ${state.lastSyncText}", fontSize = 11.sp, color = AppColors.TextSecondary)
                            Button(
                                onClick = { viewModel.syncNow() },
                                enabled = !state.isSyncing,
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(10.dp)
                            ) {
                                if (state.isSyncing) {
                                    CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                                } else {
                                    Text("مزامنة الآن", fontSize = 12.sp)
                                }
                            }
                        }
                    }
                    // ✅ (2026-09-24) مدخل إعدادات الاتصال بـ Cloudflare —
                    // اعتمادات المزامنة + نطاق worker مخصّص + توكن D1 المباشر.
                    SettingsItem(
                        "إعدادات Cloudflare",
                        "اعتمادات المزامنة · نطاق مخصّص · توكن D1",
                        "☁️",
                        Color(0xFFF6820C)
                    ) { onNavigate("cloudflare_login") }
                }

                // Section 3 — الإشعارات والتقارير.
                SettingsSection(
                    title = "الإشعارات والتقارير", icon = "🔔",
                    subtitle = "إقفال اليوم · تذكيرات واتساب",
                    expanded = "notifications" in expandedSections,
                    onToggle = { toggleSection("notifications") }
                ) {
                    SettingsItem("إقفال اليوم", "تقرير يومي عبر WhatsApp و Telegram", "🌙", Color(0xFF3F51B5)) { showNightAudit = true }
                    SettingsItem("تذكير المتبقي", "تذكير واتساب بالمتأخر للحجوزات النشطة", "💳", AppColors.PrimaryColor) { onNavigate("bookings_reminder") }
                }

                // Section 4 — التطبيق والخدمات.
                SettingsSection(
                    title = "التطبيق والخدمات", icon = "📱",
                    subtitle = "المظهر · المساعد الذكي · معلومات التطبيق",
                    expanded = "app" in expandedSections,
                    onToggle = { toggleSection("app") }
                ) {
                    SettingsItem("المظهر", "الألوان والوضع", "🎨", Color(0xFF7B1FA2)) { showAppSettings = true }
                    SettingsItem("المساعد الذكي", "Gemini AI - تحكم ذكي بالبيانات", "🤖", Color(0xFFF57C00)) { onNavigate("ai_chat") }
                    SettingsItem("معلومات التطبيق", "الإصدار ومعلومات المطور", "ℹ️", AppColors.TextSecondary) { showAbout = true }
                }

                // Hotel day card.
                Card(
                    colors = CardDefaults.cardColors(containerColor = AppColors.AccentSoft),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("اليوم الفندقي الحالي", fontSize = 11.sp, color = AppColors.TextSecondary)
                        Text(
                            HotelTimeEngine.currentHotelDayKey(),
                            fontWeight = FontWeight.Bold, fontSize = 16.sp, color = AppColors.WarningColor
                        )
                        Text("حد اليوم الفندقي: 14:01", fontSize = 10.sp, color = AppColors.TextSecondary)
                    }
                }
            }
        }
    }

    // Night audit dialog (Dart _performNightAudit l.617-713).
    if (showNightAudit) {
        AlertDialog(
            onDismissRequest = { showNightAudit = false },
            title = { Text("إقفال اليوم") },
            text = {
                Text(
                    "سيتم تجميع كل بيانات اليوم المالية وإقفال اليوم الفندقي وإرسال التقرير عبر WhatsApp و Telegram.\n\nهل تريد المتابعة؟"
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showNightAudit = false
                    // Build the day-close report text and share via WhatsApp.
                    val hotelDay = HotelTimeEngine.currentHotelDayKey()
                    val report = buildString {
                        append("تقرير إقفال اليوم - MARINA HOTEL\n")
                        append("━━━━━━━━━━━\n")
                        append("اليوم الفندقي: $hotelDay\n")
                        append("━━━━━━━━━━━\n")
                        append("مارينا هوتل | 9677734587456")
                    }
                    PdfExporter.openWhatsAppText(context, "9677734587456", report)
                }) { Text("إقفال وإرسال", color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { showNightAudit = false }) { Text("إلغاء") }
            }
        )
    }

    // App settings dialog (Dart l.715-748).
    if (showAppSettings) {
        AlertDialog(
            onDismissRequest = { showAppSettings = false },
            title = { Text("إعدادات التطبيق") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("المظهر: كحلي مارينا مع ذهبي", fontSize = 13.sp)
                    Text("اللغة: العربية (RTL)", fontSize = 13.sp)
                    Text("حد اليوم الفندقي: 14:01", fontSize = 13.sp)
                }
            },
            confirmButton = {
                TextButton(onClick = { showAppSettings = false }) { Text("حسناً") }
            }
        )
    }

    // About dialog (Dart l.751-768).
    if (showAbout) {
        AlertDialog(
            onDismissRequest = { showAbout = false },
            title = { Text("تطبيق إدارة فندق مارينا") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("الإصدار: 1.5.0", fontSize = 13.sp)
                    Text("تطبيق شامل لإدارة العمليات الفندقية", fontSize = 12.sp, color = AppColors.TextSecondary)
                    Text("تصميم Eng: Nassar Alshabi", fontSize = 12.sp, color = AppColors.TextSecondary)
                    Text("Phone: +967 734587456", fontSize = 12.sp, color = AppColors.TextSecondary)
                    Text("© 2026 Marina Hotel", fontSize = 11.sp, color = AppColors.TextSecondary)
                }
            },
            confirmButton = {
                TextButton(onClick = { showAbout = false }) { Text("إغلاق") }
            }
        )
    }
}

// ---------------------------------------------------------------------------

@Composable
private fun QuickStat(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.background(color.copy(alpha = 0.1f), RoundedCornerShape(10.dp)).padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 15.sp)
        Text(label, fontSize = 9.sp, color = AppColors.TextSecondary)
    }
}

@Composable
private fun SettingsSection(
    title: String,
    icon: String,
    subtitle: String,
    expanded: Boolean,
    onToggle: () -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        shape = RoundedCornerShape(12.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth().clickable(onClick = onToggle),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(icon, fontSize = 18.sp)
                    Column {
                        Text(title, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor, fontSize = 15.sp)
                        if (!expanded) Text(subtitle, fontSize = 10.sp, color = AppColors.TextSecondary, maxLines = 1)
                    }
                }
                Text(if (expanded) "▲" else "▼", color = AppColors.TextSecondary, fontSize = 12.sp)
            }
            AnimatedVisibility(visible = expanded) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp), content = content)
            }
        }
    }
}

@Composable
private fun SettingsItem(
    title: String,
    subtitle: String,
    icon: String,
    color: Color,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(color.copy(alpha = 0.07f), RoundedCornerShape(10.dp))
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(icon, fontSize = 18.sp)
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
            Text(subtitle, fontSize = 10.sp, color = AppColors.TextSecondary, maxLines = 2)
        }
        Text("‹", color = AppColors.TextSecondary, fontSize = 16.sp)
    }
}
