package com.marina.marina.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AdminPanelSettings
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Assignment
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Gavel
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.ManageAccounts
import androidx.compose.material.icons.filled.NightlightRound
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Payment
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.a.a.BuildConfig
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.ui.theme.ThemePrefs
import com.marina.marina.util.PdfExporter

/**
 * الإعدادات — نقل 1:1 لـ `settings_screen.dart` (فرع feat/cloudflare-sync-
 * execution، إلغاء الأقسام المخفية 2026-09-17):
 *  • بطاقة إحصائيات سريعة مُصغّرة (dashboard icon 18 + 4 عدادات بأيقونات).
 *  • أقسام مسطحة ظاهرة دائماً: SettingsSectionHeader (أيقونة 22 زرقاء +
 *    عنوان 16 bold + شارة عدّاد + سطر فرعي) فوق شبكة 3 أعمدة
 *    (بطاقة 130dp: أيقونة 20 + عنوان 12 bold + وصف 12 رمادي).
 *  • زر مزامنة في شريط العنوان (نظير SyncActionButton في AppScaffold).
 *  • حوارات: إقفال اليوم (عنوان بأيقونة قمر indigo) · إعدادات التطبيق
 *    (مفتاح الوضع الداكن) · معلومات التطبيق.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigate: (String) -> Unit = {},
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
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

    // ─── عناصر الأقسام — نفس نصوص وألوان وأيقونات Dart ───
    val dataItems = listOf(
        HubItem("إدارة الموظفين", "إضافة وتعديل بيانات الموظفين", Icons.Default.People, DartColors.blue, route = "employees"),
        HubItem("إدارة الضيوف", "عرض تاريخ وإحصائيات الضيوف", Icons.Default.Person, DartColors.green, route = "information"),
        HubItem("القائمة السوداء", "إضافة/إدارة الأشخاص المطلوبين", Icons.Default.Gavel, DartColors.red, route = "blacklist"),
        HubItem("المخزون", "الأصناف والرصيد والوارد والصرف والجرد", Icons.Default.Inventory2, DartColors.brown, route = "inventory"),
        HubItem("الاستحقاقات", "استحقاقات الرواتب للموظفين", Icons.Default.Payment, DartColors.indigo, route = "salary_entitlements")
    )
    val syncItems = listOf(
        HubItem(
            "المزامنة السحابية بين الأجهزة",
            "رفع وسحب البيانات عبر Cloudflare D1 — الإعدادات والأداء والشبكة",
            Icons.Default.CloudSync, DartColors.blue, route = "cloudflare_sync_settings"
        ),
        // نظير بطاقة النسخ الاحتياطي في settings_screen.dart (نفس النصوص).
        HubItem(
            "النسخ الاحتياطي والاستعادة",
            "نسخ محلية آمنة ومزامنة Cloudflare D1",
            Icons.Default.Backup, Color(0xFFFF5722), route = "backup"
        )
    )
    val whatsappItems = listOf(
        HubItem("إقفال اليوم", "تقرير يومي عبر WhatsApp و Telegram", Icons.Default.NightlightRound, DartColors.indigo, action = { showNightAudit = true }),
        HubItem("تذكير المتبقي", "تذكير واتساب بالمتأخر للحجوزات النشطة", Icons.Default.Payment, DartColors.blue, route = "bookings_reminder")
    )
    val appItems = listOf(
        HubItem("المظهر", "الوضع الليلي والألوان", Icons.Default.Palette, DartColors.purple, action = { showAppSettings = true }),
        HubItem("المساعد الذكي", "Gemini AI - تحكم ذكي بالبيانات", Icons.Default.SmartToy, DartColors.amber700, route = "ai_chat"),
        HubItem("معلومات التطبيق", "الإصدار ومعلومات المطور", Icons.Default.Info, DartColors.grey, action = { showAbout = true })
    )

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("الإعدادات", style = MaterialTheme.typography.titleLarge) },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    ),
                    actions = {
                        // نظير SyncActionButton في AppScaffold (Dart).
                        if (state.isSyncing) {
                            Box(modifier = Modifier.size(24.dp).padding(2.dp)) {
                                CircularProgressIndicator(modifier = Modifier.fillMaxSize(), strokeWidth = 2.dp)
                            }
                        } else {
                            IconButton(onClick = viewModel::syncNow) {
                                Icon(
                                    Icons.Default.Sync,
                                    contentDescription = "مزامنة مع Cloudflare",
                                    tint = if (state.isError) Color(0xFFFF5349) else AppColors.TextPrimary
                                )
                            }
                        }
                    }
                )
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                // ✅ بطاقة الإحصائيات السريعة (Dart _buildQuickStatsCard).
                QuickStatsCard(
                    rooms = state.roomsCount,
                    active = state.activeBookings,
                    employees = state.employeesCount,
                    users = state.usersCount,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
                )

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp)
                ) {
                    SectionHeader(title = "إدارة البيانات", icon = Icons.Default.ManageAccounts, count = dataItems.size)
                    SettingsGrid(dataItems) { item ->
                        item.route?.let(onNavigate) ?: item.action?.invoke()
                    }
                    Spacer(Modifier.height(20.dp))

                    SectionHeader(
                        title = "المزامنة والنسخ الاحتياطي",
                        icon = Icons.Default.Sync,
                        count = syncItems.size,
                        subtitle = "Cloudflare · حالة المزامنة · النسخ المحلي"
                    )
                    SettingsGrid(syncItems) { item ->
                        item.route?.let(onNavigate) ?: item.action?.invoke()
                    }
                    Spacer(Modifier.height(20.dp))

                    SectionHeader(
                        title = "الإشعارات والتقارير",
                        icon = Icons.Default.Notifications,
                        count = whatsappItems.size,
                        subtitle = "إقفال اليوم · WhatsApp · Telegram"
                    )
                    SettingsGrid(whatsappItems) { item ->
                        item.route?.let(onNavigate) ?: item.action?.invoke()
                    }
                    Spacer(Modifier.height(20.dp))

                    SectionHeader(
                        title = "التطبيق والخدمات",
                        icon = Icons.Default.Apps,
                        count = appItems.size,
                        subtitle = "المظهر · المساعد الذكي · الأخطاء · Remote Config"
                    )
                    SettingsGrid(appItems) { item ->
                        item.route?.let(onNavigate) ?: item.action?.invoke()
                    }
                }
            }
        }
    }

    // ─── حوار إقفال اليوم (Dart _performNightAudit — حوار التأكيد) ───
    if (showNightAudit) {
        AlertDialog(
            onDismissRequest = { showNightAudit = false },
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.NightlightRound, contentDescription = null, tint = DartColors.indigo)
                    Spacer(Modifier.width(8.dp))
                    Text("إقفال اليوم")
                }
            },
            text = {
                Text(
                    "سيتم تجميع كل بيانات اليوم المالية وإقفال اليوم الفندقي " +
                        "وإرسال التقرير عبر WhatsApp و Telegram.\n\n" +
                        "هل تريد المتابعة؟"
                )
            },
            confirmButton = {
                Button(onClick = {
                    showNightAudit = false
                    // بناء تقرير إقفال اليوم ومشاركته عبر WhatsApp.
                    val hotelDay = HotelTimeEngine.currentHotelDayKey()
                    val report = buildString {
                        append("تقرير إقفال اليوم - MARINA HOTEL\n")
                        append("━━━━━━━━━━━\n")
                        append("اليوم الفندقي: $hotelDay\n")
                        append("━━━━━━━━━━━\n")
                        append("مارينا هوتل | 9677734587456")
                    }
                    PdfExporter.openWhatsAppText(context, "9677734587456", report)
                }) { Text("إقفال وإرسال") }
            },
            dismissButton = {
                TextButton(onClick = { showNightAudit = false }) { Text("إلغاء") }
            }
        )
    }

    // ─── حوار إعدادات التطبيق (Dart _showAppSettingsDialog) ───
    if (showAppSettings) {
        val isDark by ThemePrefs.isDark.collectAsState()
        AlertDialog(
            onDismissRequest = { showAppSettings = false },
            title = { Text("إعدادات التطبيق") },
            text = {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.DarkMode, contentDescription = null)
                    Spacer(Modifier.width(12.dp))
                    Text("المظهر الداكن", fontSize = 15.sp, modifier = Modifier.weight(1f))
                    Switch(
                        checked = isDark,
                        onCheckedChange = { viewModel.setDarkMode(context, it) }
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { showAppSettings = false }) { Text("إغلاق") }
            }
        )
    }

    // ─── حوار معلومات التطبيق (Dart _showAboutDialog) ───
    if (showAbout) {
        AlertDialog(
            onDismissRequest = { showAbout = false },
            title = { Text("تطبيق إدارة فندق مارينا") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("الإصدار: ${BuildConfig.VERSION_NAME}", fontSize = 13.sp)
                    Text("تطبيق شامل لإدارة العمليات الفندقية", fontSize = 13.sp)
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

// ═══════════════ مكونات مطابقة لعناصر Dart ═══════════════

/** ألوان Dart المستخدمة في الشاشة (Colors.* الفعلية). */
private object DartColors {
    val blue = Color(0xFF2196F3)
    val green = Color(0xFF4CAF50)
    val orange = Color(0xFFFF9800)
    val purple = Color(0xFF9C27B0)
    val indigo = Color(0xFF3F51B5)
    val red = Color(0xFFF44336)
    val brown = Color(0xFF795548)
    val grey = Color(0xFF9E9E9E)
    val amber700 = Color(0xFFFFA000)
}

/** عنصر شبكة الإعدادات — نظير _SettingsItem في Dart. */
private data class HubItem(
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val color: Color,
    val route: String? = null,
    val action: (() -> Unit)? = null
)

/** بطاقة الإحصائيات المُصغّرة — نفس padding/أحجام الخطوط في Dart. */
@Composable
private fun QuickStatsCard(
    rooms: Int,
    active: Int,
    employees: Int,
    users: Int,
    modifier: Modifier = Modifier
) {
    Card(
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Dashboard, contentDescription = null, tint = AppColors.PrimaryColor, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("إحصائيات سريعة", fontSize = 14.sp, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.height(8.dp))
            Row(modifier = Modifier.fillMaxWidth()) {
                StatItem("الغرف", "$rooms", Icons.Default.Hotel, DartColors.blue, Modifier.weight(1f))
                StatItem("النشطة", "$active", Icons.Default.Assignment, DartColors.green, Modifier.weight(1f))
                StatItem("الموظفين", "$employees", Icons.Default.People, DartColors.orange, Modifier.weight(1f))
                StatItem("المستخدمين", "$users", Icons.Default.AdminPanelSettings, DartColors.purple, Modifier.weight(1f))
            }
        }
    }
}

/** عدّاد إحصائي — Icon 20 + value 16 bold ملون + title 10 رمادي (Dart). */
@Composable
private fun StatItem(title: String, value: String, icon: ImageVector, color: Color, modifier: Modifier = Modifier) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
        Spacer(Modifier.height(4.dp))
        Text(value, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = color)
        Text(title, fontSize = 10.sp, color = DartColors.grey, textAlign = TextAlign.Center)
    }
}

/**
 * رأس قسم ثابت — نظير SettingsSectionHeader: أيقونة 22 زرقاء + عنوان
 * 16 bold أزرق + شارة عدّاد (خلفية زرقاء 12%) + سطر فرعي اختياري.
 */
@Composable
private fun SectionHeader(title: String, icon: ImageVector, count: Int, subtitle: String? = null) {
    Column(modifier = Modifier.padding(bottom = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = DartColors.blue, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(8.dp))
            Text(
                title,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = DartColors.blue,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            Spacer(Modifier.width(6.dp))
            Box(
                modifier = Modifier
                    .background(DartColors.blue.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
                    .padding(horizontal = 8.dp, vertical = 2.dp)
            ) {
                Text("$count", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DartColors.blue)
            }
        }
        if (subtitle != null) {
            Spacer(Modifier.height(2.dp))
            Text(
                subtitle,
                fontSize = 12.sp,
                color = AppColors.TextSecondary.copy(alpha = 0.7f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** شبكة 3 أعمدة — نظير _buildSettingsGrid: بطاقات 130dp ارتفاعاً. */
@Composable
private fun SettingsGrid(items: List<HubItem>, onClick: (HubItem) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        items.chunked(3).forEach { rowItems ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                rowItems.forEach { item ->
                    GridCard(item, onClick, Modifier.weight(1f))
                }
                // تعبئة الصف غير المكتمل للحفاظ على عرض الأعمدة.
                repeat(3 - rowItems.size) { Spacer(modifier = Modifier.weight(1f)) }
            }
        }
    }
}

/** بطاقة عنصر — Card elevation 1 + padding 10 + عمود متمركز (Dart). */
@Composable
private fun GridCard(item: HubItem, onClick: (HubItem) -> Unit, modifier: Modifier = Modifier) {
    Card(
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        modifier = modifier
            .height(130.dp)
            .clickable { onClick(item) }
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(item.icon, contentDescription = null, tint = item.color, modifier = Modifier.size(20.dp))
            Spacer(Modifier.height(8.dp))
            Text(
                item.title,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(4.dp))
            Text(
                item.subtitle,
                fontSize = 12.sp,
                color = DartColors.grey,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}
