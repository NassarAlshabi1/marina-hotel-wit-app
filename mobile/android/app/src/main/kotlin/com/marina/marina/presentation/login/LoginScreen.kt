package com.marina.marina.presentation.login

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.widthIn
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.presentation.auth.AuthViewModel

/**
 * شاشة الدخول — نقل 1:1 لـ `login_screen.dart`:
 *  • رأس أفقي: أيقونة قفل 28 + «تسجيل الدخول» 20 bold (Dart l.78-88).
 *  • حقول بتلميحات (أدخل اسم المستخدم / أدخل كلمة المرور).
 *  • «تذكرني» تفاعلي يُحمّل من التخزين (نظير AuthLocalStore).
 *  • زر «دخول» بمؤشر تحميل أبيض 18 + رسائل تحقق تحت الحقول.
 *  • بطاقة بعرض أقصى 420 متمركزة على خلفية فاتحة (نفس Dart).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginScreen(
    viewModel: AuthViewModel,
    onLoginSuccess: () -> Unit = {}
) {
    val authState by viewModel.authState.collectAsState()
    val rememberMe by viewModel.rememberMe.collectAsState()
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }
    var submitting by remember { mutableStateOf(false) }
    var usernameError by remember { mutableStateOf<String?>(null) }
    var passwordError by remember { mutableStateOf<String?>(null) }

    // مؤشر الإرسال يتبع حالة المزامنة (isRestoring يعمل كـ _submitting).
    LaunchedEffect(authState.isRestoring) {
        if (!authState.isRestoring) submitting = false
    }

    LaunchedEffect(authState.isAuthenticated) {
        if (authState.isAuthenticated) {
            onLoginSuccess()
        }
    }

    MarinaTheme {
        Scaffold(
            containerColor = Color(0xFFF8F8FC)
        ) { padding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(24.dp),
                contentAlignment = Alignment.Center
            ) {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .widthIn(max = 420.dp)
                        .wrapContentSize(),
                    elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
                    colors = CardDefaults.cardColors(containerColor = Color(0xFFFFFFFF))
                ) {
                    Column(
                        modifier = Modifier.padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        // رأس أفقي — نفس صف Dart (Icon 28 + نص 20 bold).
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Default.Lock,
                                contentDescription = null,
                                tint = Color(0xFF242476),
                                modifier = Modifier.size(28.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "تسجيل الدخول",
                                fontSize = 20.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFF0A0E2F)
                            )
                        }
                        Spacer(modifier = Modifier.height(16.dp))

                        OutlinedTextField(
                            value = username,
                            onValueChange = {
                                username = it
                                usernameError = null
                            },
                            label = { Text("اسم المستخدم") },
                            placeholder = { Text("أدخل اسم المستخدم") },
                            isError = usernameError != null,
                            supportingText = usernameError?.let { error -> { Text(error, color = Color(0xFFE5484D)) } },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = Color(0xFF242476),
                                unfocusedBorderColor = Color(0xFFD3D3E4)
                            )
                        )
                        Spacer(modifier = Modifier.height(12.dp))

                        OutlinedTextField(
                            value = password,
                            onValueChange = {
                                password = it
                                passwordError = null
                            },
                            label = { Text("كلمة المرور") },
                            placeholder = { Text("أدخل كلمة المرور") },
                            isError = passwordError != null,
                            supportingText = passwordError?.let { error -> { Text(error, color = Color(0xFFE5484D)) } },
                            singleLine = true,
                            visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                            trailingIcon = {
                                IconButton(onClick = { passwordVisible = !passwordVisible }) {
                                    Icon(
                                        imageVector = if (passwordVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                        contentDescription = null
                                    )
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = Color(0xFF242476),
                                unfocusedBorderColor = Color(0xFFD3D3E4)
                            )
                        )
                        Spacer(modifier = Modifier.height(8.dp))

                        // «تذكرني» — تفاعلي ويُحمّل من التخزين (نفس Dart).
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(
                                checked = rememberMe,
                                onCheckedChange = { viewModel.setRememberMe(it) },
                                colors = CheckboxDefaults.colors(checkedColor = Color(0xFF242476))
                            )
                            Text("تذكرني", style = AppTypographyBody())
                        }
                        Spacer(modifier = Modifier.height(8.dp))

                        if (authState.error != null) {
                            Text(
                                text = authState.error!!,
                                color = Color(0xFFE5484D),
                                fontSize = 13.sp
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                        }

                        Button(
                            onClick = {
                                // نفس مدققات Form في Dart.
                                usernameError = if (username.isBlank()) "يرجى إدخال اسم المستخدم" else null
                                passwordError = if (password.isEmpty()) "يرجى إدخال كلمة المرور" else null
                                if (usernameError != null || passwordError != null) return@Button
                                submitting = true
                                viewModel.login(username.trim(), password, rememberMe)
                            },
                            modifier = Modifier.fillMaxWidth(),
                            enabled = !submitting && !authState.isRestoring,
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF242476))
                        ) {
                            if (submitting || authState.isRestoring) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(18.dp),
                                    strokeWidth = 2.dp,
                                    color = Color.White
                                )
                            } else {
                                Text("دخول", color = Color.White)
                            }
                        }
                    }
                }
            }
        }
    }
}

/** نص الجسم بحجم Dart الافتراضي (14). */
@Composable
private fun AppTypographyBody() = androidx.compose.ui.text.TextStyle(fontSize = 14.sp)
