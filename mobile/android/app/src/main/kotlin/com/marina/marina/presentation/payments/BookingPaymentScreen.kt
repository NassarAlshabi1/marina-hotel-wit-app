package com.marina.marina.presentation.payments

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.util.BookingFinancials
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.util.PdfExporter

/**
 * معالجة المدفوعات — 1:1 port of `booking_payment_screen.dart`:
 * PaymentSummaryCard + two tabs (دفعة جديدة / الإجراءات) with the full
 * action set: quick payments, auto-extension, extra-night payments,
 * extend-stay, checkout, early checkout + refund, cancel today payments,
 * debt creation, admin discount, account statement (WhatsApp + PDF).
 */
@Composable
fun BookingPaymentScreen(
    onBack: () -> Unit = {},
    onOpenPaymentHistory: () -> Unit = {},
    onOpenDebts: () -> Unit = {},
    isAdmin: Boolean = true,
    viewModel: BookingPaymentViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var selectedTab by remember { mutableStateOf(0) }
    var paymentDialogMethod by remember { mutableStateOf<String?>(null) }
    var paymentPresetAmount by remember { mutableStateOf<Double?>(null) }
    var paymentPresetNotes by remember { mutableStateOf<String?>(null) }
    var paymentIsPendingBalance by remember { mutableStateOf(false) }
    var showCheckoutConfirm by remember { mutableStateOf(false) }
    var showEarlyCheckout by remember { mutableStateOf(false) }
    var showCancelToday by remember { mutableStateOf(false) }
    var showCreateDebt by remember { mutableStateOf(false) }
    var showDiscount by remember { mutableStateOf(false) }
    var showExtendStay by remember { mutableStateOf(false) }
    var showStatement by remember { mutableStateOf(false) }
    var showInvoice by remember { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(Unit) { viewModel.setAdmin(isAdmin) }
    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.consumeMessage()
        }
    }
    // Dart: after a successful action, offer the WhatsApp confirmation message.
    LaunchedEffect(state.whatsappMessage) {
        state.whatsappMessage?.let { msg ->
            val phone = state.booking?.let { BookingFinancials.cleanAndFormatPhone(it.guestPhone) }
            if (phone.isNullOrBlank()) {
                viewModel.consumeMessage()
            } else {
                val send = snackbarHostState.showSnackbar(
                    message = "تم التسجيل — إرسال رسالة واتساب للنزيل؟",
                    actionLabel = "إرسال",
                    duration = SnackbarDuration.Short
                ) == SnackbarResult.ActionPerformed
                if (send) PdfExporter.openWhatsAppText(context, phone, msg)
                viewModel.consumeMessage()
            }
        }
    }
    LaunchedEffect(state.finished) {
        if (state.finished) onBack()
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("معالجة المدفوعات", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = onBack) { Text("رجوع", color = AppColors.PrimaryColor) }
                    },
                    actions = {
                        IconButton(onClick = onOpenPaymentHistory) {
                            Text("سجل", color = AppColors.PrimaryColor, fontSize = 12.sp)
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            }
        ) { padding ->
            when {
                state.isLoading -> Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center
                ) { CircularProgressIndicator() }

                state.booking == null -> Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center
                ) { Text("الحجز غير موجود", style = AppTypography.bodyLarge, color = AppColors.TextSecondary) }

                else -> Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        PaymentSummaryCard(state)
                        state.summary?.lastPayment?.let {
                            LastPaymentCard(it)
                        }
                        TabRow(selectedTabIndex = selectedTab) {
                            Tab(selected = selectedTab == 0, onClick = { selectedTab = 0 },
                                text = { Text("دفعة جديدة", fontSize = 13.sp) })
                            Tab(selected = selectedTab == 1, onClick = { selectedTab = 1 },
                                text = { Text("الإجراءات", fontSize = 13.sp) })
                        }
                        if (selectedTab == 0) {
                            NewPaymentTab(
                                state = state,
                                onPay = { method, preset, notes, pendingBalance ->
                                    paymentDialogMethod = method
                                    paymentPresetAmount = preset
                                    paymentPresetNotes = notes
                                    paymentIsPendingBalance = pendingBalance
                                }
                            )
                        } else {
                            ActionsTab(
                                state = state,
                                isAdmin = isAdmin,
                                onCheckout = { showCheckoutConfirm = true },
                                onEarlyCheckout = { showEarlyCheckout = true },
                                onCancelToday = { showCancelToday = true },
                                onCreateDebt = { showCreateDebt = true },
                                onDiscount = { showDiscount = true },
                                onStatement = { showStatement = true },
                                onInvoice = { showInvoice = true },
                                onPaymentHistory = onOpenPaymentHistory
                            )
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Dialogs
    // -------------------------------------------------------------------------

    paymentDialogMethod?.let { method ->
        PaymentDialog(
            title = if (paymentIsPendingBalance) "دفع نقدي — رصيد تراكمي" else "دفع $method",
            presetAmount = paymentPresetAmount,
            presetNotes = paymentPresetNotes,
            method = method,
            remaining = state.summary?.remainingAmount ?: 0.0,
            onDismiss = {
                paymentDialogMethod = null
                paymentPresetAmount = null
                paymentPresetNotes = null
                paymentIsPendingBalance = false
            },
            onConfirm = { amount, notes, ref ->
                viewModel.processPayment(
                    amount = amount,
                    method = method,
                    notes = notes ?: paymentPresetNotes,
                    isPendingBalance = paymentIsPendingBalance
                )
                paymentDialogMethod = null
                paymentPresetAmount = null
                paymentPresetNotes = null
                paymentIsPendingBalance = false
            }
        )
    }

    state.extensionProposal?.let { proposal ->
        AlertDialog(
            onDismissRequest = { viewModel.dismissExtensionProposal() },
            title = { Text("تسجيل دفعة مع تمديد") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("المتبقي الحالي: ${CurrencyFormatter.formatAmount(proposal.remaining)} ريال")
                    Text("الفائض: ${CurrencyFormatter.formatAmount(proposal.surplus)} ريال")
                    Text("سيتم إضافة: ${proposal.extraNights} ليلة/ليالي قادمة")
                    Text("سيتم تحديث تاريخ المغادرة وإضافة الليالي الجديدة", color = AppColors.TextSecondary)
                }
            },
            confirmButton = {
                TextButton(onClick = { viewModel.confirmExtensionAndPay("نقدي", null) }) {
                    Text("تأكيد التمديد والدفع", color = Color(0xFF3F51B5), fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissExtensionProposal() }) { Text("إلغاء") }
            }
        )
    }

    if (showCheckoutConfirm) {
        val summary = state.summary
        val nightsTotal = if (state.nights.isNotEmpty()) {
            state.nights.sumOf { if (it.finalRate > 0) it.finalRate else it.nightlyRate }
        } else summary?.totalAmount ?: 0.0
        val effectiveRemaining = ((nightsTotal) - (summary?.paidAmount ?: 0.0))
            .coerceIn(0.0, nightsTotal)
        AlertDialog(
            onDismissRequest = { showCheckoutConfirm = false },
            title = { Text(if (effectiveRemaining > 0) "تحذير!" else "تأكيد المغادرة") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (effectiveRemaining > 0) {
                        Text(
                            "المبلغ المتبقي: ${CurrencyFormatter.formatAmount(effectiveRemaining)}",
                            color = AppColors.DangerColor, fontWeight = FontWeight.Bold
                        )
                        Text("⚠️ سيتم خصم المبلغ من راتبكم", color = AppColors.WarningColor)
                    }
                    Text("هل تريد تسجيل مغادرة العميل وتحرير الغرفة؟")
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.completeCheckout()
                    showCheckoutConfirm = false
                }) {
                    Text(
                        if (effectiveRemaining > 0) "متابعة رغم ذلك" else "تأكيد المغادرة",
                        color = if (effectiveRemaining > 0) AppColors.DangerColor else AppColors.SuccessColor,
                        fontWeight = FontWeight.Bold
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { showCheckoutConfirm = false }) { Text("إلغاء") }
            }
        )
    }

    if (showEarlyCheckout) {
        val booking = state.booking
        val summary = state.summary
        val early = booking?.let {
            BookingFinancials.earlyCheckout(it, state.roomPrice, summary?.paidAmount ?: 0.0, state.nights)
        }
        if (early == null) {
            AlertDialog(
                onDismissRequest = { showEarlyCheckout = false },
                title = { Text("مغادرة مبكرة") },
                text = { Text("لا يوجد مغادرة مبكرة — الحجز انتهى أو لا يوجد تاريخ مغادرة مخطط") },
                confirmButton = {
                    TextButton(onClick = { showEarlyCheckout = false }) { Text("حسناً") }
                }
            )
        } else {
            AlertDialog(
                onDismissRequest = { showEarlyCheckout = false },
                title = { Text("مغادرة مبكرة / مردود") },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        DetailRow("الليالي المدفوعة", "${early.plannedNights}")
                        DetailRow("الليالي المستخدمة", "${early.actualNights}")
                        DetailRow("الليالي غير المستخدمة", "${early.unusedNights}", AppColors.WarningColor)
                        DetailRow("إجمالي المدفوع", "${CurrencyFormatter.formatAmount(summary?.paidAmount ?: 0.0)}")
                        DetailRow("تكلفة الليالي المستخدمة", "${CurrencyFormatter.formatAmount(early.actualNightsCost)}")
                        if (early.refundAmount > 0) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(AppColors.SuccessColor.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
                                    .padding(12.dp)
                            ) {
                                Text(
                                    "المبلغ المردود: ${CurrencyFormatter.formatAmount(early.refundAmount)}",
                                    color = AppColors.SuccessColor, fontWeight = FontWeight.Bold,
                                    modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center
                                )
                            }
                        } else {
                            Text(
                                "لا يوجد مردود — المدفوع يساوي تكلفة الليالي المستخدمة",
                                color = AppColors.WarningColor,
                                modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center
                            )
                        }
                    }
                },
                confirmButton = {
                    TextButton(onClick = {
                        viewModel.processEarlyCheckout(
                            early.refundAmount,
                            early.unusedNights.coerceAtLeast(0),
                            early.actualNights
                        )
                        showEarlyCheckout = false
                    }) {
                        Text(
                            if (early.refundAmount > 0) "تأكيد المغادرة والمردود" else "تأكيد المغادرة فقط",
                            color = if (early.refundAmount > 0) AppColors.SuccessColor else AppColors.WarningColor,
                            fontWeight = FontWeight.Bold
                        )
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showEarlyCheckout = false }) { Text("إلغاء") }
                }
            )
        }
    }

    if (showCancelToday) {
        val hotelDay = HotelTimeEngine.currentHotelDayKey()
        val todays = state.payments.filter {
            !it.isVoided && (it.hotelDayKey == hotelDay ||
                (it.hotelDayKey == null && it.paymentDate.startsWith(hotelDay)))
        }
        AlertDialog(
            onDismissRequest = { showCancelToday = false },
            title = { Text("إلغاء دفعة اليوم الفندقي") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (todays.isEmpty()) {
                        Text("لا توجد دفعات اليوم")
                    } else {
                        Text("اليوم الفندقي: $hotelDay")
                        Text("عدد الدفعات: ${todays.size}")
                        Text(
                            "إجمالي المبلغ المراد إلغاؤه: ${CurrencyFormatter.formatAmount(todays.sumOf { it.amount })}",
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            "⚠️ سيتم حذف دفعات اليوم الفندقي فقط. سجل خروج النزيل منفصل عبر زر 'تسجيل المغادرة'",
                            color = AppColors.WarningColor, fontSize = 12.sp
                        )
                    }
                }
            },
            confirmButton = {
                if (todays.isNotEmpty()) {
                    TextButton(onClick = {
                        viewModel.cancelTodayPayments()
                        showCancelToday = false
                    }) { Text("تأكيد إلغاء الدفعات", color = AppColors.DangerColor, fontWeight = FontWeight.Bold) }
                } else {
                    TextButton(onClick = { showCancelToday = false }) { Text("حسناً") }
                }
            },
            dismissButton = {
                TextButton(onClick = { showCancelToday = false }) { Text("إلغاء") }
            }
        )
    }

    if (showCreateDebt) {
        val remaining = state.summary?.remainingAmount ?: 0.0
        AlertDialog(
            onDismissRequest = { showCreateDebt = false },
            title = { Text("إنشاء دين بالمبلغ المتبقي") },
            text = {
                Text(
                    "سيتم إنشاء دين بقيمة ${CurrencyFormatter.formatAmount(remaining)} على النزيل " +
                        "${state.booking?.guestName ?: ""} (غرفة ${state.booking?.roomNumber ?: ""}) " +
                        "وإضافته تلقائياً إلى قائمة الديون."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.createDebtFromRemainingBalance()
                    showCreateDebt = false
                }) { Text("تأكيد", color = AppColors.WarningColor, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { showCreateDebt = false }) { Text("إلغاء") }
            }
        )
    }

    if (showDiscount) {
        var amountText by remember { mutableStateOf("") }
        val summary = state.summary
        AlertDialog(
            onDismissRequest = { showDiscount = false },
            title = { Text("خصم مبلغ من الليالي الفعلية") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    DetailRow("إجمالي الفاتورة", CurrencyFormatter.formatAmount(summary?.totalAmount ?: 0.0))
                    DetailRow("المدفوع", CurrencyFormatter.formatAmount(summary?.paidAmount ?: 0.0))
                    DetailRow("المتبقي", CurrencyFormatter.formatAmount(summary?.remainingAmount ?: 0.0))
                    if ((state.booking?.discount ?: 0.0) > 0) {
                        DetailRow("الخصم الحالي", CurrencyFormatter.formatAmount(state.booking?.discount ?: 0.0))
                    }
                    if (!isAdmin) {
                        Text("⚠️ صلاحية الخصم متاحة للمدير فقط", color = AppColors.WarningColor)
                    } else {
                        OutlinedTextField(
                            value = amountText,
                            onValueChange = { amountText = it.filter { c -> c.isDigit() || c == '.' } },
                            label = { Text("مبلغ الخصم") },
                            singleLine = true
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (isAdmin) {
                            CurrencyFormatter.parseAmount(amountText)?.let { viewModel.applyAdminDiscount(it) }
                        }
                        showDiscount = false
                    },
                    enabled = isAdmin
                ) { Text("تطبيق الخصم", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { showDiscount = false }) { Text("إلغاء") }
            }
        )
    }

    if (showExtendStay) {
        var nightsText by remember { mutableStateOf("1") }
        val rate = state.roomPrice
        val nights = nightsText.toIntOrNull() ?: 0
        val cost = nights * rate
        AlertDialog(
            onDismissRequest = { showExtendStay = false },
            title = { Text("تمديد الإقامة") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    DetailRow("سعر الليلة", CurrencyFormatter.formatAmount(rate))
                    OutlinedTextField(
                        value = nightsText,
                        onValueChange = { nightsText = it.filter { c -> c.isDigit() } },
                        label = { Text("عدد الليالي الإضافية") },
                        singleLine = true
                    )
                    DetailRow("التكلفة الإجمالية", CurrencyFormatter.formatAmount(cost))
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.extendStay(nights)
                    showExtendStay = false
                }) { Text("تمديد وتسجيل دفعة", color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { showExtendStay = false }) { Text("إلغاء") }
            }
        )
    }

    if (showStatement) {
        StatementDialog(
            state = state,
            onBuildStatement = { viewModel.buildAccountStatement() },
            onDismiss = { showStatement = false }
        )
    }

    if (showInvoice) {
        val booking = state.booking
        val summary = state.summary
        if (booking != null && summary != null) {
            LaunchedEffect(booking.id) {
                showInvoice = false
                val checkin = HotelTimeEngine.parseDate(booking.checkinDate)
                val checkout = HotelTimeEngine.parseDate(booking.actualCheckout ?: booking.checkoutDate)
                val nightsCount = if (checkin != null) HotelTimeEngine.nightsWithCutoff(checkin, checkout) else summary.nightsCount
                val file = PdfExporter.buildReport(
                    context = context,
                    reportTitle = "الفاتورة الشاملة",
                    periodText = "الغرفة: ${booking.roomNumber} • $nightsCount ليلة",
                    infoRows = listOf(
                        "النزيل" to booking.guestName,
                        "الهاتف" to (booking.guestPhone.ifBlank { "غير متوفر" }),
                        "الجنسية" to booking.guestNationality,
                        "الوصول" to (checkin?.let { HotelTimeEngine.formatDisplay(it) } ?: "—"),
                        "المغادرة" to (checkout?.let { HotelTimeEngine.formatDisplay(it) } ?: "—")
                    ),
                    stats = listOf(
                        Triple("الإجمالي", CurrencyFormatter.formatAmount(summary.totalAmount), 0xFF242476.toInt()),
                        Triple("المدفوع", CurrencyFormatter.formatAmount(summary.paidAmount), 0xFF2E7D5B.toInt()),
                        Triple("المتبقي", CurrencyFormatter.formatAmount(summary.remainingAmount), 0xFFE5484D.toInt())
                    ),
                    tables = listOf(
                        PdfExporter.PdfTable(
                            title = "تفاصيل الفاتورة",
                            headers = listOf("البيان", "الكمية", "السعر", "الإجمالي"),
                            rows = listOf(
                                listOf(
                                    "إقامة — غرفة ${booking.roomNumber}",
                                    "$nightsCount ليلة",
                                    "${CurrencyFormatter.formatAmount(state.roomPrice)} ريال",
                                    "${CurrencyFormatter.formatAmount(summary.totalAmount)} ريال"
                                )
                            ),
                            totalRow = listOf("الإجمالي", "", "", "${CurrencyFormatter.formatAmount(summary.totalAmount)} ريال")
                        ),
                        PdfExporter.PdfTable(
                            title = "سجل المدفوعات",
                            headers = listOf("التاريخ", "طريقة الدفع", "المبلغ"),
                            rows = state.payments.sortedBy { it.paymentDate }.map {
                                listOf(
                                    it.paymentDate.take(16).replace("T", " "),
                                    it.paymentMethod,
                                    "${CurrencyFormatter.formatAmount(it.amount)} ريال"
                                )
                            },
                            totalRow = listOf("الإجمالي المدفوع", "", "${CurrencyFormatter.formatAmount(summary.paidAmount)} ريال")
                        )
                    ),
                    fileName = PdfExporter.generateFileName("فاتورة-${booking.guestName}-${booking.roomNumber}")
                )
                PdfExporter.sharePdf(context, file, "فاتورة - ${booking.guestName} - غرفة ${booking.roomNumber}")
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Summary card — Dart PaymentSummaryCard (widgets/payment_summary_card.dart)
// ---------------------------------------------------------------------------

@Composable
private fun PaymentSummaryCard(state: BookingPaymentUiState) {
    val booking = state.booking ?: return
    val summary = state.summary ?: return
    val gradient = if (summary.isFullyPaid) {
        listOf(Color(0xFF2E7D5B), Color(0xFF1B5E40))
    } else {
        listOf(AppColors.PrimaryColor, AppColors.PrimaryDark)
    }
    Card(
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = Color.Transparent),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .background(Brush.verticalGradient(gradient), RoundedCornerShape(14.dp))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .background(Color.White.copy(alpha = 0.2f), CircleShape),
                        contentAlignment = Alignment.Center
                    ) { Text("غ${booking.roomNumber}", color = Color.White, fontWeight = FontWeight.Bold) }
                    Column {
                        Text(booking.guestName.ifBlank { "ضيف" }, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        if (booking.guestPhone.isNotBlank()) {
                            Text(booking.guestPhone, color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp)
                        }
                    }
                }
                Text(
                    if (summary.isFullyPaid) "مكتمل الدفع" else "دفع جزئي",
                    color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .background(Color.White.copy(alpha = 0.25f), RoundedCornerShape(20.dp))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                )
            }

            if (booking.guestIdNumber.isNotBlank()) {
                Text(
                    "${booking.guestIdType} • ${booking.guestIdNumber} • الجنسية: ${booking.guestNationality}",
                    color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp
                )
            }
            val checkin = HotelTimeEngine.parseDate(booking.checkinDate)
            val plannedCheckout = HotelTimeEngine.parseDate(booking.checkoutDate)
            Text(
                "الوصول: ${checkin?.let { HotelTimeEngine.formatDisplay(it) } ?: "—"}",
                color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp
            )
            Text(
                "المغادرة المخطط: ${plannedCheckout?.let { HotelTimeEngine.formatDisplay(it) } ?: "—"}",
                color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp
            )
            // Auto-checkout line (StayBalanceCalculator).
            state.stayBalance?.let { balance ->
                if (summary.paidAmount > 0 && summary.roomRate > 0 && balance.autoCheckoutMillis != null) {
                    val autoText = HotelTimeEngine.formatDisplayDateOnly(balance.autoCheckoutMillis!!)
                    val extra = if (balance.isAutoExtended) " (+تمديد تلقائي)" else ""
                    Text(
                        "المغادرة التلقائية: $autoText (${balance.totalPaidNights} ليلة مدفوعة)$extra",
                        color = Color(0xFFFFE082), fontSize = 11.sp
                    )
                }
            }
            booking.actualCheckout?.let {
                val actual = HotelTimeEngine.parseDate(it)
                Text(
                    "المغادرة الفعلي: ${actual?.let { d -> HotelTimeEngine.formatDisplay(d) } ?: "—"}",
                    color = Color(0xFF9EE6C0), fontSize = 11.sp
                )
            }

            // Chips row.
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                SummaryChip("سعر الليلة", CurrencyFormatter.formatAmount(summary.roomRate))
                SummaryChip("الليالي الفعلية", "${summary.nightsCount}", highlight = summary.nightsCount > summary.expectedNights)
                if (state.extraNightsBeyondExpected > 0) {
                    SummaryChip("+${state.extraNightsBeyondExpected} ليلة بعد 14:00", "", warning = true)
                }
                if (summary.hasDebt) {
                    SummaryChip("يوجد دين", CurrencyFormatter.formatAmount(summary.debtAmount), warning = true)
                }
                if (summary.totalDiscount > 0) {
                    SummaryChip("التخفيض", "-${CurrencyFormatter.formatAmount(summary.totalDiscount)}")
                }
                if (summary.nightsCount > 0) {
                    SummaryChip("ليالي عادية", "${summary.normalNights}")
                }
                if (summary.discountedNights > 0) {
                    SummaryChip("ليالي مخفضة: ${summary.discountedNights} (-${CurrencyFormatter.formatAmount(summary.totalDiscount)})", "")
                }
                if (summary.surchargeNights > 0) {
                    SummaryChip("ليالي مزادة: ${summary.surchargeNights} (+${CurrencyFormatter.formatAmount(summary.totalSurcharge)})", "")
                }
            }

            // Progress.
            if (summary.totalAmount > 0) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("تقدم الدفع", color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp)
                        Text("${"%.1f".format(summary.paidPercentage)}%", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                    LinearProgressIndicator(
                        progress = { (summary.paidPercentage / 100.0).coerceIn(0.0, 1.0).toFloat() },
                        modifier = Modifier.fillMaxWidth().height(8.dp),
                        color = Color(0xFF9EE6C0),
                        trackColor = Color.White.copy(alpha = 0.25f)
                    )
                }
            }

            // Amount chips.
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AmountChip("الإجمالي", CurrencyFormatter.formatAmount(summary.totalAmount), Color(0xFF64B5F6), Modifier.weight(1f))
                AmountChip("المدفوع", CurrencyFormatter.formatAmount(summary.paidAmount), Color(0xFF9EE6C0), Modifier.weight(1f))
                AmountChip("المتبقي", CurrencyFormatter.formatAmount(summary.remainingAmount), Color(0xFFFFB4A9), Modifier.weight(1f))
                AmountChip("مدفوع اليوم", CurrencyFormatter.formatAmount(summary.todayPaidAmount), Color(0xFFB39DDB), Modifier.weight(1f))
            }

            if (!summary.isFullyPaid) {
                OutlinedButton(
                    onClick = {},
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                    border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = 0.6f))
                ) {
                    Text("دفعة رصيد تراكمي تُسجَّل من تبويب دفعة جديدة", fontSize = 10.sp)
                }
            }
        }
    }
}

@Composable
private fun SummaryChip(label: String, value: String, highlight: Boolean = false, warning: Boolean = false) {
    val bg = when {
        warning -> Color(0xFFFFCDD2)
        highlight -> Color(0xFFFFECB3)
        else -> Color.White.copy(alpha = 0.18f)
    }
    val fg = when {
        warning -> Color(0xFFB71C1C)
        highlight -> Color(0xFF795548)
        else -> Color.White
    }
    Text(
        if (value.isBlank()) label else "$label: $value",
        color = fg, fontSize = 10.sp,
        modifier = Modifier
            .background(bg, RoundedCornerShape(20.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    )
}

@Composable
private fun AmountChip(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .background(Color.White.copy(alpha = 0.15f), RoundedCornerShape(10.dp))
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        Text(label, color = Color.White.copy(alpha = 0.8f), fontSize = 9.sp)
    }
}

@Composable
private fun LastPaymentCard(payment: com.marina.marina.domain.model.Payment) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF2E7D5B).copy(alpha = 0.12f), RoundedCornerShape(10.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("آخر مبلغ مدفوع", style = AppTypography.bodyMedium, color = AppColors.SuccessColor)
        Text(
            "${CurrencyFormatter.formatAmount(payment.amount)} ريال",
            style = AppTypography.titleMedium, fontWeight = FontWeight.Bold, color = AppColors.SuccessColor
        )
    }
}

// ---------------------------------------------------------------------------
// Tab 1 — New payment (Dart _buildNewPaymentTab l.706-913)
// ---------------------------------------------------------------------------

@Composable
private fun NewPaymentTab(
    state: BookingPaymentUiState,
    onPay: (method: String, presetAmount: Double?, presetNotes: String?, isPendingBalance: Boolean) -> Unit
) {
    val summary = state.summary ?: return
    if (summary.isFullyPaid) {
        Card(
            colors = CardDefaults.cardColors(containerColor = AppColors.SuccessColor.copy(alpha = 0.1f)),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(
                modifier = Modifier.padding(24.dp).fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text("تم سداد المبلغ كاملاً ✓", style = AppTypography.titleLarge, color = AppColors.SuccessColor, fontWeight = FontWeight.Bold)
                Text("يمكنك الآن تسجيل مغادرة العميل من تبويب الإجراءات", style = AppTypography.bodyMedium, color = AppColors.TextSecondary)
            }
        }
        return
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Method cards — Dart: only cash + transfer in a 2-column grid.
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            MethodCard(
                title = "نقدي", subtitle = "دفعة نقدية", icon = "💵",
                color = Color(0xFF2E7D5B),
                modifier = Modifier.weight(1f),
                onClick = { onPay("نقدي", null, null, false) }
            )
            MethodCard(
                title = "تحويل", subtitle = "تحويل بنكي", icon = "🏦",
                color = Color(0xFF5E35B1),
                modifier = Modifier.weight(1f),
                onClick = { onPay("تحويل", null, null, false) }
            )
        }

        // Quick payment row — 25/50/75/100% of remaining.
        val remainingRounded = kotlin.math.abs(summary.remainingAmount.toInt().toDouble())
        Text("دفع سريع", style = AppTypography.titleMedium, fontWeight = FontWeight.Bold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            listOf("25%" to 0.25, "50%" to 0.5, "75%" to 0.75, "100%" to 1.0).forEach { (label, fraction) ->
                val amount = (remainingRounded * fraction).toInt().toDouble()
                OutlinedButton(
                    onClick = { onPay("نقدي", amount, null, false) },
                    enabled = amount > 0,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = AppColors.PrimaryColor,
                        disabledContentColor = AppColors.TextSecondary.copy(alpha = 0.4f)
                    )
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(label, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                        Text(CurrencyFormatter.formatAmount(amount), fontSize = 9.sp)
                    }
                }
            }
        }

        // Pending balance entry (رصيد تراكمي).
        OutlinedButton(
            onClick = { onPay("نقدي", null, "رصيد تراكمي للنزيل", true) },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFF3F51B5))
        ) {
            Text("إضافة دفعة رصيد تراكمي", fontSize = 12.sp)
        }

        // Extended-stay options (Dart _buildExtendedStayPaymentOptions).
        if (state.extendedStayActive) {
            val extra = state.extraNightsBeyondExpected
            Card(
                colors = CardDefaults.cardColors(containerColor = AppColors.AccentSoft),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("ليالٍ إضافية بعد انتهاء الحجز", fontWeight = FontWeight.Bold, color = AppColors.WarningColor)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ExtraNightButton("دفع ليلة واحدة", 1, state.roomPrice, onPay)
                        if (extra >= 2) {
                            ExtraNightButton("دفع ليلتين", 2, state.roomPrice, onPay)
                        }
                    }
                    if (extra > 0) {
                        ExtraNightButton("دفع كل الإضافي ($extra)", extra, state.roomPrice, onPay)
                    }
                }
            }
        }
    }
}

@Composable
private fun ExtraNightButton(label: String, nights: Int, rate: Double, onPay: (String, Double?, String?, Boolean) -> Unit) {
    val note = if (nights == 1) "دفع ليلة إضافية واحدة" else "دفع $nights ليالي إضافية"
    OutlinedButton(
        onClick = { onPay("نقدي", nights * rate, note, false) },
        enabled = rate > 0,
        modifier = Modifier.height(40.dp),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = AppColors.WarningColor)
    ) {
        Text(label, fontSize = 11.sp)
    }
}

@Composable
private fun MethodCard(
    title: String,
    subtitle: String,
    icon: String,
    color: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Card(
        modifier = modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.12f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(icon, fontSize = 26.sp)
            Text(title, fontWeight = FontWeight.Bold, color = color)
            Text(subtitle, fontSize = 11.sp, color = AppColors.TextSecondary)
        }
    }
}

// ---------------------------------------------------------------------------
// Tab 2 — Actions (Dart ActionsTab widgets/actions_tab.dart)
// ---------------------------------------------------------------------------

@Composable
private fun ActionsTab(
    state: BookingPaymentUiState,
    isAdmin: Boolean,
    onCheckout: () -> Unit,
    onEarlyCheckout: () -> Unit,
    onCancelToday: () -> Unit,
    onCreateDebt: () -> Unit,
    onDiscount: () -> Unit,
    onStatement: () -> Unit,
    onInvoice: () -> Unit,
    onPaymentHistory: () -> Unit
) {
    val summary = state.summary ?: return
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // Conditional banner.
        if (summary.hasDebt || summary.remainingAmount > 0) {
            val bg = if (summary.hasDebt) AppColors.DangerColor.copy(alpha = 0.12f) else AppColors.WarningColor.copy(alpha = 0.12f)
            Row(
                modifier = Modifier.fillMaxWidth().background(bg, RoundedCornerShape(10.dp)).padding(12.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                if (summary.hasDebt) {
                    Text(
                        "دين سابق: ${CurrencyFormatter.formatAmount(summary.debtAmount)} • متبقي: ${CurrencyFormatter.formatAmount(summary.remainingAmount)}",
                        color = AppColors.DangerColor, fontSize = 12.sp, fontWeight = FontWeight.Bold
                    )
                } else {
                    Text(
                        "متبقي: ${CurrencyFormatter.formatAmount(summary.remainingAmount)}",
                        color = AppColors.WarningColor, fontSize = 12.sp, fontWeight = FontWeight.Bold
                    )
                }
            }
        }

        // Buttons row: create debt + discount.
        if (summary.remainingAmount > 0) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                Button(
                    onClick = onCreateDebt,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.WarningColor),
                    shape = RoundedCornerShape(10.dp)
                ) { Text("إنشاء دين", fontSize = 12.sp) }
                Button(
                    onClick = onDiscount,
                    modifier = Modifier.weight(1f),
                    enabled = isAdmin,
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.SuccessColor),
                    shape = RoundedCornerShape(10.dp)
                ) { Text(if (isAdmin) "خصم مبلغ" else "خصم (مقيد)", fontSize = 12.sp) }
            }
        }

        // 6 action cards.
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            ActionCard("عرض الفاتورة الشاملة", "فاتورة تفصيلية PDF", Color(0xFF00897B), Modifier.weight(1f), onInvoice)
            ActionCard("سجل المدفوعات", "كل دفعات الحجز", Color(0xFF5E35B1), Modifier.weight(1f), onPaymentHistory)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            ActionCard(
                "تسجيل المغادرة",
                if ((summary.remainingAmount) > 0) "تحذير: يوجد مبلغ متبقي!" else "إنهاء الإقامة وتحرير الغرفة",
                if ((summary.remainingAmount) > 0) AppColors.DangerColor else AppColors.SuccessColor,
                Modifier.weight(1f), onCheckout
            )
            ActionCard("مغادرة مبكرة / مردود", "رد قيمة الليالي غير المستخدمة", Color(0xFFFFB300), Modifier.weight(1f), onEarlyCheckout)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            ActionCard("إلغاء يوم إضافي", "حذف دفعات اليوم الفندقي", AppColors.DangerColor, Modifier.weight(1f), onCancelToday)
            ActionCard("إرسال كشف حساب", "واتساب أو PDF", Color(0xFFEF6C00), Modifier.weight(1f), onStatement)
        }

        // Booking info footer.
        val booking = state.booking
        Card(
            colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
            shape = RoundedCornerShape(12.dp)
        ) {
            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("معلومات الحجز", fontWeight = FontWeight.Bold, color = AppColors.PrimaryColor)
                Text("المعرّف: ${booking?.localUuid?.take(8) ?: "—"}", fontSize = 11.sp, color = AppColors.TextSecondary)
                Text("الحالة: ${booking?.status ?: "—"}", fontSize = 11.sp, color = AppColors.TextSecondary)
                booking?.notes?.let { if (it.isNotBlank()) Text("ملاحظات: $it", fontSize = 11.sp, color = AppColors.TextSecondary) }
            }
        }
    }
}

@Composable
private fun ActionCard(title: String, subtitle: String, color: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Card(
        modifier = modifier.clickable(onClick = onClick).height(76.dp),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.1f))
    ) {
        Column(
            modifier = Modifier.padding(10.dp).fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(title, fontWeight = FontWeight.Bold, color = color, fontSize = 11.sp, textAlign = TextAlign.Center)
            Text(subtitle, fontSize = 9.sp, color = AppColors.TextSecondary, textAlign = TextAlign.Center, maxLines = 2)
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String, valueColor: Color = AppColors.TextPrimary) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = AppTypography.bodySmall, color = AppColors.TextSecondary)
        Text(value, style = AppTypography.bodySmall, color = valueColor, fontWeight = FontWeight.SemiBold)
    }
}

// ---------------------------------------------------------------------------
// Payment dialog — Dart _showPaymentDialog (l.992-1125)
// ---------------------------------------------------------------------------

@Composable
private fun PaymentDialog(
    title: String,
    method: String,
    presetAmount: Double?,
    presetNotes: String?,
    remaining: Double,
    onDismiss: () -> Unit,
    onConfirm: (amount: Double, notes: String?, reference: String?) -> Unit
) {
    var amount by remember { mutableStateOf(presetAmount?.let { it.toInt().toString() } ?: "") }
    var notes by remember { mutableStateOf(presetNotes ?: "") }
    var reference by remember { mutableStateOf("") }
    var cardLast4 by remember { mutableStateOf("") }
    var bank by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (remaining > 0 && presetAmount == null) {
                    Text("المتبقي: ${CurrencyFormatter.formatAmount(remaining)} ريال", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
                }
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { c -> c.isDigit() } },
                    label = { Text("المبلغ *") },
                    prefix = { Text("ر.ي ") },
                    singleLine = true
                )
                if (method == "بطاقة") {
                    OutlinedTextField(
                        value = cardLast4,
                        onValueChange = { if (it.length <= 4) cardLast4 = it.filter { c -> c.isDigit() } },
                        label = { Text("آخر 4 أرقام من البطاقة") },
                        singleLine = true
                    )
                }
                if (method == "تحويل") {
                    OutlinedTextField(
                        value = bank,
                        onValueChange = { bank = it },
                        label = { Text("اسم البنك") },
                        singleLine = true
                    )
                }
                if (method == "تحويل" || method == "شيك") {
                    OutlinedTextField(
                        value = reference,
                        onValueChange = { reference = it },
                        label = { Text("رقم المرجع/الشيك") },
                        singleLine = true
                    )
                }
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("ملاحظات (اختياري)") },
                    singleLine = true
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val value = CurrencyFormatter.parseAmount(amount)
                    if (value != null && value > 0) {
                        onConfirm(value, notes.ifBlank { null }, reference.ifBlank { null })
                    }
                }
            ) { Text("تسجيل الدفعة", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

// ---------------------------------------------------------------------------
// Statement dialog — Dart _sendAccountStatement (l.3007-3224)
// ---------------------------------------------------------------------------

@Composable
private fun StatementDialog(
    state: BookingPaymentUiState,
    onBuildStatement: () -> String?,
    onDismiss: () -> Unit
) {
    val booking = state.booking ?: return onDismiss()
    val summary = state.summary ?: return onDismiss()
    val context = LocalContext.current
    var message by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("إرسال كشف حساب") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                DetailRow("العميل", booking.guestName)
                DetailRow("الغرفة", booking.roomNumber)
                DetailRow("الهاتف", booking.guestPhone.ifBlank { "غير متوفر" })
                DetailRow("الإجمالي", CurrencyFormatter.formatAmount(summary.totalAmount))
                DetailRow("المدفوع", CurrencyFormatter.formatAmount(summary.paidAmount))
                DetailRow(
                    "المتبقي", CurrencyFormatter.formatAmount(summary.remainingAmount),
                    if (summary.remainingAmount > 0) AppColors.DangerColor else AppColors.SuccessColor
                )
                HorizontalDivider(color = AppColors.DividerColor)
                Text("سجل المدفوعات (${state.payments.size})", fontWeight = FontWeight.Bold, fontSize = 12.sp)
                state.payments.sortedBy { it.paymentDate }.take(6).forEach { p ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(
                            "${p.paymentMethod} • ${p.paymentDate.take(10)}",
                            fontSize = 10.sp, color = AppColors.TextSecondary
                        )
                        Text("${CurrencyFormatter.formatAmount(p.amount)} ريال", fontSize = 10.sp)
                    }
                }
                if (state.payments.size > 6) {
                    Text("... و${state.payments.size - 6} دفعات أخرى", fontSize = 10.sp, color = AppColors.TextSecondary)
                }
                if (message != null) {
                    Text(
                        "${message!!.length}/1000 حرف",
                        fontSize = 10.sp,
                        color = if (message!!.length > 1000) AppColors.DangerColor else if (message!!.length > 900) AppColors.WarningColor else AppColors.TextSecondary
                    )
                }
            }
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = {
                    val msg = message ?: onBuildStatement().also { message = it }
                    val phone = BookingFinancials.cleanAndFormatPhone(booking.guestPhone)
                    PdfExporter.openWhatsAppText(context, phone, msg ?: "")
                }) { Text("إرسال كنص", color = AppColors.SuccessColor, fontWeight = FontWeight.Bold) }
                TextButton(onClick = {
                    val msg = message ?: onBuildStatement().also { message = it }
                    PdfExporter.shareText(context, msg ?: "", "كشف حساب - ${booking.guestName}")
                }) { Text("مشاركة", color = Color(0xFFEF6C00)) }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

