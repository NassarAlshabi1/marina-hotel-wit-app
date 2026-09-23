package com.marina.marina.presentation.debts

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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateDebtFromBookingScreen(
    viewModel: CreateDebtFromBookingViewModel = hiltViewModel(),
    bookingId: Long = 0L,
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()
    // Dart l.343-345 — the amount field is prefilled with the computed remaining.
    var amount by remember(state.computation) {
        mutableStateOf(state.computation?.remaining?.toInt()?.toString() ?: "")
    }
    var notes by remember { mutableStateOf("") }

    LaunchedEffect(bookingId) { viewModel.load(bookingId) }
    LaunchedEffect(state.saved) { if (state.saved) onSaved() }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("إنشاء دين من حجز", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            }
        ) { padding ->
            if (state.isLoading) {
                Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(16.dp)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    state.error?.let {
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.DangerColor.copy(alpha = 0.1f)),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Text(it, color = AppColors.DangerColor, modifier = Modifier.padding(12.dp), style = AppTypography.bodyMedium)
                        }
                    }

                    // Dart booking selector (l.101-169) — "N - guest".
                    if (state.selectableBookings.isNotEmpty()) {
                        var expanded by remember { mutableStateOf(false) }
                        val selectedLabel = state.selectedBooking?.let { "${it.roomNumber} - ${it.guestName}" } ?: "اختر حجزاً"
                        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                            OutlinedTextField(
                                value = selectedLabel,
                                onValueChange = {},
                                readOnly = true,
                                modifier = Modifier.fillMaxWidth().menuAnchor(),
                                label = { Text("الحجز") },
                                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) }
                            )
                            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                                state.selectableBookings.forEach { b ->
                                    DropdownMenuItem(
                                        text = { Text("${b.roomNumber} - ${b.guestName}") },
                                        onClick = {
                                            viewModel.selectBooking(b.id)
                                            expanded = false
                                        }
                                    )
                                }
                            }
                        }
                    } else {
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.WarningColor.copy(alpha = 0.1f)),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Text(
                                "لا توجد حجوزات نشطة",
                                modifier = Modifier.padding(12.dp),
                                style = AppTypography.bodyMedium,
                                color = AppColors.WarningColor
                            )
                        }
                    }

                    // Dart booking info card (l.171-207).
                    state.selectedBooking?.let { booking ->
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                            shape = RoundedCornerShape(12.dp),
                            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
                        ) {
                            Column(
                                modifier = Modifier.padding(14.dp).fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Text("بيانات الحجز", style = AppTypography.titleMedium, fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
                                InfoLine("الغرفة", booking.roomNumber)
                                InfoLine("النزيل", booking.guestName)
                                if (booking.guestIdNumber.isNotBlank()) InfoLine("رقم الهوية", booking.guestIdNumber)
                                InfoLine("الوصول", booking.checkinDate.take(10))
                                InfoLine("المغادرة المخططة", booking.checkoutDate?.take(10) ?: "—")
                                InfoLine("الحالة", booking.status)
                                InfoLine("الإجمالي", CurrencyFormatter.formatAmount(booking.totalDueCached))
                                InfoLine("المدفوع", CurrencyFormatter.formatAmount(booking.totalPaidCached))
                                InfoLine("المتبقي", CurrencyFormatter.formatAmount(booking.remainingBalanceCached))
                            }
                        }
                    }

                    // Dart debt period pickers (l.231-293).
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = state.fromDate,
                            onValueChange = { viewModel.setPeriod(it, state.toDate) },
                            label = { Text("من (yyyy-MM-dd)") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = state.toDate,
                            onValueChange = { viewModel.setPeriod(state.fromDate, it) },
                            label = { Text("إلى (yyyy-MM-dd)") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                    }

                    // Dart compute button (l.295-350).
                    Button(
                        onClick = { viewModel.computeDebt() },
                        enabled = !state.isComputing && state.selectedBooking != null &&
                            state.fromDate.isNotBlank() && state.toDate.isNotBlank(),
                        modifier = Modifier.fillMaxWidth().height(48.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryColor),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text(if (state.isComputing) "جاري الحساب..." else "احسب الدين", color = Color.White, fontWeight = FontWeight.Bold)
                    }

                    // Dart summary card (l.352-382).
                    state.computation?.let { c ->
                        Card(
                            colors = CardDefaults.cardColors(containerColor = AppColors.InfoColor.copy(alpha = 0.08f)),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Column(
                                modifier = Modifier.padding(14.dp).fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Text("ملخص الدين المحسوب", style = AppTypography.titleMedium, fontWeight = FontWeight.Bold, color = AppColors.InfoColor)
                                InfoLine("عدد الليالي", "${c.nights}")
                                InfoLine("سعر الليلة", CurrencyFormatter.formatAmount(c.nightlyRate))
                                InfoLine("إجمالي الفترة", CurrencyFormatter.formatAmount(c.total))
                                InfoLine("المدفوع", CurrencyFormatter.formatAmount(c.paid))
                                InfoLine(
                                    "المتبقي (المقترح)",
                                    CurrencyFormatter.formatAmount(c.remaining),
                                    if (c.remaining > 0) AppColors.DangerColor else AppColors.SuccessColor
                                )
                            }
                        }
                    }

                    OutlinedTextField(
                        value = amount,
                        onValueChange = { amount = it.filter { ch -> ch.isDigit() } },
                        label = { Text("مبلغ الدين (ريال) *") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                    )

                    OutlinedTextField(
                        value = notes,
                        onValueChange = { notes = it },
                        label = { Text("ملاحظات") },
                        minLines = 3
                    )

                    Button(
                        onClick = { viewModel.saveDebt(amount.toDoubleOrNull() ?: 0.0, notes) },
                        enabled = !state.isSaving && (amount.toDoubleOrNull() ?: 0.0) > 0,
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryColor),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text(
                            if (state.isSaving) "جاري الإنشاء..." else "حفظ الدين",
                            color = Color.White, fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun InfoLine(label: String, value: String, valueColor: Color = AppColors.TextPrimary) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = AppTypography.bodySmall, color = AppColors.TextSecondary)
        Text(value, style = AppTypography.bodySmall, fontWeight = FontWeight.SemiBold, color = valueColor)
    }
}
