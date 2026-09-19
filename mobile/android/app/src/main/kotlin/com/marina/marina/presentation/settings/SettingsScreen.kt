package com.marina.marina.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun SettingsScreen(
    onLogout: () -> Unit = {},
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.consumeMessage()
        }
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
                    .padding(16.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // ---- Quick stats ------------------------------------------------
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SettingStat("الغرف", "${state.roomCount}", Modifier.weight(1f))
                    SettingStat("حجوزات نشطة", "${state.activeBookings}", Modifier.weight(1f))
                    SettingStat("الموظفون", "${state.employeeCount}", Modifier.weight(1f))
                }

                // ---- Cloud sync -------------------------------------------------
                SettingsSectionCard(title = "المزامنة السحابية") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text("حالة المزامنة", style = AppTypography.titleSmall, fontWeight = FontWeight.Bold)
                            Text(
                                if (state.sync.isSyncing) "جارٍ المزامنة..."
                                else state.sync.lastMessage.ifBlank { "لم تتم المزامنة بعد" },
                                style = AppTypography.bodySmall,
                                color = if (state.sync.isError) AppColors.DangerColor else AppColors.TextSecondary
                            )
                        }
                        Button(
                            onClick = viewModel::syncNow,
                            enabled = !state.sync.isSyncing,
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryColor),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            if (state.sync.isSyncing) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp,
                                    color = Color.White
                                )
                            } else {
                                Text("مزامنة الآن", color = Color.White, fontSize = 13.sp)
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))
                    HorizontalDivider(color = AppColors.DividerColor)
                    Spacer(modifier = Modifier.height(10.dp))

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("تغييرات محلية معلّقة", style = AppTypography.bodyMedium)
                        Text(
                            "${state.pendingOutbox} عنصر",
                            style = AppTypography.bodyMedium,
                            fontWeight = FontWeight.Bold,
                            color = if (state.pendingOutbox > 0) AppColors.WarningColor else AppColors.SuccessColor
                        )
                    }
                }

                // ---- Hotel day info ---------------------------------------------
                SettingsSectionCard(title = "اليوم الفندقي") {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("مفتاح اليوم الحالي", style = AppTypography.bodyMedium)
                        Text(
                            HotelTimeEngine.currentHotelDayKey(),
                            style = AppTypography.bodyMedium,
                            fontWeight = FontWeight.Bold,
                            color = AppColors.PrimaryColor
                        )
                    }
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        "حد اليوم الفندقي: 14:01 — الحجوزات والمدفوعات والمصروفات تُحتسب ضمن هذا اليوم.",
                        style = AppTypography.bodySmall,
                        color = AppColors.TextSecondary
                    )
                }

                // ---- About ------------------------------------------------------
                SettingsSectionCard(title = "حول التطبيق") {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("الإصدار", style = AppTypography.bodyMedium)
                        Text("1.0.0 (Kotlin)", style = AppTypography.bodyMedium, fontWeight = FontWeight.Bold)
                    }
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        "نظام إدارة فندق مارينا — النسخة الأصلية Kotlin + Jetpack Compose\nبنية معمارية نظيفة + Room + Hilt + مزامنة Cloudflare D1",
                        style = AppTypography.bodySmall,
                        color = AppColors.TextSecondary
                    )
                }

                // ---- Logout -----------------------------------------------------
                Button(
                    onClick = onLogout,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.DangerColor),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text("تسجيل الخروج", color = Color.White, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun SettingStat(label: String, value: String, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(10.dp)
    ) {
        Column(
            modifier = Modifier.padding(vertical = 12.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value, style = AppTypography.titleLarge, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
            Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary)
        }
    }
}

@Composable
private fun SettingsSectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = AppTypography.titleMedium, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
            Spacer(modifier = Modifier.height(4.dp))
            content()
        }
    }
}
