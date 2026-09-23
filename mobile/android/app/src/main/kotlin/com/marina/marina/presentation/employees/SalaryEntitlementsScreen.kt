package com.marina.marina.presentation.employees

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.SalaryEntitlementCalculator
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

/** Dart salary_entitlements_screen.dart (l.71-520) — parity port. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SalaryEntitlementsScreen(
    viewModel: SalaryEntitlementsViewModel = hiltViewModel(),
    onBack: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()
    val snackbar = remember { SnackbarHostState() }
    var expandedEmployee by remember { mutableStateOf<Long?>(null) }

    LaunchedEffect(state.message, state.error) {
        (state.message ?: state.error)?.let { snackbar.showSnackbar(it) }
        viewModel.consumeMessage()
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("استحقاقات الرواتب", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, contentDescription = "رجوع") }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            snackbarHost = { SnackbarHost(snackbar) }
        ) { padding ->
            Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        "فشل تحميل البيانات: ${state.error}",
                        color = AppColors.DangerColor,
                        style = AppTypography.bodyMedium
                    )
                    state.isEmpty -> Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("لا يوجد موظفين نشطين", style = AppTypography.bodyLarge, color = AppColors.TextSecondary)
                    }
                    else -> {
                        // Dart summary card (l.116-172).
                        SummaryCard(state)

                        LazyColumn(
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.padding(top = 12.dp)
                        ) {
                            items(state.entitlements, key = { it.employee.id }) { ent ->
                                EntitlementCard(
                                    entitlement = ent,
                                    cycle = state.cycleResults[ent.employee.id],
                                    expanded = expandedEmployee == ent.employee.id,
                                    onToggle = {
                                        expandedEmployee = if (expandedEmployee == ent.employee.id) null else ent.employee.id
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SummaryCard(state: SalaryEntitlementsUiState) {
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("ملخص الاستحقاقات (${state.totalCount} موظف)", style = AppTypography.titleMedium, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                StatCell("إجمالي الاستحقاقات", CurrencyFormatter.formatAmount(state.totalEntitlements), AppColors.SuccessColor)
                StatCell("إجمالي السحبيات", CurrencyFormatter.formatAmount(state.totalWithdrawals), AppColors.WarningColor)
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                StatCell("إجمالي السلف", CurrencyFormatter.formatAmount(state.totalAdvances), Color(0xFF3F51B5))
                StatCell("إجمالي الخصومات", CurrencyFormatter.formatAmount(state.totalDeductions), AppColors.DangerColor)
            }
            HorizontalRule()
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("صافي المستحقات", style = AppTypography.titleMedium, fontWeight = FontWeight.Bold)
                Text(
                    CurrencyFormatter.formatAmount(state.totalNet),
                    style = AppTypography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = if (state.totalNet >= 0) Color(0xFF1976D2) else AppColors.DangerColor
                )
            }
        }
    }
}

@Composable
private fun StatCell(label: String, value: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = AppTypography.titleSmall, fontWeight = FontWeight.Bold, color = color)
        Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary)
    }
}

@Composable
private fun HorizontalRule() {
    Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(AppColors.DividerColor))
}

@Composable
private fun EntitlementCard(
    entitlement: SalaryEntitlementCalculator.Entitlement,
    cycle: SalaryEntitlementCalculator.CycleResult?,
    expanded: Boolean,
    onToggle: () -> Unit
) {
    val ent = entitlement
    Card(
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onToggle)
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(ent.employee.name, style = AppTypography.titleMedium, fontWeight = FontWeight.Bold)
                    // Dart l.194-229: hire date + مدة العمل + الراتب الشهري.
                    Text(
                        "مدة العمل: ${ent.totalMonthsWorked} شهر • الراتب: ${CurrencyFormatter.formatAmount(ent.basicSalary)}",
                        style = AppTypography.bodySmall, color = AppColors.TextSecondary
                    )
                }
                Icon(
                    if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = null,
                    tint = AppColors.TextSecondary
                )
            }

            // Dart breakdown rows (l.230-257).
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                StatCell("الاستحقاق", CurrencyFormatter.formatAmount(ent.totalEntitlement), AppColors.SuccessColor)
                StatCell("السحبيات", CurrencyFormatter.formatAmount(ent.totalWithdrawals), AppColors.WarningColor)
                StatCell("السلف", CurrencyFormatter.formatAmount(ent.totalAdvances), Color(0xFF3F51B5))
                StatCell("الخصومات", CurrencyFormatter.formatAmount(ent.totalDeductions), AppColors.DangerColor)
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("المتبقي (الصافي)", style = AppTypography.bodyMedium, fontWeight = FontWeight.Bold)
                Text(
                    CurrencyFormatter.formatAmount(ent.netEntitlement),
                    style = AppTypography.bodyMedium, fontWeight = FontWeight.Bold,
                    color = if (ent.netEntitlement >= 0) Color(0xFF1976D2) else AppColors.DangerColor
                )
            }

            AnimatedVisibility(visible = expanded) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    HorizontalRule()

                    // Dart monthly cycle card (l.360-520).
                    cycle?.let { c ->
                        Column(
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(
                                    when {
                                        c.carryOverToNext > 0 -> AppColors.DangerColor.copy(alpha = 0.08f)
                                        c.carriedOverFromPrevious > 0 -> AppColors.WarningColor.copy(alpha = 0.08f)
                                        else -> Color(0xFF1976D2).copy(alpha = 0.06f)
                                    },
                                    RoundedCornerShape(10.dp)
                                )
                                .padding(10.dp)
                        ) {
                            Text("الدورة الشهرية الحالية", style = AppTypography.titleSmall, fontWeight = FontWeight.Bold)
                            CycleLine("الراتب", CurrencyFormatter.formatAmount(c.basicSalary))
                            CycleLine("المسحوبات", CurrencyFormatter.formatAmount(c.withdrawals))
                            CycleLine("السلف", CurrencyFormatter.formatAmount(c.advances))
                            CycleLine("أقساط مسددة", CurrencyFormatter.formatAmount(c.installmentsPaid))
                            CycleLine("رصيد السلفة", CurrencyFormatter.formatAmount(c.advanceBalance))
                            CycleLine("الخصومات", CurrencyFormatter.formatAmount(c.deductions))
                            CycleLine(
                                "المتبقي",
                                CurrencyFormatter.formatAmount(c.remainingBalance),
                                valueColor = if (c.remainingBalance > 0) Color(0xFF1976D2) else AppColors.SuccessColor
                            )
                            if (c.carryOverToNext > 0) {
                                Text(
                                    "تجاوز ${CurrencyFormatter.formatAmount(c.carryOverToNext)} → يُرحّل للدورة القادمة",
                                    style = AppTypography.labelSmall, color = AppColors.DangerColor
                                )
                            }
                        }
                    }

                    // Dart last-6 transactions (l.260-354).
                    if (ent.transactions.isNotEmpty()) {
                        Text("آخر المعاملات", style = AppTypography.titleSmall, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
                        ent.transactions.take(6).forEach { t ->
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(
                                    "${t.type} • ${t.date.take(10)}" + (t.note.takeIf { it.isNotBlank() }?.let { " — $it" } ?: ""),
                                    style = AppTypography.labelSmall, color = AppColors.TextSecondary,
                                    maxLines = 1
                                )
                                Text(
                                    CurrencyFormatter.formatAmount(t.amount),
                                    style = AppTypography.labelSmall,
                                    color = when (t.type) {
                                        "سلفة" -> Color(0xFF3F51B5)
                                        "سحب" -> AppColors.WarningColor
                                        else -> AppColors.DangerColor
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CycleLine(label: String, value: String, valueColor: Color = AppColors.TextPrimary) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary)
        Text(value, style = AppTypography.labelSmall, fontWeight = FontWeight.SemiBold, color = valueColor)
    }
}
