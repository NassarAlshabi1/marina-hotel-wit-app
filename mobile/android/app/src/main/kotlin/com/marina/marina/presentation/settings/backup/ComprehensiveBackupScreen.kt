package com.marina.marina.presentation.settings.backup

import androidx.compose.foundation.background
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.HelpOutline
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import com.marina.marina.presentation.common.AppSnackbar
import com.marina.marina.presentation.common.showAppSnackbar
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import kotlinx.coroutines.launch

/**
 * الشاشة الرئيسية للنسخ الاحتياطي — نقل ComprehensiveBackupScreen
 * (comprehensive_backup_screen_v2.dart) 1:1: تبويبان (Cloudflare D1 /
 * النسخ المحلية) + حوار «مساعدة» بنفس النص، بعد إزالة تبويبات النظرة
 * العامة والإدارة الوهمية (قرار Dart 2026-09-05).
 */
object BackupUi {
    /** نظير UIConstants.backupColor = Color(0xFF4CAF50). */
    val backupColor = Color(0xFF4CAF50)
    val grey100 = Color(0xFFF5F5F5)
    val grey400 = Color(0xFFBDBDBD)
    val grey500 = Color(0xFF9E9E9E)
    val grey600 = Color(0xFF757575)
    val grey700 = Color(0xFF616161)
    const val spacingSM = 8
    const val spacingMD = 16
    const val spacingLG = 24
    const val radiusMD = 8
    const val radiusLG = 12
    const val iconSizeMD = 24
}

@Composable
fun ComprehensiveBackupScreen(
    onBack: () -> Unit = {},
    backupViewModel: BackupViewModel = hiltViewModel(),
    d1ViewModel: CloudflareD1ViewModel = hiltViewModel()
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    var showHelp by remember { mutableStateOf(false) }
    val backupState by backupViewModel.state.collectAsState()
    val d1State by d1ViewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    // سناك-بارات النسخ المحلي (ألوان Dart الصريحة)
    LaunchedEffect(Unit) {
        backupViewModel.snackbars.collect { event ->
            snackbarHostState.showAppSnackbar(
                AppSnackbar(
                    event.text,
                    event.containerColorArgb?.let { Color(it) }
                )
            )
        }
    }
    LaunchedEffect(Unit) {
        d1ViewModel.snackbars.collect { msg ->
            snackbarHostState.showAppSnackbar(AppSnackbar(msg))
        }
    }

    Scaffold(
        containerColor = AppColors.BackgroundColor,
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("النسخ الاحتياطي", style = AppTypography.titleLarge) },
                navigationIcon = {
                    TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                },
                actions = {
                    IconButton(onClick = { showHelp = true }) {
                        Icon(Icons.Filled.HelpOutline, contentDescription = "مساعدة")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.SurfaceColor,
                    titleContentColor = AppColors.TextPrimary
                )
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            // Tab Bar — نظير ColoredBox(grey.shade100) + TabBar بألوان backupColor
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(BackupUi.grey100)
            ) {
                TabRow(
                    selectedTabIndex = selectedTab,
                    containerColor = BackupUi.grey100,
                    indicator = { positions ->
                        if (selectedTab < positions.size) {
                            androidx.compose.foundation.layout.Box(
                                Modifier
                                    .tabIndicatorOffset(positions[selectedTab])
                                    .height(3.dp)
                                    .background(BackupUi.backupColor)
                            )
                        }
                    }
                ) {
                    Tab(
                        selected = selectedTab == 0,
                        onClick = { selectedTab = 0 },
                        icon = {
                            Icon(
                                Icons.Filled.Dns, null,
                                tint = if (selectedTab == 0) BackupUi.backupColor else BackupUi.grey500
                            )
                        },
                        text = {
                            Text(
                                "Cloudflare D1",
                                color = if (selectedTab == 0) BackupUi.backupColor else BackupUi.grey500
                            )
                        }
                    )
                    Tab(
                        selected = selectedTab == 1,
                        onClick = { selectedTab = 1 },
                        icon = {
                            Icon(
                                Icons.Filled.PhoneAndroid, null,
                                tint = if (selectedTab == 1) BackupUi.backupColor else BackupUi.grey500
                            )
                        },
                        text = {
                            Text(
                                "النسخ المحلية",
                                color = if (selectedTab == 1) BackupUi.backupColor else BackupUi.grey500
                            )
                        }
                    )
                }
            }

            // Tab Views
            if (selectedTab == 0) {
                CloudflareD1Tab(d1ViewModel)
            } else {
                LocalBackupsTab(backupViewModel)
            }
        }
    }

    if (showHelp) {
        // نظير _showHelpDialog — نفس النص حرفياً.
        AlertDialog(
            onDismissRequest = { showHelp = false },
            title = { Text("مساعدة") },
            text = {
                Column(
                    Modifier.verticalScroll(rememberScrollState())
                ) {
                    Text(
                        "نظام النسخ الاحتياطي:\n\n" +
                            "• Cloudflare D1 (رفع إداري): رفع نسخة إدارية يدوياً\n" +
                            "  - ينشئ ملف JSON من البيانات المحلية\n" +
                            "  - يرفعه إلى Cloudflare بعد تأكيد صريح\n" +
                            "  - لا يُسمح به ما دام Outbox يحتوي تغييرات غير مُسلّمة\n\n" +
                            "• Cloudflare D1: رفع بيانات جداول المزامنة المطابقة " +
                            "لعقد المزامنة السحابي فقط\n" +
                            "  - كتابة آمنة بأسلوب INSERT OR REPLACE\n" +
                            "  - اختيار الجداول وعرض التقدم والإيقاف\n\n" +
                            "• النسخ المحلية: نسخ على ذاكرة الجهاز\n" +
                            "  - إنشاء نسخة احتياطية محلية\n" +
                            "  - استعادة من نسخة محلية\n" +
                            "  - مشاركة أو حذف النسخ القديمة\n" +
                            "  - استيراد نسخة من ملف خارجي\n" +
                            "  - تصدير قاعدة البيانات كاملة إلى ملف Excel"
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { showHelp = false }) { Text("حسناً") }
            }
        )
    }
}

/**
 * نظير SectionHeader في Dart common_widgets — أيقونة + عنوان + إجراء
 * اختياري (يُستخدم في «النسخ المحلية (n)»).
 */
@Composable
fun BackupSectionHeader(
    title: String,
    icon: ImageVector,
    action: (@Composable () -> Unit)? = null
) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = BackupUi.spacingMD.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = BackupUi.backupColor,
            modifier = Modifier.size(22.dp)
        )
        Spacer(Modifier.width(BackupUi.spacingSM.dp))
        Text(
            title,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface
        )
        Spacer(Modifier.weight(1f))
        action?.invoke()
    }
}

/** نظير InfoRow في Dart common_widgets — صف (تسمية، قيمة، أيقونة). */
@Composable
fun InfoRow(label: String, value: String, icon: ImageVector) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = BackupUi.grey600, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(BackupUi.spacingSM.dp))
        Text(label, fontSize = 13.sp, color = BackupUi.grey600)
        Spacer(Modifier.width(BackupUi.spacingSM.dp))
        Text(value, fontSize = 13.sp, fontWeight = FontWeight.W500)
    }
}
