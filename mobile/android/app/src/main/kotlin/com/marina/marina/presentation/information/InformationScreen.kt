package com.marina.marina.presentation.information

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun InformationScreen(
    viewModel: InformationViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("سجل المعلومية", style = AppTypography.titleLarge) },
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
                    .padding(horizontal = 16.dp)
            ) {
                Text(
                    "سجل الضيوف للتقارير الأمنية",
                    style = AppTypography.bodySmall,
                    color = AppColors.TextSecondary
                )

                Spacer(modifier = Modifier.height(10.dp))

                OutlinedTextField(
                    value = state.searchQuery,
                    onValueChange = viewModel::setSearchQuery,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("بحث بالاسم، الغرفة، رقم الهوية...") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp)
                )

                Spacer(modifier = Modifier.height(10.dp))

                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        "تعذر تحميل السجل: ${state.error}",
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor
                    )
                    state.filtered.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        contentAlignment = Alignment.Center
                    ) { Text("لا توجد سجلات", style = AppTypography.bodyLarge, color = AppColors.TextSecondary) }
                    else -> LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(bottom = 24.dp)
                    ) {
                        item {
                            Card(
                                colors = CardDefaults.cardColors(containerColor = AppColors.PrimaryColor),
                                shape = RoundedCornerShape(10.dp),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp).fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    RegistryHeaderCell("الغرفة", Modifier.weight(0.7f))
                                    RegistryHeaderCell("الاسم", Modifier.weight(1.4f))
                                    RegistryHeaderCell("الجنسية", Modifier.weight(0.9f))
                                    RegistryHeaderCell("الهوية", Modifier.weight(1f))
                                }
                            }
                        }
                        items(state.filtered, key = { it.bookingId }) { row ->
                            RegistryRowCard(row)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RegistryHeaderCell(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = AppTypography.labelMedium,
        color = Color.White,
        fontWeight = FontWeight.Bold,
        modifier = modifier
    )
}

@Composable
private fun RegistryRowCard(row: GuestRegistryRow) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Box(
                    modifier = Modifier
                        .background(AppColors.PrimaryColor, RoundedCornerShape(6.dp))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(row.roomNumber, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
                Text(
                    row.guestName,
                    style = AppTypography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.TextPrimary
                )
                Text(
                    "دخول: ${row.checkinDate}",
                    style = AppTypography.labelSmall,
                    color = AppColors.TextSecondary
                )
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                InfoTag("الجنسية", row.nationality)
                InfoTag("نوع الهوية", row.idType)
                InfoTag("رقم الهوية", row.idNumber)
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                InfoTag("تاريخ الإصدار", row.idIssueDate)
                InfoTag("مكان الإصدار", row.idIssuePlace)
            }
        }
    }
}

@Composable
private fun InfoTag(label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("$label: ", style = AppTypography.labelSmall, color = AppColors.TextSecondary)
        Text(value, style = AppTypography.labelSmall, color = AppColors.TextPrimary, fontWeight = FontWeight.SemiBold)
    }
}
