package com.marina.marina.presentation.auth

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Login
import androidx.compose.material.icons.filled.PersonOutline
import androidx.compose.material.icons.filled.RestartAlt
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.presentation.auth.CloudflareConnectionViewModel.CfSyncStatus
import com.marina.marina.presentation.auth.CloudflareConnectionViewModel.MessageKind
import com.marina.marina.ui.theme.AppColors

/**
 * ✅ (2026-09-24) شاشة «تسجيل الدخول إلى Cloudflare» — نقل 1:1 لـ
 * cloudflare_login_screen.dart (فرع feat/cloudflare-sync-execution):
 *
 *  • بطاقة الحالة العلوية: أيقونة/لون/نص حسب حالة المزامنة + صفّا
 *    «الخادم» (النقطة الفعّالة) و«الحساب» (بخط monospace).
 *  • بانر خطأ التهيئة (initError) إن وُجد.
 *  • بطاقة الاعتمادات: عنوان بأيقونة مفتاح + ملاحظة الإبقاء على كلمة
 *    المرور + حقلان مع أيقونات بادئة + زر دخول بمؤشر تحميل + فحص
 *    الاتصال + زر الاعتمادات المدمجة (عند وجود overrides).
 *  • بانرا الرسالة وفحص الصحة + حاوية الشرح المختصر.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloudflareLoginScreen(
    onBack: () -> Unit = {},
    viewModel: CloudflareConnectionViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    // دخول تلقائي واحد عند فتح الشاشة (نظير addPostFrameCallback في Dart).
    LaunchedEffect(Unit) { viewModel.autoLoginIfNeeded() }

    Scaffold(
        containerColor = AppColors.BackgroundColor,
        topBar = {
            TopAppBar(
                title = { Text("تسجيل الدخول إلى Cloudflare") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "رجوع")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.PrimaryColor,
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            // ─── بطاقة الحالة الحالية (_StatusCard) ───
            StatusCard(
                status = state.status,
                workerUrl = state.workerUrl,
                account = state.account
            )
            Spacer(Modifier.height(16.dp))

            // ─── بانر آخر خطأ تهيئة (_buildInitErrorBanner) ───
            state.initError?.let { initError ->
                Banner(text = initError, color = AppColors.DangerColor)
                Spacer(Modifier.height(16.dp))
            }

            // ─── بطاقة الاعتمادات ───
            Card(
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Key, contentDescription = null, tint = AppColors.PrimaryColor, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("اعتمادات حساب المزامنة", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "اترك كلمة المرور فارغة للإبقاء على الحالية.",
                        fontSize = 12.sp,
                        color = AppColors.TextSecondary
                    )
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = state.usernameField,
                        onValueChange = viewModel::onUsernameChange,
                        label = { Text("اسم المستخدم") },
                        leadingIcon = { Icon(Icons.Default.PersonOutline, contentDescription = null) },
                        singleLine = true,
                        enabled = !state.isLoggingIn,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = state.passwordField,
                        onValueChange = viewModel::onPasswordChange,
                        label = { Text("كلمة المرور") },
                        leadingIcon = { Icon(Icons.Outlined.Lock, contentDescription = null) },
                        singleLine = true,
                        enabled = !state.isLoggingIn,
                        visualTransformation = if (state.obscurePassword) {
                            PasswordVisualTransformation()
                        } else {
                            VisualTransformation.None
                        },
                        trailingIcon = {
                            IconButton(onClick = viewModel::toggleObscurePassword) {
                                Icon(
                                    if (state.obscurePassword) Icons.Default.Visibility else Icons.Default.VisibilityOff,
                                    contentDescription = null
                                )
                            }
                        },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(16.dp))
                    androidx.compose.material3.Button(
                        onClick = viewModel::login,
                        enabled = !state.isLoggingIn,
                        colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                            containerColor = AppColors.PrimaryColor,
                            contentColor = Color.White
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        if (state.isLoggingIn) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                                color = Color.White
                            )
                            Spacer(Modifier.width(8.dp))
                            Text("جارٍ تسجيل الدخول...")
                        } else {
                            Icon(Icons.Default.Login, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("تسجيل الدخول")
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedButton(
                            onClick = viewModel::checkHealth,
                            enabled = !state.isCheckingHealth,
                            modifier = Modifier.weight(1f)
                        ) {
                            if (state.isCheckingHealth) {
                                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                            } else {
                                Icon(Icons.Default.WifiTethering, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("فحص الاتصال")
                            }
                        }
                        if (state.hasCredentialOverrides) {
                            TextButton(
                                onClick = viewModel::resetOverrides,
                                enabled = !state.isLoggingIn && !state.isCheckingHealth
                            ) {
                                Icon(Icons.Default.RestartAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(4.dp))
                                Text("الاعتمادات المدمجة")
                            }
                        }
                    }
                }
            }

            // ─── بانر الرسالة (_message) ───
            state.message?.let { message ->
                Spacer(Modifier.height(12.dp))
                Banner(
                    text = message.text,
                    color = when (message.kind) {
                        MessageKind.SUCCESS -> AppColors.SuccessColor
                        MessageKind.DANGER -> AppColors.DangerColor
                        MessageKind.INFO -> AppColors.InfoColor
                    }
                )
            }

            // ─── بانر نتيجة فحص الاتصال (_healthResult) ───
            state.healthResult?.let { health ->
                Spacer(Modifier.height(8.dp))
                Banner(
                    text = health.text,
                    color = if (health.kind == MessageKind.SUCCESS) AppColors.SuccessColor else AppColors.DangerColor
                )
            }

            Spacer(Modifier.height(16.dp))

            // ─── شرح مختصر (Container infoColor 8% في Dart) ───
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        color = AppColors.InfoColor.copy(alpha = 0.08f),
                        shape = RoundedCornerShape(8.dp)
                    )
                    .padding(12.dp)
            ) {
                Text(
                    "تُحفظ الاعتمادات على هذا الجهاز فقط وتُستخدم مع كل عمليات " +
                        "المزامنة (دفع/سحب). إذا كان workers.dev محجوباً في شبكتك " +
                        "أضف نطاقاً مخصّصاً من إعدادات المزامنة أولاً.",
                    fontSize = 12.sp,
                    lineHeight = 19.sp
                )
            }
        }
    }
}

// ═══════════════ مكونات مطابقة لعناصر Dart ═══════════════

/** ألوان حالات SyncStatus في Dart (Colors.blue/green/orange/grey). */
private object StatusColors {
    val blue = Color(0xFF2196F3)
    val green = Color(0xFF4CAF50)
    val orange = Color(0xFFFF9800)
    val grey = Color(0xFF9E9E9E)
}

/** بطاقة الحالة العلوية — لحظية (نظير _StatusCard في Dart). */
@Composable
private fun StatusCard(status: CfSyncStatus, workerUrl: String, account: String) {
    val (icon, color, label) = when (status) {
        CfSyncStatus.SYNCING -> Triple(Icons.Default.Sync, StatusColors.blue, "جاري المزامنة الآن...")
        CfSyncStatus.SUCCESS -> Triple(Icons.Default.CloudDone, StatusColors.green, "متصل — آخر مزامنة نجحت")
        CfSyncStatus.FAILED -> Triple(Icons.Default.CloudOff, StatusColors.orange, "آخر مزامنة فشلت — جرّب تسجيل الدخول أدناه")
        CfSyncStatus.IDLE -> Triple(Icons.Outlined.Cloud, StatusColors.grey, "جاهز — لا مزامنة جارية")
    }

    Card(
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(28.dp))
                Spacer(Modifier.width(12.dp))
                Text(
                    label,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
            }
            Spacer(Modifier.height(12.dp))
            StatusRow(Icons.Default.Dns, "الخادم", workerUrl)
            Spacer(Modifier.height(6.dp))
            StatusRow(Icons.Default.Key, "الحساب", account)
        }
    }
}

/** صف معلومة — أيقونة 16 + تسمية 13 + قيمة 13 w600 monospace (Dart). */
@Composable
private fun StatusRow(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = AppColors.TextSecondary, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(8.dp))
        Text("$label: ", fontSize = 13.sp)
        Text(
            value,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
    }
}

/** بانر ملوّن — خلفية 10% + حدود 40% + أيقونة معلومات (نظير _buildBanner). */
@Composable
private fun Banner(text: String, color: Color) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                color = color.copy(alpha = 0.1f),
                shape = RoundedCornerShape(8.dp)
            )
            .border(
                border = BorderStroke(1.dp, color.copy(alpha = 0.4f)),
                shape = RoundedCornerShape(8.dp)
            )
            .padding(12.dp),
        verticalAlignment = Alignment.Top
    ) {
        Icon(Icons.Default.Info, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, color = color, fontSize = 13.sp, lineHeight = 19.sp)
    }
}
