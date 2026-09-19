package com.marina.marina.presentation.dashboard

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun DashboardScreen(
    onNavigate: (String) -> Unit = {},
    viewModel: DashboardViewModel = hiltViewModel()
) {
    val state by viewModel.dashboardState
    LaunchedEffect(Unit) { viewModel.loadDashboardData() }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("لوحة التحكم", style = AppTypography.titleLarge) },
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
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = "مرحباً بعودتك",
                    style = AppTypography.headlineMedium,
                    color = AppColors.TextPrimary
                )
                Text(
                    text = "نظام إدارة فندق مارينا",
                    style = AppTypography.bodyLarge,
                    color = AppColors.TextSecondary
                )

                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        text = "تعذر تحميل البيانات: ${state.error}",
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor
                    )
                    state.isDataLoaded -> Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        StatCard(
                            label = "الحجوزات النشطة",
                            value = state.activeBookings.toString(),
                            modifier = Modifier.weight(1f)
                        )
                        StatCard(
                            label = "نسبة الإشغال",
                            value = "${(state.occupancyRate * 100).toInt()}%",
                            modifier = Modifier.weight(1f)
                        )
                        StatCard(
                            label = "ديون معلقة",
                            value = state.pendingDebts.toString(),
                            modifier = Modifier.weight(1f)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Quick action cards (all destinations, 4-column grid).
                val quickActions = listOf(
                    "الغرف" to "rooms",
                    "الحجوزات" to "bookings",
                    "المدفوعات" to "payments",
                    "الديون" to "debts",
                    "الموظفون" to "employees",
                    "المصروفات" to "expenses",
                    "الصندوق" to "finance",
                    "التقارير" to "reports",
                    "المخزون" to "inventory",
                    "الملاحظات" to "notes",
                    "المعلومية" to "information",
                    "المساعد الذكي" to "ai_chat",
                    "الإعدادات" to "settings"
                )
                LazyVerticalGrid(
                    columns = GridCells.Fixed(4),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth().weight(1f)
                ) {
                    items(quickActions) { (title, route) ->
                        ActionCard(
                            title = title,
                            icon = "•",
                            modifier = Modifier,
                            onClick = { onNavigate(route) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun StatCard(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(text = value, style = AppTypography.headlineSmall, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
            Spacer(modifier = Modifier.height(4.dp))
            Text(text = label, style = AppTypography.bodySmall, color = AppColors.TextSecondary)
        }
    }
}

@Composable
fun ActionCard(
    title: String,
    icon: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit = {}
) {
    Card(
        modifier = modifier,
        onClick = onClick,
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(text = icon, style = AppTypography.headlineMedium)
            Spacer(modifier = Modifier.height(8.dp))
            Text(text = title, style = AppTypography.titleSmall, color = AppColors.TextPrimary)
        }
    }
}