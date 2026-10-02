package com.marina.marina.presentation.login

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.marina.marina.presentation.auth.AuthViewModel
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.MarinaPalette
import com.marina.marina.ui.theme.MarinaTheme

/** Premium coastal login with the same authentication and validation contract. */
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

    LaunchedEffect(authState.isRestoring) {
        if (!authState.isRestoring) submitting = false
    }
    LaunchedEffect(authState.isAuthenticated) {
        if (authState.isAuthenticated) onLoginSuccess()
    }

    MarinaTheme {
        Scaffold(containerColor = AppColors.BackgroundColor) { padding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(AppColors.BackgroundColor, AppColors.SurfaceColor)
                        )
                    )
                    .padding(padding)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .imePadding()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 22.dp, vertical = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .widthIn(max = 460.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        BrandWelcomeCard()
                        Spacer(Modifier.height(18.dp))

                        OutlinedCard(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(26.dp),
                            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                            border = BorderStroke(1.dp, AppColors.DividerColor),
                            colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor)
                        ) {
                            Column(
                                modifier = Modifier.padding(horizontal = 22.dp, vertical = 24.dp),
                                verticalArrangement = Arrangement.spacedBy(14.dp)
                            ) {
                                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(
                                        text = "مرحباً بعودتك",
                                        style = MaterialTheme.typography.headlineSmall,
                                        color = AppColors.TextPrimary,
                                        fontWeight = FontWeight.Bold
                                    )
                                    Text(
                                        text = "سجّل الدخول للمتابعة إلى لوحة الفندق",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = AppColors.TextSecondary
                                    )
                                }

                                OutlinedTextField(
                                    value = username,
                                    onValueChange = {
                                        username = it
                                        usernameError = null
                                    },
                                    label = { Text("اسم المستخدم") },
                                    placeholder = { Text("أدخل اسم المستخدم") },
                                    leadingIcon = {
                                        androidx.compose.material3.Icon(
                                            imageVector = Icons.Default.Person,
                                            contentDescription = null,
                                            tint = AppColors.TextSecondary
                                        )
                                    },
                                    isError = usernameError != null,
                                    supportingText = usernameError?.let { error ->
                                        { Text(error) }
                                    },
                                    singleLine = true,
                                    shape = RoundedCornerShape(16.dp),
                                    modifier = Modifier.fillMaxWidth(),
                                    colors = loginFieldColors()
                                )

                                OutlinedTextField(
                                    value = password,
                                    onValueChange = {
                                        password = it
                                        passwordError = null
                                    },
                                    label = { Text("كلمة المرور") },
                                    placeholder = { Text("أدخل كلمة المرور") },
                                    leadingIcon = {
                                        androidx.compose.material3.Icon(
                                            imageVector = Icons.Default.Lock,
                                            contentDescription = null,
                                            tint = AppColors.TextSecondary
                                        )
                                    },
                                    isError = passwordError != null,
                                    supportingText = passwordError?.let { error ->
                                        { Text(error) }
                                    },
                                    singleLine = true,
                                    shape = RoundedCornerShape(16.dp),
                                    visualTransformation = if (passwordVisible) {
                                        VisualTransformation.None
                                    } else {
                                        PasswordVisualTransformation()
                                    },
                                    trailingIcon = {
                                        androidx.compose.material3.IconButton(
                                            onClick = { passwordVisible = !passwordVisible }
                                        ) {
                                            androidx.compose.material3.Icon(
                                                imageVector = if (passwordVisible) {
                                                    Icons.Default.VisibilityOff
                                                } else {
                                                    Icons.Default.Visibility
                                                },
                                                contentDescription = if (passwordVisible) {
                                                    "إخفاء كلمة المرور"
                                                } else {
                                                    "إظهار كلمة المرور"
                                                },
                                                tint = AppColors.TextSecondary
                                            )
                                        }
                                    },
                                    modifier = Modifier.fillMaxWidth(),
                                    colors = loginFieldColors()
                                )

                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Checkbox(
                                        checked = rememberMe,
                                        onCheckedChange = viewModel::setRememberMe,
                                        colors = CheckboxDefaults.colors(
                                            checkedColor = AppColors.PrimaryActionColor,
                                            checkmarkColor = Color.White
                                        )
                                    )
                                    Text(
                                        text = "تذكرني على هذا الجهاز",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = AppColors.TextPrimary
                                    )
                                }

                                if (authState.error != null) {
                                    Text(
                                        text = authState.error!!,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = AppColors.DangerColor
                                    )
                                }

                                Button(
                                    onClick = {
                                        usernameError = if (username.isBlank()) {
                                            "يرجى إدخال اسم المستخدم"
                                        } else {
                                            null
                                        }
                                        passwordError = if (password.isEmpty()) {
                                            "يرجى إدخال كلمة المرور"
                                        } else {
                                            null
                                        }
                                        if (usernameError != null || passwordError != null) {
                                            return@Button
                                        }
                                        submitting = true
                                        viewModel.login(username.trim(), password, rememberMe)
                                    },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(54.dp),
                                    enabled = !submitting && !authState.isRestoring,
                                    shape = RoundedCornerShape(16.dp),
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = AppColors.PrimaryActionColor,
                                        contentColor = Color.White
                                    )
                                ) {
                                    if (submitting || authState.isRestoring) {
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(20.dp),
                                            strokeWidth = 2.dp,
                                            color = Color.White
                                        )
                                    } else {
                                        Text(
                                            text = "دخول إلى النظام",
                                            style = MaterialTheme.typography.titleMedium,
                                            color = Color.White
                                        )
                                    }
                                }
                            }
                        }

                        Spacer(Modifier.height(14.dp))
                        Text(
                            text = "نظام إدارة فندق مارينا",
                            style = MaterialTheme.typography.labelMedium,
                            color = AppColors.TextSecondary
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun BrandWelcomeCard() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Brush.linearGradient(
                    listOf(MarinaPalette.OceanNight, MarinaPalette.Ocean)
                ),
                RoundedCornerShape(26.dp)
            )
            .padding(horizontal = 22.dp, vertical = 20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        androidx.compose.material3.Surface(
            modifier = Modifier.size(58.dp),
            shape = RoundedCornerShape(18.dp),
            color = AppColors.AccentColor
        ) {
            androidx.compose.material3.Icon(
                imageVector = Icons.Filled.Hotel,
                contentDescription = null,
                tint = MarinaPalette.OceanNight,
                modifier = Modifier.padding(15.dp)
            )
        }
        Spacer(Modifier.width(16.dp))
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                text = "فندق مارينا",
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            Text(
                text = "ضيافة راقية تبدأ بإدارة واضحة",
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.82f)
            )
        }
    }
}

@Composable
private fun loginFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = AppColors.PrimaryColor,
    unfocusedBorderColor = AppColors.DividerColor,
    focusedLabelColor = AppColors.PrimaryColor,
    unfocusedLabelColor = AppColors.TextSecondary,
    cursorColor = AppColors.PrimaryColor,
    focusedContainerColor = AppColors.SurfaceColor,
    unfocusedContainerColor = AppColors.SurfaceColor,
    errorBorderColor = AppColors.DangerColor,
    errorLabelColor = AppColors.DangerColor
)
