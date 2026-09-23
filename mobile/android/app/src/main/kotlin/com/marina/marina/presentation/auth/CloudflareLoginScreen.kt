package com.marina.marina.presentation.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.ui.theme.AppColors

/**
 * ✅ (2026-09-24) شاشة اتصال Cloudflare — نقل cloudflare_login_screen.dart:
 *  • الحقول تُملأ تلقائياً admin/admin (طلب المالك 2026-09-11).
 *  • دخول تلقائي واحد عند الفتح إن لم تكن المزامنة متصلة.
 *  • عرض النقطة الفعّالة (نطاق مخصّص أو workers.dev) + معرّف الحالة.
 *  • «فحص الاتصال» → /health.
 *  • نطاق worker مخصّص (شبكات اليمن تحجب workers.dev).
 *  • توكن D1 REST المباشر (cfut_…) + فحص صلاحيته.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloudflareLoginScreen(
    viewModel: AuthViewModel,
    onLoginSuccess: () -> Unit = {},
    onBack: () -> Unit = {},
    connectionViewModel: CloudflareConnectionViewModel = hiltViewModel()
) {
    val authState by viewModel.authState.collectAsState()
    val connState by connectionViewModel.state.collectAsState()

    // تعبئة تلقائية: override الفعّال إن وُضع، وإلا admin/admin.
    var username by remember {
        mutableStateOf(
            if (connectionViewModel.hasCredentialOverrides) connectionViewModel.effectiveUsername
            else "admin"
        )
    }
    var password by remember { mutableStateOf("admin") }
    var customUrl by remember { mutableStateOf(connectionViewModel.customEndpoint ?: "") }
    var d1Token by remember { mutableStateOf("") }
    var obscurePassword by remember { mutableStateOf(true) }

    /// حارس ضد تكرار الدخول التلقائي (فشل الشبكة مثلاً) — المحاولة
    /// التالية تبقى يدوية بضغط الزر (نفس حارس Flutter).
    var autoLoginAttempted by remember { mutableStateOf(false) }

    LaunchedEffect(authState.isAuthenticated) {
        if (authState.isAuthenticated) onLoginSuccess()
    }

    // دخول تلقائي واحد عند فتح الشاشة إن لم يكن الاتصال الشبكي جاهزاً.
    LaunchedEffect(Unit) {
        if (!autoLoginAttempted) {
            autoLoginAttempted = true
            if (!connectionViewModel.hasWorkerToken) {
                connectionViewModel.login(username, password)
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("الاتصال بـ Cloudflare") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "رجوع")
                    }
                }
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
            // ─── الحالة العامة ───────────────────────────────────
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Cloud, contentDescription = null, tint = Color(0xFFF6820C), modifier = Modifier.size(20.dp))
                        Text(
                            if (connectionViewModel.hasWorkerToken) "متصل بالخادم" else "غير متصل",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (connectionViewModel.hasWorkerToken) AppColors.SuccessColor else AppColors.WarningColor
                        )
                    }
                    Text("النقطة الفعّالة: ${connectionViewModel.activeEndpoint}", fontSize = 11.sp, color = AppColors.TextSecondary)
                    Text("D1: ${connectionViewModel.let { if (it.hasD1Token) "توكن مباشر محفوظ" else "عبر الـ worker (التلقائي)" }}", fontSize = 11.sp, color = AppColors.TextSecondary)
                }
            }

            // ─── اعتمادات الدخول ─────────────────────────────────
            Card(modifier = Modifier.fillMaxWidth(), elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("اعتمادات المزامنة", fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    OutlinedTextField(
                        value = username,
                        onValueChange = { username = it },
                        label = { Text("اسم المستخدم") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text("كلمة المرور") },
                        modifier = Modifier.fillMaxWidth(),
                        visualTransformation = if (obscurePassword) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        trailingIcon = {
                            IconButton(onClick = { obscurePassword = !obscurePassword }) {
                                Text(if (obscurePassword) "👁" else "🚫", fontSize = 14.sp)
                            }
                        }
                    )
                    authState.error?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { connectionViewModel.login(username, password) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("تسجيل الدخول", fontSize = 12.sp)
                        }
                        OutlinedButton(
                            onClick = { connectionViewModel.checkHealth() },
                            enabled = !connState.isCheckingHealth,
                            modifier = Modifier.weight(1f)
                        ) {
                            if (connState.isCheckingHealth) {
                                CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                            } else {
                                Text("فحص الاتصال", fontSize = 12.sp)
                            }
                        }
                    }
                    if (connectionViewModel.hasCredentialOverrides) {
                        OutlinedButton(
                            onClick = { connectionViewModel.clearCredentialOverrides() },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("الرجوع للاعتمادات المدمجة (admin)", fontSize = 11.sp)
                        }
                    }
                    connState.healthMessage?.let {
                        Text(it, fontSize = 12.sp, color = if (connState.isHealthOk == true) AppColors.SuccessColor else AppColors.DangerColor)
                    }
                }
            }

            // ─── نطاق worker مخصّص ────────────────────────────────
            Card(modifier = Modifier.fillMaxWidth(), elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("نطاق Worker مخصّص", fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    Text(
                        "لشبكات تحجب workers.dev — ضع نطاقك المربوط بنفس الـ worker",
                        fontSize = 11.sp, color = AppColors.TextSecondary
                    )
                    OutlinedTextField(
                        value = customUrl,
                        onValueChange = { customUrl = it },
                        label = { Text("https://natak.com") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri)
                    )
                    connState.customUrlError?.let { Text(it, color = Color.Red, fontSize = 11.sp) }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { connectionViewModel.setCustomUrl(customUrl) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("حفظ النطاق", fontSize = 12.sp)
                        }
                        OutlinedButton(
                            onClick = {
                                customUrl = ""
                                connectionViewModel.setCustomUrl(null)
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("مسح", fontSize = 12.sp)
                        }
                    }
                }
            }

            // ─── توكن D1 REST المباشر ─────────────────────────────
            Card(modifier = Modifier.fillMaxWidth(), elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("توكن D1 المباشر (اختياري)", fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    Text(
                        "للنسخ الاحتياطي المباشر إلى D1 — صلاحية D1 Edit (cfut_…)",
                        fontSize = 11.sp, color = AppColors.TextSecondary
                    )
                    OutlinedTextField(
                        value = d1Token,
                        onValueChange = { d1Token = it },
                        label = { Text(if (connectionViewModel.hasD1Token) "توكن محفوظ — ضع بديلاً أو امسح" else "cfut_…") },
                        modifier = Modifier.fillMaxWidth(),
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password)
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { connectionViewModel.saveD1TokenAndProbe(d1Token) },
                            enabled = !connState.isProbingD1,
                            modifier = Modifier.weight(1f)
                        ) {
                            if (connState.isProbingD1) {
                                CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                            } else {
                                Text("حفظ وفحص", fontSize = 12.sp)
                            }
                        }
                        if (connectionViewModel.hasD1Token) {
                            OutlinedButton(
                                onClick = {
                                    d1Token = ""
                                    connectionViewModel.saveD1TokenAndProbe(null)
                                },
                                modifier = Modifier.weight(1f)
                            ) {
                                Text("إلغاء التوكن", fontSize = 12.sp)
                            }
                        }
                    }
                    connState.d1Message?.let {
                        Text(it, fontSize = 12.sp, color = if (connState.isD1Ok == true) AppColors.SuccessColor else AppColors.WarningColor)
                    }
                }
            }

            // ─── رسالة الحفظ العامة ──────────────────────────────
            connState.savedMessage?.let {
                Card(
                    colors = CardDefaults.cardColors(containerColor = AppColors.PrimaryLight),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(it, modifier = Modifier.padding(10.dp), fontSize = 12.sp)
                }
            }

            Text(
                "المصادقة الأساسية للدخول محلية (admin/admin) وتعمل بلا شبكة — هذه الشاشة لضبط اتصال المزامنة السحابية",
                fontSize = 10.sp,
                color = AppColors.TextSecondary,
                modifier = Modifier.padding(bottom = 8.dp)
            )
        }
    }
}
