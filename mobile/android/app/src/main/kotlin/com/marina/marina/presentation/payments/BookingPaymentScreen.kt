package com.marina.marina.presentation.payments

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Discount
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoneyOff
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.ReceiptLong
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.TaskAlt
import androidx.compose.material.icons.filled.TrendingDown
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material.icons.filled.Update
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material.icons.filled.CurrencyExchange
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.util.BookingFinancials
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import com.marina.marina.util.PdfExporter
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// ─── Dart palette (booking_payment_screen.dart + payment_summary_card.dart) ───
private val GreenPrimary = Color(0xFF4CAF50)
private val Green50 = Color(0xFFE8F5E9)
private val Green100 = Color(0xFFC8E6C9)
private val Green200 = Color(0xFFA5D6A7)
private val Green300 = Color(0xFF81C784)
private val Green800 = Color(0xFF2E7D32)
private val BluePrimary = Color(0xFF2196F3)
private val Blue50 = Color(0xFFE3F2FD)
private val Blue100 = Color(0xFFBBDEFB)
private val Blue200 = Color(0xFF90CAF9)
private val OrangePrimary = Color(0xFFFF9800)
private val Orange50 = Color(0xFFFFF3E0)
private val Orange100 = Color(0xFFFFE0B2)
private val Orange300 = Color(0xFFFFB74D)
private val Orange400 = Color(0xFFFFA726)
private val Orange700 = Color(0xFFF57C00)
private val Orange800 = Color(0xFFEF6C00)
private val RedPrimary = Color(0xFFF44336)
private val Red50 = Color(0xFFFFEBEE)
private val Red100 = Color(0xFFFFCDD2)
private val Red200 = Color(0xFFEF9A9A)
private val Red300 = Color(0xFFE57373)
private val Red700 = Color(0xFFD32F2F)
private val Red900 = Color(0xFFB71C1C)
private val Amber700 = Color(0xFFFFA000)
private val PurplePrimary = Color(0xFF9C27B0)
private val TealPrimary = Color(0xFF009688)
private val Teal700 = Color(0xFF00796B)
private val IndigoPrimary = Color(0xFF3F51B5)
private val BlueGrey = Color(0xFF607D8B)
private val Grey300 = Color(0xFFE0E0E0)
private val Grey50 = Color(0xFFFAFAFA)
private val Grey100 = Color(0xFFF5F5F5)
private val Grey600 = Color(0xFF757575)
private val Grey700 = Color(0xFF616161)

/** طلب فتح حوار الدفع (Dart `_showPaymentDialog` arguments). */
private data class PayDialogRequest(
    val method: PayMethodUi,
    val presetAmount: Double?,
    val presetNotes: String?,
    val isPendingBalance: Boolean
)

/**
 * معالجة المدفوعات — نقل 1:1 لـ booking_payment_screen.dart
 * (فرع feat/cloudflare-sync-execution):
 *
 *  • PaymentSummaryCard (بطاقة الملخص الملوّنة) + بطاقة «آخر مبلغ مدفوع».
 *  • تبويب «دفعة جديدة»: بطاقتا نقدي/تحويل + دفعات سريعة 25/50/75/100%.
 *  • تبويب «الإجراءات» (ActionsTab): 6 بطاقات إجراءات + شريط المتبقي/الدين +
 *    إنشاء دين + خصم المدير + معلومات الحجز.
 *  • حوارات: الدفع، التمديد التلقائي، تأكيد المغادرة، المغادرة المبكرة
 *    والمردود، إلغاء دفعة اليوم الفندقي، كشف الحساب (جدول + معاينة WhatsApp).
 */
@OptIn(ExperimentalMaterial3Api::class)
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
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    var snackbarTone by remember { mutableStateOf(MsgTone.INFO) }

    var selectedTab by remember { mutableIntStateOf(0) }
    var payRequest by remember { mutableStateOf<PayDialogRequest?>(null) }
    var showCheckoutConfirm by remember { mutableStateOf(false) }
    var showEarlyCheckout by remember { mutableStateOf(false) }
    var showCancelToday by remember { mutableStateOf(false) }
    var showCreateDebt by remember { mutableStateOf(false) }
    var showDiscount by remember { mutableStateOf(false) }
    var showStatement by remember { mutableStateOf(false) }
    var showInvoice by remember { mutableStateOf(false) }
    var showSavingBlock by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.setAdmin(isAdmin) }

    // سناك-بار النتائج — ألوان Dart (أخضر/أحمر/برتقالي) + إجراء اختياري.
    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message ?: return@LaunchedEffect
        snackbarTone = state.tone
        val result = snackbarHostState.showSnackbar(
            message = msg,
            actionLabel = state.action,
            duration = if (state.action != null) SnackbarDuration.Long else SnackbarDuration.Short
        )
        if (result == SnackbarResult.ActionPerformed && state.action == "عرض الديون") {
            onOpenDebts()
        }
        viewModel.consumeMessage()
    }

    // Dart يرسل واتساب تلقائياً؛ لا خدمة واتساب في Kotlin — يُعرض كإجراء سناك-بار.
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
    LaunchedEffect(state.finished) { if (state.finished) onBack() }

    // Dart PopScope(canPop: !_isSaving) — منع الرجوع أثناء الحفظ.
    BackHandler(enabled = state.isSaving) { showSavingBlock = true }

    // Dart `_showEarlyCheckoutDialog` guards (l.2041-2074): snackbars بدل الحوار.
    fun guardEarlyCheckout() {
        val booking = state.booking ?: return
        val early = BookingFinancials.earlyCheckout(
            booking, state.roomPrice, state.summary?.paidAmount ?: 0.0, state.nights
        )
        when {
            early == null -> {
                snackbarTone = MsgTone.INFO
                scope.launch {
                    snackbarHostState.showSnackbar(
                        "لا يوجد مغادرة مبكرة — الحجز انتهى أو لا يوجد تاريخ مغادرة مخطط"
                    )
                }
            }
            early.unusedNights <= 0 -> {
                snackbarTone = MsgTone.INFO
                scope.launch { snackbarHostState.showSnackbar("لا توجد ليالي غير مستخدمة للرد") }
            }
            else -> showEarlyCheckout = true
        }
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { PaymentSnackbarHost(snackbarHostState, snackbarTone) },
            topBar = {
                TopAppBar(
                    title = { Text("معالجة المدفوعات", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "رجوع")
                        }
                    },
                    // Dart actions: IconButton(Icons.history, tooltip: 'سجل المدفوعات').
                    actions = {
                        IconButton(onClick = onOpenPaymentHistory) {
                            Icon(Icons.Filled.History, contentDescription = "سجل المدفوعات")
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

                HotelTimeEngine.parseDate(state.booking!!.checkinDate) == null -> Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center
                ) { Text("خطأ: تاريخ الوصول للحجز غير صالح.") }

                else -> {
                    val booking = state.booking!!
                    Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                        PaymentSummaryCard(
                            state = state,
                            onAddBalancePayment = {
                                payRequest = PayDialogRequest(
                                    PayMethodUi.CASH, null, "رصيد تراكمي للنزيل", true
                                )
                            }
                        )
                        state.summary?.lastPayment?.let { LastPaymentCard(it) }
                        Spacer(Modifier.height(8.dp))
                        // شريط التبويبات الدائري (Dart l.539-561).
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp)
                                .background(
                                    androidx.compose.material3.MaterialTheme.colorScheme.surfaceVariant,
                                    RoundedCornerShape(25.dp)
                                )
                        ) {
                            TabRow(
                                selectedTabIndex = selectedTab,
                                containerColor = Color.Transparent,
                                indicator = { positions ->
                                    if (selectedTab < positions.size) {
                                        Box(
                                            Modifier
                                                .tabIndicatorOffset(positions[selectedTab])
                                                .fillMaxHeight()
                                                .padding(4.dp)
                                                .background(
                                                    androidx.compose.material3.MaterialTheme.colorScheme.primary,
                                                    RoundedCornerShape(25.dp)
                                                )
                                        )
                                    }
                                },
                                divider = {}
                            ) {
                                Tab(
                                    selected = selectedTab == 0,
                                    onClick = { selectedTab = 0 },
                                    text = { Text("دفعة جديدة", fontSize = 13.sp) }
                                )
                                Tab(
                                    selected = selectedTab == 1,
                                    onClick = { selectedTab = 1 },
                                    text = { Text("الإجراءات", fontSize = 13.sp) }
                                )
                            }
                        }
                        Box(modifier = Modifier.weight(1f)) {
                            when (selectedTab) {
                                0 -> NewPaymentTab(
                                    state = state,
                                    onPay = { method, preset, notes ->
                                        payRequest = PayDialogRequest(method, preset, notes, false)
                                    }
                                )
                                1 -> ActionsTab(
                                    state = state,
                                    isAdmin = isAdmin,
                                    onCheckout = { showCheckoutConfirm = true },
                                    onEarlyCheckout = { guardEarlyCheckout() },
                                    onCancelToday = { showCancelToday = true },
                                    onCreateDebt = { showCreateDebt = true },
                                    onDiscount = {
                                        if (isAdmin) {
                                            showDiscount = true
                                        } else {
                                            snackbarTone = MsgTone.ERROR
                                            scope.launch {
                                                snackbarHostState.showSnackbar(
                                                    "⚠️ صلاحية الخصم متاحة للمدير فقط"
                                                )
                                            }
                                        }
                                    },
                                    onStatement = {
                                        if (booking.guestPhone.isBlank()) {
                                            snackbarTone = MsgTone.ERROR
                                            scope.launch {
                                                snackbarHostState.showSnackbar("لا يوجد رقم هاتف للعميل")
                                            }
                                        } else {
                                            showStatement = true
                                        }
                                    },
                                    onInvoice = { showInvoice = true },
                                    onPaymentHistory = onOpenPaymentHistory
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // الحوارات
    // -------------------------------------------------------------------------

    payRequest?.let { request ->
        PaymentDialog(
            request = request,
            isSaving = state.isSaving,
            onDismiss = { payRequest = null },
            onConfirm = { amount, notes ->
                viewModel.processPayment(
                    amount = amount,
                    method = request.method.db,
                    notes = notes,
                    isPendingBalance = request.isPendingBalance
                )
                payRequest = null
            }
        )
    }

    state.receipt?.let { receipt ->
        ReceiptDialog(
            receipt = receipt,
            onDismiss = { viewModel.consumeReceipt() },
            onPrint = {
                viewModel.consumeReceipt()
                try {
                    PdfExporter.buildReport(
                        context = context,
                        reportTitle = "إيصال استلام",
                        periodText = "REC${System.currentTimeMillis()}",
                        infoRows = listOf(
                            "المبلغ" to "${CurrencyFormatter.formatAmount(receipt.amount)} ريال",
                            "طريقة الدفع" to receipt.methodLabel,
                            "المتبقي" to CurrencyFormatter.formatAmount(receipt.remaining)
                        ),
                        stats = emptyList(),
                        tables = emptyList(),
                        fileName = PdfExporter.generateFileName("إيصال استلام")
                    )
                    // Dart `receipt.generatePDF()` يشارك الملف بعد التوليد.
                    // buildReport يعيد الملف — مشاركته عبر sheet النظام.
                } catch (_: Exception) {
                }
            }
        )
    }

    state.extensionProposal?.let { proposal ->
        // Dart l.1615-1706: حوار تسجيل دفعة مع تمديد.
        AlertDialog(
            onDismissRequest = { viewModel.dismissExtensionProposal() },
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Update, null, tint = IndigoPrimary)
                    Spacer(Modifier.width(8.dp))
                    Text("تسجيل دفعة مع تمديد")
                }
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("المبلغ يتجاوز المتبقي. سيتم تمديد الحجز تلقائياً:")
                    Spacer(Modifier.height(12.dp))
                    Text("المبلغ المتبقي الحالي: ${CurrencyFormatter.formatAmount(proposal.remaining)}")
                    Text("المبلغ الفائض: ${CurrencyFormatter.formatAmount(proposal.surplus)}")
                    Text(
                        "سيتم إضافة: ${proposal.extraNights} " +
                            "${if (proposal.extraNights == 1) "ليلة" else "ليالي"} قادمة",
                        fontWeight = FontWeight.Bold,
                        color = IndigoPrimary
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "سيتم تحديث تاريخ المغادرة وإضافة الليالي الجديدة",
                        color = Color(0xFF9E9E9E),
                        fontSize = 12.sp
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = { viewModel.confirmExtensionAndPay("نقدي") },
                    colors = ButtonDefaults.buttonColors(containerColor = IndigoPrimary)
                ) { Text("تأكيد التمديد والدفع", color = Color.White) }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissExtensionProposal() }) { Text("إلغاء") }
            }
        )
    }

    if (showSavingBlock) {
        // Dart PopScope dialog: 'جاري الحفظ'.
        AlertDialog(
            onDismissRequest = {},
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(12.dp))
                    Text("جاري الحفظ")
                }
            },
            text = { Text("يرجى الانتظار حتى يتم حفظ الدفعة...") },
            confirmButton = {}
        )
    }

    if (showCheckoutConfirm) {
        CheckoutConfirmDialog(
            state = state,
            onDismiss = { showCheckoutConfirm = false },
            onConfirm = {
                viewModel.completeCheckout()
                showCheckoutConfirm = false
            }
        )
    }

    if (showEarlyCheckout) {
        EarlyCheckoutDialog(
            state = state,
            onDismiss = { showEarlyCheckout = false },
            onConfirmRefund = { refund, unused, actual ->
                viewModel.processEarlyCheckout(refund, unused, actual)
                showEarlyCheckout = false
            },
            onCheckoutOnly = {
                viewModel.completeCheckout()
                showEarlyCheckout = false
            }
        )
    }

    if (showCancelToday) {
        CancelTodayDialog(
            state = state,
            onDismiss = { showCancelToday = false },
            onConfirm = {
                viewModel.cancelTodayPayments()
                showCancelToday = false
            }
        )
    }

    if (showCreateDebt) {
        val remaining = state.summary?.remainingAmount ?: 0.0
        if (remaining > 0) {
            AlertDialog(
                onDismissRequest = { showCreateDebt = false },
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.AddCircle, null, tint = OrangePrimary)
                        Spacer(Modifier.width(8.dp))
                        Text("إنشاء دين بالمبلغ المتبقي")
                    }
                },
                text = {
                    Text(
                        "سيتم إنشاء دين بقيمة ${CurrencyFormatter.formatAmount(remaining)} " +
                            "للنزيل ${state.booking?.guestName ?: ""} (غرفة ${state.booking?.roomNumber ?: ""}).\n\n" +
                            "الدين سيُضاف تلقائياً إلى قائمة الديون ويمكن متابعته " +
                            "وسداد لاحقاً.\n\nهل تريد المتابعة؟"
                    )
                },
                confirmButton = {
                    Button(
                        onClick = {
                            viewModel.createDebtFromRemainingBalance()
                            showCreateDebt = false
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = OrangePrimary)
                    ) { Text("إنشاء الدين", color = Color.White) }
                },
                dismissButton = {
                    TextButton(onClick = { showCreateDebt = false }) { Text("إلغاء") }
                }
            )
        } else {
            showCreateDebt = false
        }
    }

    if (showDiscount) {
        DiscountDialog(
            state = state,
            onDismiss = { showDiscount = false },
            onApply = {
                viewModel.applyAdminDiscount(it)
                showDiscount = false
            }
        )
    }

    if (showStatement) {
        StatementDialog(
            state = state,
            onBuildStatement = { viewModel.buildAccountStatement() },
            onShareText = { message ->
                val phone = BookingFinancials.cleanAndFormatPhone(state.booking?.guestPhone ?: "")
                PdfExporter.openWhatsAppText(context, phone.ifBlank { null }, message)
            },
            onSharePdf = {
                val booking = state.booking ?: return@StatementDialog
                val summary = state.summary ?: return@StatementDialog
                try {
                    val file = PdfExporter.buildReport(
                        context = context,
                        reportTitle = "كشف حساب",
                        periodText = "الغرفة ${booking.roomNumber} • ${booking.guestName}",
                        infoRows = listOf(
                            "العميل" to booking.guestName,
                            "الهاتف" to booking.guestPhone.ifBlank { "غير متوفر" },
                            "الوصول" to booking.checkinDate.take(10),
                            "المغادرة" to (booking.actualCheckout?.take(10)
                                ?: booking.checkoutDate?.take(10) ?: "—"),
                            "عدد الليالي" to "${summary.nightsCount}"
                        ),
                        stats = listOf(
                            Triple("الإجمالي", CurrencyFormatter.formatAmount(summary.totalAmount), 0xFF242476.toInt()),
                            Triple("المدفوع", CurrencyFormatter.formatAmount(summary.paidAmount), 0xFF2E7D32.toInt()),
                            Triple(
                                "المتبقي", CurrencyFormatter.formatAmount(summary.remainingAmount),
                                if (summary.remainingAmount > 0) 0xFFC62828.toInt() else 0xFF2E7D32.toInt()
                            )
                        ),
                        tables = listOf(
                            PdfExporter.PdfTable(
                                title = "سجل المدفوعات (${state.payments.size})",
                                headers = listOf("التاريخ", "الطريقة", "المبلغ"),
                                rows = state.payments.sortedBy { it.paymentDate }.map { p ->
                                    listOf(
                                        p.paymentDate.take(10),
                                        p.paymentMethod,
                                        CurrencyFormatter.formatAmount(p.amount)
                                    )
                                },
                                totalRow = listOf("", "الإجمالي", CurrencyFormatter.formatAmount(summary.paidAmount))
                            )
                        ),
                        fileName = PdfExporter.generateFileName("كشف_حساب_${booking.guestName}_${booking.roomNumber}")
                    )
                    PdfExporter.sharePdf(
                        context, file,
                        "كشف حساب - ${booking.guestName} - غرفة ${booking.roomNumber}"
                    )
                } catch (_: Exception) {
                }
            },
            onDismiss = { showStatement = false }
        )
    }

    if (showInvoice) {
        val booking = state.booking
        val summary = state.summary
        if (booking != null && summary != null) {
            LaunchedEffect(booking.id) {
                showInvoice = false
                try {
                    val checkin = HotelTimeEngine.parseDate(booking.checkinDate)
                    val checkout = HotelTimeEngine.parseDate(booking.actualCheckout ?: booking.checkoutDate)
                    val nightsCount = if (checkin != null) {
                        HotelTimeEngine.nightsWithCutoff(checkin, checkout)
                    } else summary.nightsCount
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
                                totalRow = listOf(
                                    "الإجمالي", "", "",
                                    "${CurrencyFormatter.formatAmount(summary.totalAmount)} ريال"
                                )
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
                                totalRow = listOf(
                                    "الإجمالي المدفوع", "",
                                    "${CurrencyFormatter.formatAmount(summary.paidAmount)} ريال"
                                )
                            )
                        ),
                        fileName = PdfExporter.generateFileName("فاتورة-${booking.guestName}-${booking.roomNumber}")
                    )
                    PdfExporter.sharePdf(context, file, "فاتورة - ${booking.guestName} - غرفة ${booking.roomNumber}")
                } catch (_: Exception) {
                }
            }
        } else {
            showInvoice = false
        }
    }
}

// ---------------------------------------------------------------------------
// بطاقة الملخص — Dart widgets/payment_summary_card.dart
// ---------------------------------------------------------------------------

@Composable
private fun PaymentSummaryCard(state: BookingPaymentUiState, onAddBalancePayment: () -> Unit) {
    val booking = state.booking ?: return
    val summary = state.summary ?: return
    val fullyPaid = summary.isFullyPaid

    val gradientColors = if (fullyPaid) listOf(Green50, Green100) else listOf(Blue50, Blue100)
    val borderColor = if (fullyPaid) Green200 else Blue200

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp, vertical = 6.dp)
            .background(
                Brush.linearGradient(gradientColors),
                RoundedCornerShape(12.dp)
            )
            .border(1.dp, borderColor, RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp)
    ) {
        // صف معلومات النزيل.
        Row(verticalAlignment = Alignment.Top) {
            Box(
                modifier = Modifier.size(36.dp).background(BluePrimary, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(booking.roomNumber, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            }
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(booking.guestName, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = AppColors.TextPrimary)
                Text(
                    "غرفة ${booking.roomNumber}${if (booking.guestPhone.isNotBlank()) " • ${booking.guestPhone}" else ""}",
                    fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Grey600
                )
                val identityLine = if (booking.guestIdNumber.isEmpty()) {
                    booking.guestIdType
                } else {
                    "${booking.guestIdType} • ${booking.guestIdNumber}"
                }
                Text(identityLine, fontSize = 11.sp, color = Grey600)
                Text("الجنسية: ${booking.guestNationality}", fontSize = 11.sp, color = Grey600)
                val checkin = HotelTimeEngine.parseDate(booking.checkinDate)
                Text(
                    "الوصول: ${checkin?.let { HotelTimeEngine.formatDisplay(it) } ?: "—"}",
                    fontSize = 11.sp, color = Grey600
                )
                val planned = HotelTimeEngine.parseDate(booking.checkoutDate)
                if (planned != null) {
                    Text("المغادرة المخطط: ${HotelTimeEngine.formatDisplay(planned)}", fontSize = 11.sp, color = Grey600)
                }
                // سطر المغادرة التلقائية (StayBalanceCalculator) عند وجود دفعات.
                state.stayBalance?.let { balance ->
                    if (summary.paidAmount > 0 && summary.roomRate > 0 && balance.autoCheckoutMillis != null) {
                        val extra = if (balance.isAutoExtended) {
                            " (+${(balance.totalPaidNights - booking.expectedNights).coerceAtLeast(0)})"
                        } else ""
                        Text(
                            "المغادرة التلقائية: ${HotelTimeEngine.formatDisplayDateOnly(balance.autoCheckoutMillis!!)} " +
                                "(${balance.totalPaidNights} ليلة مدفوعة)$extra",
                            fontSize = 11.sp, color = Grey600
                        )
                    }
                }
                booking.actualCheckout?.let { raw ->
                    HotelTimeEngine.parseDate(raw)?.let {
                        Text(
                            "المغادرة الفعلي: ${HotelTimeEngine.formatDisplay(it)}",
                            fontSize = 11.sp, color = GreenPrimary
                        )
                    }
                }
            }
            Spacer(Modifier.width(8.dp))
            // شارة الحالة.
            Box(
                modifier = Modifier
                    .background(
                        (if (fullyPaid) GreenPrimary else OrangePrimary).copy(alpha = 0.2f),
                        RoundedCornerShape(8.dp)
                    )
                    .border(1.dp, if (fullyPaid) GreenPrimary else OrangePrimary, RoundedCornerShape(8.dp))
                    .padding(horizontal = 10.dp, vertical = 4.dp)
            ) {
                Text(
                    if (fullyPaid) "مكتمل الدفع" else "دفع جزئي",
                    fontSize = 10.sp, fontWeight = FontWeight.Bold,
                    color = if (fullyPaid) GreenPrimary else OrangePrimary
                )
            }
        }

        Spacer(Modifier.height(8.dp))

        // صف الرقائق التفصيلية (Dart l.264-329).
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            SummaryDetailChip(Icons.Filled.AttachMoney, "سعر الليلة", CurrencyFormatter.formatAmount(summary.roomRate), BlueGrey)
            SummaryDetailChip(
                Icons.Filled.TaskAlt, "الليالي الفعلية", "${summary.nightsCount}",
                if (summary.nightsCount > summary.expectedNights) OrangePrimary else GreenPrimary
            )
            val hasNotCheckedOut = booking.actualCheckout == null
            val nowIsAfterCutoff = HotelTimeEngine.isAfterCutoff(System.currentTimeMillis())
            if (hasNotCheckedOut && nowIsAfterCutoff &&
                summary.nightsCount > summary.expectedNights
            ) {
                SummaryInfoBadge(
                    Icons.Filled.Schedule,
                    "+${summary.nightsCount - summary.expectedNights} ليلة بعد 14:00",
                    Orange100, Orange400, Orange700
                )
            }
            if (summary.debtAmount > 0) {
                SummaryInfoBadge(
                    Icons.Filled.Warning,
                    "يوجد دين ${CurrencyFormatter.formatAmount(summary.debtAmount)}",
                    Red100, Red300, Red700
                )
            }
            if (booking.discount > 0) {
                SummaryDetailChip(Icons.Filled.Discount, "التخفيض", CurrencyFormatter.formatAmount(booking.discount), PurplePrimary)
            }
            if (summary.normalNights > 0) {
                SummaryDetailChip(Icons.Filled.NightsStay, "ليالي عادية", "${summary.normalNights}", BlueGrey)
            }
            if (summary.discountedNights > 0) {
                SummaryDetailChip(
                    Icons.Filled.TrendingDown, "ليالي مخفضة",
                    "${summary.discountedNights} (-${CurrencyFormatter.formatAmount(summary.totalDiscount)})",
                    PurplePrimary
                )
            }
            if (summary.surchargeNights > 0) {
                SummaryDetailChip(
                    Icons.Filled.TrendingUp, "ليالي مزادة",
                    "${summary.surchargeNights} (+${CurrencyFormatter.formatAmount(summary.totalSurcharge)})",
                    TealPrimary
                )
            }
        }

        Spacer(Modifier.height(1.dp))

        // شريط تقدم الدفع (Dart l.332-356).
        Column {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("تقدم الدفع", fontWeight = FontWeight.Bold, fontSize = 9.sp)
                Text("${"%.1f".format(summary.paidPercentage)}%", fontWeight = FontWeight.Bold, fontSize = 9.sp)
            }
            Spacer(Modifier.height(1.dp))
            LinearProgressIndicator(
                progress = { (summary.paidPercentage / 100.0).coerceIn(0.0, 1.0).toFloat() },
                modifier = Modifier.fillMaxWidth().height(2.dp),
                color = if (fullyPaid) GreenPrimary else BluePrimary,
                trackColor = Grey300
            )
        }

        Spacer(Modifier.height(1.dp))

        // رقائق المبالغ الأربع (Dart l.358-377).
        Row(modifier = Modifier.fillMaxWidth()) {
            SummaryAmountChip("الإجمالي", summary.totalAmount, BluePrimary, Modifier.weight(1f))
            Spacer(Modifier.width(3.dp))
            SummaryAmountChip("المدفوع", summary.paidAmount, GreenPrimary, Modifier.weight(1f))
            Spacer(Modifier.width(3.dp))
            SummaryAmountChip("المتبقي", summary.remainingAmount, RedPrimary, Modifier.weight(1f))
            Spacer(Modifier.width(3.dp))
            SummaryAmountChip("مدفوع اليوم", summary.todayPaidAmount, IndigoPrimary, Modifier.weight(1f))
        }

        Spacer(Modifier.height(2.dp))

        // زر الرصيد التراكمي (Dart l.380-399).
        Button(
            onClick = onAddBalancePayment,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = IndigoPrimary, contentColor = Color.White),
            contentPadding = PaddingValues(vertical = 3.dp),
            shape = RoundedCornerShape(10.dp)
        ) {
            Icon(Icons.Filled.AccountBalanceWallet, null, modifier = Modifier.size(12.dp))
            Spacer(Modifier.width(4.dp))
            Text("إضافة دفعة رصيد تراكمي", fontWeight = FontWeight.Bold, fontSize = 9.sp)
        }
    }
}

@Composable
private fun SummaryDetailChip(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, value: String, color: Color) {
    Row(
        modifier = Modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(6.dp))
            .border(1.dp, color.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, modifier = Modifier.size(12.dp), tint = color)
        Spacer(Modifier.width(3.dp))
        Text("$label: ", fontSize = 9.sp, color = color, fontWeight = FontWeight.Bold)
        Text(value, fontSize = 9.sp, color = color, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun SummaryInfoBadge(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, bg: Color, border: Color, textColor: Color) {
    Row(
        modifier = Modifier
            .background(bg, RoundedCornerShape(6.dp))
            .border(1.dp, border, RoundedCornerShape(6.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, modifier = Modifier.size(12.dp), tint = textColor)
        Spacer(Modifier.width(3.dp))
        Text(text, fontSize = 9.sp, color = textColor, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun SummaryAmountChip(label: String, amount: Double, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(6.dp))
            .border(1.dp, color.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
            .padding(horizontal = 4.dp, vertical = 3.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(label, fontSize = 8.sp, color = color, fontWeight = FontWeight.Bold)
        Text(CurrencyFormatter.formatAmount(amount), fontSize = 11.sp, color = color, fontWeight = FontWeight.Bold)
    }
}

/** Dart `_buildLastPaymentCard` (l.609-641) — المبلغ فقط بدون زيادات. */
@Composable
private fun LastPaymentCard(payment: Payment) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .background(Green50, RoundedCornerShape(10.dp))
            .border(1.dp, Green200, RoundedCornerShape(10.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            "آخر مبلغ مدفوع",
            fontSize = 11.sp, fontWeight = FontWeight.Bold,
            color = Grey700, modifier = Modifier.weight(1f)
        )
        Text(
            CurrencyFormatter.formatAmount(payment.amount),
            fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Green800
        )
    }
}

// ---------------------------------------------------------------------------
// تبويب دفعة جديدة (Dart _buildNewPaymentTab + _buildPaymentForm)
// ---------------------------------------------------------------------------

@Composable
private fun NewPaymentTab(
    state: BookingPaymentUiState,
    onPay: (method: PayMethodUi, presetAmount: Double?, presetNotes: String?) -> Unit
) {
    val summary = state.summary ?: return
    if (summary.isFullyPaid) {
        // Dart l.707-722.
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.CheckCircle, null, modifier = Modifier.size(80.dp), tint = GreenPrimary)
                Spacer(Modifier.height(16.dp))
                Text("تم سداد المبلغ كاملاً", fontSize = 14.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text("يمكنك الآن تسجيل مغادرة العميل", color = Grey600)
            }
        }
        return
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(10.dp)
    ) {
        Text("إضافة دفعة جديدة", fontSize = 12.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))

        // بطاقتا الطريقة (نقدي/تحويل فقط — Dart l.771-794).
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PayMethodCard(PayMethodUi.CASH, Modifier.weight(1f)) { onPay(PayMethodUi.CASH, null, null) }
            PayMethodCard(PayMethodUi.TRANSFER, Modifier.weight(1f)) { onPay(PayMethodUi.TRANSFER, null, null) }
        }

        Spacer(Modifier.height(10.dp))
        Text("دفعات سريعة", fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))

        // دفعات سريعة 25/50/75/100% من المتبقي (Dart l.796-846).
        val remaining = kotlin.math.round(summary.remainingAmount).toInt()
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            QuickPaymentButton("25%", (remaining * 25 / 100.0).toInt(), summary, Modifier.weight(1f)) {
                onPay(PayMethodUi.CASH, (remaining * 25 / 100.0).toDouble(), null)
            }
            QuickPaymentButton("50%", (remaining * 50 / 100.0).toInt(), summary, Modifier.weight(1f)) {
                onPay(PayMethodUi.CASH, (remaining * 50 / 100.0).toDouble(), null)
            }
            QuickPaymentButton("75%", (remaining * 75 / 100.0).toInt(), summary, Modifier.weight(1f)) {
                onPay(PayMethodUi.CASH, (remaining * 75 / 100.0).toDouble(), null)
            }
            QuickPaymentButton("100%", remaining, summary, Modifier.weight(1f)) {
                onPay(PayMethodUi.CASH, remaining.toDouble(), null)
            }
        }
    }
}

@Composable
private fun PayMethodCard(method: PayMethodUi, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Card(
        modifier = modifier.clickable(onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .border(1.dp, method.color.copy(alpha = 0.3f), RoundedCornerShape(8.dp))
                .padding(horizontal = 6.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(method.icon, null, tint = method.color, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(4.dp))
            Text(
                method.label,
                fontWeight = FontWeight.Bold, color = method.color, fontSize = 11.sp,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun QuickPaymentButton(
    label: String,
    amount: Int,
    summary: BookingFinancials.Summary,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = amount > 0,
        modifier = modifier,
        colors = ButtonDefaults.buttonColors(
            containerColor = BluePrimary,
            contentColor = Color.White,
            disabledContainerColor = BluePrimary.copy(alpha = 0.3f)
        ),
        contentPadding = PaddingValues(vertical = 4.dp),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, fontWeight = FontWeight.Bold, fontSize = 10.sp)
            Text(
                CurrencyFormatter.formatAmount(amount.toDouble()),
                fontSize = 9.sp,
                maxLines = 1
            )
        }
    }
}

// ---------------------------------------------------------------------------
// تبويب الإجراءات — Dart widgets/actions_tab.dart
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
    val booking = state.booking ?: return
    val hasRemainingBalance = summary.remainingAmount > 0
    val hasUnsettledDebt = summary.debtAmount > 0

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(10.dp)
    ) {
        // شريط المتبقي / الدين (Dart l.106-152).
        if (hasRemainingBalance || hasUnsettledDebt) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        if (hasUnsettledDebt) Red50 else Orange50,
                        RoundedCornerShape(6.dp)
                    )
                    .border(
                        1.dp,
                        if (hasUnsettledDebt) Red300 else Orange300,
                        RoundedCornerShape(6.dp)
                    )
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    if (hasUnsettledDebt) Icons.Filled.ErrorOutline else Icons.Filled.WarningAmber,
                    null,
                    tint = if (hasUnsettledDebt) Red700 else Orange700,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    if (hasUnsettledDebt) {
                        "دين سابق: ${CurrencyFormatter.formatAmount(summary.debtAmount)} • متبقي: ${CurrencyFormatter.formatAmount(summary.remainingAmount)}"
                    } else {
                        "متبقي: ${CurrencyFormatter.formatAmount(summary.remainingAmount)}"
                    },
                    fontSize = 11.sp, fontWeight = FontWeight.Bold,
                    color = if (hasUnsettledDebt) Red900 else Color(0xFFE65100)
                )
            }
            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (hasRemainingBalance) {
                    Button(
                        onClick = onCreateDebt,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = OrangePrimary, contentColor = Color.White),
                        contentPadding = PaddingValues(vertical = 6.dp),
                        shape = RoundedCornerShape(6.dp)
                    ) {
                        Icon(Icons.Filled.AddCircle, null, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("إنشاء دين", fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                }
                if (isAdmin) {
                    Button(
                        onClick = onDiscount,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF43A047), contentColor = Color.White),
                        contentPadding = PaddingValues(vertical = 6.dp),
                        shape = RoundedCornerShape(6.dp)
                    ) {
                        Icon(Icons.Filled.Discount, null, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("خصم مبلغ", fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                } else {
                    Button(
                        onClick = onDiscount,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFBDBDBD), contentColor = Color.White),
                        contentPadding = PaddingValues(vertical = 6.dp),
                        shape = RoundedCornerShape(6.dp)
                    ) {
                        Icon(Icons.Filled.Lock, null, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("خصم (مقيد)", fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
            Spacer(Modifier.height(6.dp))
        }

        // شبكة بطاقات الإجراءات 2×3 (Dart l.153-163 + actions_tab.dart).
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ActionCard(
                "عرض الفاتورة الشاملة", "عرض وطباعة الفاتورة التفصيلية",
                Icons.Filled.ReceiptLong, TealPrimary, Modifier.weight(1f), onInvoice
            )
            ActionCard(
                "سجل المدفوعات", "عرض تاريخ جميع المدفوعات",
                Icons.Filled.History, PurplePrimary, Modifier.weight(1f), onPaymentHistory
            )
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ActionCard(
                "تسجيل المغادرة",
                if (summary.isFullyPaid) "تسجيل مغادرة العميل" else "تحذير: يوجد مبلغ متبقي!",
                Icons.Filled.Logout,
                if (summary.isFullyPaid) GreenPrimary else RedPrimary,
                Modifier.weight(1f), onCheckout
            )
            ActionCard(
                "مغادرة مبكرة / مردود", "حساب المردود عند مغادرة قبل الموعد",
                Icons.Filled.CurrencyExchange, Amber700, Modifier.weight(1f), onEarlyCheckout
            )
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ActionCard(
                "إلغاء يوم إضافي", "إلغاء دفعة اليوم الفندقي المحتسبة بالخطأ",
                Icons.Filled.RemoveCircleOutline, Red700, Modifier.weight(1f), onCancelToday
            )
            ActionCard(
                "إرسال كشف حساب", "إرسال ملخص المدفوعات للعميل",
                Icons.Filled.Send, OrangePrimary, Modifier.weight(1f), onStatement
            )
        }

        Spacer(Modifier.height(12.dp))

        // بطاقة معلومات الحجز (Dart l.166-199).
        Card {
            Column(modifier = Modifier.padding(10.dp)) {
                Text("معلومات الحجز", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                InfoRow("رقم الحجز", booking.localUuid.ifBlank { "${booking.id}" })
                InfoRow("تاريخ الوصول", booking.checkinDate.split(" ").firstOrNull() ?: booking.checkinDate)
                booking.checkoutDate?.let {
                    InfoRow("تاريخ المغادرة", it.split(" ").firstOrNull() ?: it)
                }
                InfoRow("الحالة", booking.status)
                booking.notes?.takeIf { it.isNotEmpty() }?.let {
                    InfoRow("ملاحظات", it)
                }
            }
        }
    }
}

/** بطاقة إجراء — Dart `_buildActionCard` (actions_tab.dart l.211-251). */
@Composable
private fun ActionCard(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    color: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Card(
        modifier = modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Box(
                modifier = Modifier.size(28.dp).background(color.copy(alpha = 0.15f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, null, modifier = Modifier.size(16.dp), tint = color)
            }
            Spacer(Modifier.height(4.dp))
            Text(
                title, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = color,
                textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(2.dp))
            Text(
                subtitle, fontSize = 8.sp, color = Grey600,
                textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        Text(label, fontSize = 11.sp, color = Grey600)
        Spacer(Modifier.width(8.dp))
        Text(value, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
    }
}

// ---------------------------------------------------------------------------
// حوار الدفع — Dart `_showPaymentDialog` (l.992-1125)
// ---------------------------------------------------------------------------

@Composable
private fun PaymentDialog(
    request: PayDialogRequest,
    isSaving: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (amount: Double, notes: String?) -> Unit
) {
    var amount by remember { mutableStateOf(request.presetAmount?.toInt()?.toString() ?: "") }
    var notes by remember { mutableStateOf(request.presetNotes ?: "") }
    var reference by remember { mutableStateOf("") }
    var cardDigits by remember { mutableStateOf("") }
    var bank by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = { if (!isSaving) onDismiss() },
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(request.method.icon, null, tint = request.method.color)
                Spacer(Modifier.width(8.dp))
                Text("دفع ${request.method.label}")
            }
        },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedTextField(
                    value = amount,
                    onValueChange = { amount = it.filter { c -> c.isDigit() } },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("المبلغ*") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true
                )
                if (request.method == PayMethodUi.CARD) {
                    OutlinedTextField(
                        value = cardDigits,
                        onValueChange = { if (it.length <= 4) cardDigits = it.filter { c -> c.isDigit() } },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("آخر 4 أرقام من البطاقة") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true
                    )
                }
                if (request.method == PayMethodUi.TRANSFER) {
                    OutlinedTextField(
                        value = bank,
                        onValueChange = { bank = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("اسم البنك") },
                        singleLine = true
                    )
                }
                if (request.method == PayMethodUi.TRANSFER || request.method == PayMethodUi.CHECK) {
                    OutlinedTextField(
                        value = reference,
                        onValueChange = { reference = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("رقم المرجع/الشيك") },
                        singleLine = true
                    )
                }
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("ملاحظات (اختياري)") },
                    minLines = 2, maxLines = 2
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val parsed = CurrencyFormatter.parseAmount(amount)
                    if (parsed == null || parsed <= 0) return@Button
                    onConfirm(parsed, notes.ifBlank { null })
                },
                enabled = !isSaving
            ) {
                if (isSaving) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Text("تسجيل الدفعة")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

/** إيصال نجاح الدفعة — Dart `_showReceiptDialog` (l.1832-1864). */
@Composable
private fun ReceiptDialog(
    receipt: PaymentReceiptUi,
    onDismiss: () -> Unit,
    onPrint: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("تم تسجيل الدفعة بنجاح") },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.CheckCircle, null, modifier = Modifier.size(64.dp), tint = GreenPrimary)
                Spacer(Modifier.height(16.dp))
                Text("المبلغ: ${CurrencyFormatter.formatAmount(receipt.amount)}")
                Text("طريقة الدفع: ${receipt.methodLabel}")
                Text("المتبقي: ${CurrencyFormatter.formatAmount(receipt.remaining)}")
            }
        },
        confirmButton = {
            Button(onClick = onPrint) { Text("طباعة إيصال") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إغلاق") }
        }
    )
}

// ---------------------------------------------------------------------------
// حوار تأكيد المغادرة — Dart `_showCheckoutConfirmation` (l.1936-2039)
// ---------------------------------------------------------------------------

@Composable
private fun CheckoutConfirmDialog(
    state: BookingPaymentUiState,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    val summary = state.summary ?: return
    // Dart l.1947-1958: المتبقي الفعلي = ليالي السجل − المدفوع.
    val effectiveNightTotal = if (state.nights.isNotEmpty()) {
        state.nights.sumOf { if (it.finalRate > 0) it.finalRate else it.nightlyRate }
    } else summary.totalAmount
    val effectiveRemaining = (effectiveNightTotal - summary.paidAmount).coerceIn(0.0, effectiveNightTotal)
    val hasRemaining = effectiveRemaining > 0

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (hasRemaining) Icons.Filled.Warning else Icons.Filled.CheckCircle,
                    null,
                    tint = if (hasRemaining) RedPrimary else GreenPrimary
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    if (hasRemaining) "تحذير!" else "تأكيد المغادرة",
                    color = if (hasRemaining) RedPrimary else AppColors.TextPrimary
                )
            }
        },
        text = {
            Column {
                if (hasRemaining) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Red50, RoundedCornerShape(8.dp))
                            .border(1.dp, Red200, RoundedCornerShape(8.dp))
                            .padding(12.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.MoneyOff, null, tint = RedPrimary)
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "المبلغ المتبقي: ${CurrencyFormatter.formatAmount(effectiveRemaining)}",
                                fontWeight = FontWeight.Bold, color = RedPrimary, fontSize = 16.sp
                            )
                        }
                        Spacer(Modifier.height(12.dp))
                        Text(
                            "⚠️ سيتم خصم المبلغ من راتبكم",
                            fontWeight = FontWeight.Bold, color = RedPrimary, fontSize = 14.sp
                        )
                    }
                    Spacer(Modifier.height(16.dp))
                }
                Text("هل تريد تسجيل مغادرة العميل وتحرير الغرفة؟")
            }
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (hasRemaining) RedPrimary else GreenPrimary,
                    contentColor = Color.White
                )
            ) { Text(if (hasRemaining) "متابعة رغم ذلك" else "تأكيد المغادرة") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

// ---------------------------------------------------------------------------
// حوار المغادرة المبكرة — Dart `_showEarlyCheckoutDialog` (l.2041-2232)
// ---------------------------------------------------------------------------

@Composable
private fun EarlyCheckoutDialog(
    state: BookingPaymentUiState,
    onDismiss: () -> Unit,
    onConfirmRefund: (refund: Double, unused: Int, actual: Int) -> Unit,
    onCheckoutOnly: () -> Unit
) {
    val booking = state.booking ?: return
    val summary = state.summary ?: return
    val early = BookingFinancials.earlyCheckout(
        booking, state.roomPrice, summary.paidAmount, state.nights
    ) ?: return
    val dateFmt = remember { SimpleDateFormat("dd/MM/yyyy", Locale.US) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.CurrencyExchange, null, tint = Amber700)
                Spacer(Modifier.width(8.dp))
                Text("مغادرة مبكرة — حساب المردود")
            }
        },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                RefundInfoRow("الوصول", dateFmt.format(Date(HotelTimeEngine.parseDate(booking.checkinDate) ?: 0L)))
                HotelTimeEngine.parseDate(booking.checkoutDate)?.let {
                    RefundInfoRow("المغادرة المخططة", dateFmt.format(Date(it)))
                }
                RefundInfoRow("تاريخ المغادرة الفعلي", dateFmt.format(Date(System.currentTimeMillis())))
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                RefundInfoRow("الليالي المدفوعة", "${early.plannedNights} ليلة")
                RefundInfoRow("الليالي المستخدمة", "${early.actualNights} ليلة")
                RefundInfoRow("الليالي غير المستخدمة", "${early.unusedNights} ليلة", Orange700)
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                RefundInfoRow("إجمالي المدفوع", CurrencyFormatter.formatAmount(summary.paidAmount))
                RefundInfoRow("تكلفة الليالي المستخدمة", CurrencyFormatter.formatAmount(early.actualNightsCost))
                if (early.refundAmount > 0) {
                    Spacer(Modifier.height(12.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Green50, RoundedCornerShape(8.dp))
                            .border(1.dp, Green300, RoundedCornerShape(8.dp))
                            .padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Filled.MoneyOff, null, tint = GreenPrimary)
                        Spacer(Modifier.width(8.dp))
                        Text(
                            "المبلغ المردود: ${CurrencyFormatter.formatAmount(kotlin.math.round(early.refundAmount))}",
                            fontWeight = FontWeight.Bold, color = GreenPrimary, fontSize = 16.sp
                        )
                    }
                } else {
                    Spacer(Modifier.height(12.dp))
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Orange50, RoundedCornerShape(8.dp))
                            .border(1.dp, Orange300, RoundedCornerShape(8.dp))
                            .padding(12.dp)
                    ) {
                        Text(
                            "لا يوجد مردود — المدفوع يساوي تكلفة الليالي المستخدمة",
                            fontWeight = FontWeight.Bold, color = OrangePrimary, fontSize = 13.sp
                        )
                    }
                }
            }
        },
        confirmButton = {
            if (early.refundAmount > 0) {
                Button(
                    onClick = {
                        onConfirmRefund(
                            kotlin.math.round(early.refundAmount),
                            early.unusedNights,
                            early.actualNights
                        )
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = GreenPrimary, contentColor = Color.White)
                ) {
                    Icon(Icons.Filled.CheckCircle, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("تأكيد المغادرة والمردود")
                }
            } else {
                Button(
                    onClick = onCheckoutOnly,
                    colors = ButtonDefaults.buttonColors(containerColor = OrangePrimary, contentColor = Color.White)
                ) {
                    Icon(Icons.Filled.CheckCircle, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("تأكيد المغادرة فقط")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

@Composable
private fun RefundInfoRow(label: String, value: String, valueColor: Color = AppColors.TextPrimary) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, color = Grey600, fontSize = 13.sp)
        Text(value, fontWeight = FontWeight.Bold, fontSize = 13.sp, color = valueColor)
    }
}

// ---------------------------------------------------------------------------
// حوار إلغاء دفعة اليوم الفندقي — Dart l.2800-2965
// ---------------------------------------------------------------------------

@Composable
private fun CancelTodayDialog(
    state: BookingPaymentUiState,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    val hotelDay = HotelTimeEngine.currentHotelDayKey()
    val todays = state.payments.filter { p ->
        !p.isVoided && (p.hotelDayKey == hotelDay ||
            (p.hotelDayKey == null && p.paymentDate.startsWith(hotelDay)))
    }

    if (todays.isEmpty()) {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Info, null, tint = BluePrimary)
                    Spacer(Modifier.width(8.dp))
                    Text("لا توجد دفعات اليوم")
                }
            },
            text = { Text("لا توجد مدفوعات مسجلة في اليوم الفندقي الحالي لإلغائها.") },
            confirmButton = {
                TextButton(onClick = onDismiss) { Text("إغلاق") }
            }
        )
        return
    }

    val todayTotal = todays.sumOf { it.amount }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.RemoveCircleOutline, null, tint = RedPrimary)
                Spacer(Modifier.width(8.dp))
                Text("إلغاء دفعة اليوم الفندقي")
            }
        },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Red50, RoundedCornerShape(8.dp))
                        .border(1.dp, Red200, RoundedCornerShape(8.dp))
                        .padding(12.dp)
                ) {
                    Text("اليوم الفندقي: $hotelDay", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Spacer(Modifier.height(8.dp))
                    Text("عدد المدفوعات المراد إلغاؤها: ${todays.size}", fontSize = 13.sp)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "إجمالي المبلغ المراد إلغاؤه: ${CurrencyFormatter.formatAmount(todayTotal)}",
                        fontWeight = FontWeight.Bold, fontSize = 14.sp, color = RedPrimary
                    )
                }
                Spacer(Modifier.height(12.dp))
                Text(
                    "⚠️ سيتم حذف دفعات اليوم الفندقي فقط. سجل خروج النزيل منفصل عبر زر \"تسجيل المغادرة\".",
                    fontSize = 12.sp, color = Grey600
                )
                Spacer(Modifier.height(12.dp))
                Text("تفاصيل المدفوعات المراد إلغاؤها:", fontWeight = FontWeight.Bold, fontSize = 12.sp)
                Spacer(Modifier.height(8.dp))
                todays.forEach { p ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            p.notes ?: p.paymentMethod,
                            fontSize = 11.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            CurrencyFormatter.formatAmount(p.amount),
                            fontWeight = FontWeight.Bold, fontSize = 11.sp, color = RedPrimary
                        )
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(containerColor = RedPrimary, contentColor = Color.White)
            ) {
                Icon(Icons.Filled.CheckCircle, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text("تأكيد إلغاء الدفعات")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

// ---------------------------------------------------------------------------
// حوار الخصم (المدير) — Dart `_showDiscountAmountDialog` (l.2521-2695)
// ---------------------------------------------------------------------------

@Composable
private fun DiscountDialog(
    state: BookingPaymentUiState,
    onDismiss: () -> Unit,
    onApply: (Double) -> Unit
) {
    val booking = state.booking ?: return
    val summary = state.summary ?: return
    var amountText by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Discount, null, tint = GreenPrimary)
                Spacer(Modifier.width(8.dp))
                Text("خصم مبلغ من الليالي الفعلية")
            }
        },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                Text(
                    "النزيل: ${booking.guestName} (غرفة ${booking.roomNumber})",
                    fontWeight = FontWeight.Bold
                )
                Spacer(Modifier.height(8.dp))
                DialogInfoRow("إجمالي الفاتورة", CurrencyFormatter.formatAmount(summary.totalAmount))
                DialogInfoRow("المدفوع", CurrencyFormatter.formatAmount(summary.paidAmount))
                DialogInfoRow("المتبقي", CurrencyFormatter.formatAmount(summary.remainingAmount))
                if (booking.discount > 0) {
                    DialogInfoRow("خصم حالي", CurrencyFormatter.formatAmount(booking.discount))
                }
                HorizontalDivider(modifier = Modifier.padding(vertical = 6.dp))
                Text("مبلغ الخصم الجديد:", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp))
                OutlinedTextField(
                    value = amountText,
                    onValueChange = { amountText = it.filter { c -> c.isDigit() || c == '.' } },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("0") },
                    suffix = { Text("ريال") },
                    leadingIcon = { Icon(Icons.Filled.AttachMoney, null, modifier = Modifier.size(18.dp)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "سيتم إضافة هذا المبلغ إلى الخصم الحالي وتقليل المتبقي.",
                    fontSize = 10.sp, color = Grey700
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    CurrencyFormatter.parseAmount(amountText)?.let { onApply(it) }
                },
                colors = ButtonDefaults.buttonColors(containerColor = GreenPrimary, contentColor = Color.White)
            ) { Text("تطبيق الخصم") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

@Composable
private fun DialogInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, fontSize = 12.sp)
        Text(value, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

// ---------------------------------------------------------------------------
// حوار كشف الحساب — Dart `_sendAccountStatement` (l.3007-3224)
// ---------------------------------------------------------------------------

@Composable
private fun StatementDialog(
    state: BookingPaymentUiState,
    onBuildStatement: () -> String?,
    onShareText: (String) -> Unit,
    onSharePdf: () -> Unit,
    onDismiss: () -> Unit
) {
    val booking = state.booking ?: return
    val summary = state.summary ?: return
    var showFullPreview by remember { mutableStateOf(false) }
    val message = remember(state.summary?.paidAmount) { onBuildStatement() }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.ReceiptLong, null, tint = OrangePrimary)
                Spacer(Modifier.width(8.dp))
                Text("إرسال كشف حساب", maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                // 1) بطاقة معلومات العميل (Dart l.3069-3109).
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Orange50, RoundedCornerShape(8.dp))
                        .border(1.dp, Color(0xFFFFCC80), RoundedCornerShape(8.dp))
                        .padding(12.dp)
                ) {
                    StatementPreviewRow("العميل", booking.guestName)
                    StatementPreviewRow("الغرفة", booking.roomNumber)
                    StatementPreviewRow("الهاتف", booking.guestPhone)
                    StatementPreviewRow(
                        "الإجمالي",
                        "${CurrencyFormatter.formatAmount(summary.totalAmount)} ريال"
                    )
                    StatementPreviewRow(
                        "المدفوع",
                        "${CurrencyFormatter.formatAmount(summary.paidAmount)} ريال",
                        GreenPrimary
                    )
                    StatementPreviewRow(
                        "المتبقي",
                        "${CurrencyFormatter.formatAmount(summary.remainingAmount)} ريال",
                        if (summary.remainingAmount > 0) RedPrimary else GreenPrimary
                    )
                }
                Spacer(Modifier.height(12.dp))

                // 2) جدول المدفوعات المفصّل (Dart l.3230-3478).
                DialogPaymentsTable(state)

                Spacer(Modifier.height(12.dp))

                // 3) زر معاينة رسالة WhatsApp (Dart l.3121-3145).
                OutlinedButton(
                    onClick = { showFullPreview = !showFullPreview },
                    border = androidx.compose.foundation.BorderStroke(1.dp, TealPrimary)
                ) {
                    Icon(
                        if (showFullPreview) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                        null, modifier = Modifier.size(16.dp), tint = TealPrimary
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        if (showFullPreview) "إخفاء المعاينة" else "معاينة رسالة WhatsApp",
                        fontSize = 13.sp, color = TealPrimary
                    )
                }

                if (showFullPreview && message != null) {
                    Spacer(Modifier.height(8.dp))
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 260.dp)
                            .background(Color(0xFFE8F5E9), RoundedCornerShape(8.dp))
                            .border(1.dp, Green300, RoundedCornerShape(8.dp))
                            .padding(10.dp)
                            .verticalScroll(rememberScrollState())
                    ) {
                        Text(
                            message,
                            fontSize = 12.sp,
                            lineHeight = 19.sp,
                            fontFamily = FontFamily.Monospace,
                            textAlign = TextAlign.End
                        )
                    }
                    Spacer(Modifier.height(4.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Start,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "${message.length}/1000 حرف",
                            fontSize = 10.sp, fontWeight = FontWeight.Bold,
                            color = when {
                                message.length > 1000 -> RedPrimary
                                message.length > 900 -> OrangePrimary
                                else -> Grey600
                            }
                        )
                        if (message.length > 1000) {
                            Spacer(Modifier.width(6.dp))
                            Icon(Icons.Filled.Warning, null, modifier = Modifier.size(12.dp), tint = RedPrimary)
                        }
                    }
                }
            }
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(
                    onClick = {
                        val msg = message ?: onBuildStatement() ?: return@FilledTonalButton
                        onDismiss()
                        onShareText(msg)
                    },
                    colors = androidx.compose.material3.ButtonDefaults.filledTonalButtonColors(
                        containerColor = Green100
                    )
                ) {
                    Icon(Icons.Filled.Chat, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("إرسال كنص")
                }
                Button(
                    onClick = {
                        onDismiss()
                        onSharePdf()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = OrangePrimary, contentColor = Color.White)
                ) {
                    Icon(Icons.Filled.Share, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("مشاركة PDF")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}

/** جدول المدفوعات داخل الحوار — Dart `_buildDialogPaymentsTable` (l.3230-3478). */
@Composable
private fun DialogPaymentsTable(state: BookingPaymentUiState) {
    if (state.payments.isEmpty()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Grey100, RoundedCornerShape(8.dp))
                .border(1.dp, Grey300, RoundedCornerShape(8.dp))
                .padding(horizontal = 12.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Info, null, modifier = Modifier.size(18.dp), tint = Grey600)
            Spacer(Modifier.width(8.dp))
            Text("لا توجد دفعات مسجّلة بعد", fontSize = 13.sp, color = Grey600)
        }
        return
    }

    val sorted = state.payments.sortedBy { HotelTimeEngine.parseDate(it.paymentDate) ?: 0L }
    val dateFmt = remember { SimpleDateFormat("yyyy/MM/dd", Locale.US) }
    val timeFmt = remember { SimpleDateFormat("HH:mm", Locale.US) }

    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .width(4.dp)
                    .height(14.dp)
                    .background(TealPrimary, RoundedCornerShape(2.dp))
            )
            Spacer(Modifier.width(6.dp))
            Text(
                "سجل المدفوعات المفصّل (${sorted.size} دفعة)",
                fontWeight = FontWeight.Bold, fontSize = 13.sp, color = TealPrimary
            )
        }
        Spacer(Modifier.height(6.dp))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .border(1.dp, Grey300, RoundedCornerShape(8.dp))
        ) {
            // رأس الجدول.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Teal700)
                    .padding(horizontal = 8.dp, vertical = 8.dp)
            ) {
                Text("#", textAlign = TextAlign.Center, style = TableHeaderStyle, modifier = Modifier.weight(1f))
                Text("التاريخ", textAlign = TextAlign.Center, style = TableHeaderStyle, modifier = Modifier.weight(3f))
                Text("طريقة الدفع", textAlign = TextAlign.Center, style = TableHeaderStyle, modifier = Modifier.weight(2f))
                Text("المبلغ", textAlign = TextAlign.Center, style = TableHeaderStyle, modifier = Modifier.weight(2f))
            }
            // صفوف الدفعات (تظليل متبادل).
            sorted.forEachIndexed { index, p ->
                val millis = HotelTimeEngine.parseDate(p.paymentDate)
                val method = PayMethodUi.fromDb(p.paymentMethod)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(if (index % 2 == 0) Color.White else Grey50)
                        .padding(horizontal = 8.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "${index + 1}",
                        textAlign = TextAlign.Center, fontSize = 11.sp, color = Grey600,
                        modifier = Modifier.weight(1f)
                    )
                    Column(modifier = Modifier.weight(3f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            millis?.let { dateFmt.format(Date(it)) } ?: p.paymentDate.take(10),
                            fontSize = 11.sp, fontWeight = FontWeight.Bold
                        )
                        Text(
                            millis?.let { timeFmt.format(Date(it)) } ?: "",
                            fontSize = 9.sp, color = Grey600
                        )
                    }
                    Row(
                        modifier = Modifier.weight(2f),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(method.icon, null, modifier = Modifier.size(12.dp), tint = method.color)
                        Spacer(Modifier.width(3.dp))
                        Text(method.label, fontSize = 10.sp)
                    }
                    Text(
                        "${CurrencyFormatter.formatAmount(p.amount)} ريال",
                        textAlign = TextAlign.Center,
                        fontSize = 11.sp, fontWeight = FontWeight.Bold, color = GreenPrimary,
                        modifier = Modifier.weight(2f)
                    )
                }
            }
            // صف الإجمالي.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Orange50)
                    .border(1.dp, Color(0xFFFFCC80))
                    .padding(horizontal = 8.dp, vertical = 10.dp)
            ) {
                Spacer(Modifier.weight(1f))
                Text(
                    "الإجمالي المدفوع",
                    textAlign = TextAlign.Center, fontSize = 11.sp,
                    fontWeight = FontWeight.Bold, color = OrangePrimary,
                    modifier = Modifier.weight(3f)
                )
                Spacer(Modifier.weight(2f))
                Text(
                    "${CurrencyFormatter.formatAmount(state.summary?.paidAmount ?: 0.0)} ريال",
                    textAlign = TextAlign.Center, fontSize = 12.sp,
                    fontWeight = FontWeight.Bold, color = GreenPrimary,
                    modifier = Modifier.weight(2f)
                )
            }
        }
    }
}

private val TableHeaderStyle = androidx.compose.ui.text.TextStyle(
    color = Color.White,
    fontWeight = FontWeight.Bold,
    fontSize = 11.sp
)

@Composable
private fun StatementPreviewRow(label: String, value: String, valueColor: Color = AppColors.TextPrimary) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, color = Grey600, fontSize = 13.sp)
        Text(
            value,
            fontWeight = FontWeight.Bold, color = valueColor, fontSize = 13.sp,
            textAlign = TextAlign.End,
            modifier = Modifier.weight(1f, fill = false)
        )
    }
}

// مساعدات صغيرة
