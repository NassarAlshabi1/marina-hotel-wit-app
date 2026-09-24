package com.marina.marina.presentation.payments

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.BookingNight
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.BookingNightsRepository
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.util.BookingFinancials
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/**
 * إقتراح التمديد التلقائي المعروض على المستخدم للتأكيد
 * (Dart l.1615-1706: المبلغ يتجاوز المتبقي → حوار تسجيل دفعة مع تمديد).
 */
data class ExtensionProposal(
    val amount: Double,
    val remaining: Double,
    val surplus: Double,
    val extraNights: Int,
    val notes: String
)

/** Dart `_PaymentTotals` (l.4171-4175). */
data class PaymentTotals(val total: Double, val remaining: Double)

/** إيصال نجاح الدفعة — Dart `_showReceiptDialog` (l.1832-1864). */
data class PaymentReceiptUi(
    val amount: Double,
    val methodLabel: String,
    val remaining: Double
)

data class BookingPaymentUiState(
    val isLoading: Boolean = false,
    val booking: Booking? = null,
    val payments: List<Payment> = emptyList(),
    val nights: List<BookingNight> = emptyList(),
    val roomPrice: Double = 0.0,
    val debtRemaining: Double = 0.0,
    val isAdmin: Boolean = false,
    val isSaving: Boolean = false,
    val tone: MsgTone = MsgTone.INFO,
    /** سناك-بار إجراء اختياري (مثل «عرض الديون»). */
    val action: String? = null,
    val error: String? = null,
    val message: String? = null,
    val finished: Boolean = false,
    /** إيصال الدفعة المنتظر عرضه (Dart receipt dialog). */
    val receipt: PaymentReceiptUi? = null,
    /** Pending auto-extension proposal awaiting user confirmation. */
    val extensionProposal: ExtensionProposal? = null,
    /** رسالة واتساب تُعرض كإجراء سناك-بار بعد نجاح العملية. */
    val whatsappMessage: String? = null
) {
    val summary: BookingFinancials.Summary?
        get() = booking?.let { BookingFinancials.calculate(it, roomPrice, payments, nights, debtRemaining) }

    val stayBalance: BookingFinancials.StayBalance?
        get() = booking?.let {
            BookingFinancials.stayBalance(it, roomPrice, summary?.paidAmount ?: 0.0)
        }
}

@HiltViewModel
class BookingPaymentViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val bookingsRepository: BookingsRepository,
    private val paymentsRepository: PaymentsRepository,
    private val roomsRepository: RoomsRepository,
    private val nightsRepository: BookingNightsRepository,
    private val debtsRepository: DebtsRepository,
    private val syncRepository: SyncRepository
) : ViewModel() {

    private val bookingId: Long = savedStateHandle.get<Long>("bookingId") ?: 0L

    private val _state = MutableStateFlow(BookingPaymentUiState(isLoading = true))
    val state: StateFlow<BookingPaymentUiState> = _state.asStateFlow()

    init {
        combine(
            bookingsRepository.getAll(),
            paymentsRepository.getByBooking(bookingId)
        ) { bookings, payments ->
            bookings.find { it.id == bookingId } to payments
        }.onEach { (booking, payments) ->
            if (booking == null) {
                _state.value = _state.value.copy(isLoading = false, booking = null)
                return@onEach
            }
            val price = roomsRepository.getByNumber(booking.roomNumber)?.price ?: 0.0
            val nights = nightsRepository.getByBooking(booking.id)
            val debts = debtsRepository.getAll().firstOrNull() ?: emptyList()
            // Dart `_checkForDebts` (l.190-210): ديون غير مسددة مرتبطة بالحجز.
            val debtRemaining = debts
                .filter { it.bookingLocalId == booking.id && !it.isSettled && it.remainingAmount > 0 }
                .sumOf { it.remainingAmount }

            // Derived-fields refresh (Dart refreshForBookingId with
            // enqueueOutbox:false) — display-only, لا ينشئ Outbox.
            val summary = BookingFinancials.calculate(booking, price, payments, nights, debtRemaining)
            val checkin = HotelTimeEngine.parseDate(booking.checkinDate)
            val liveNights = if (checkin != null) {
                val checkout = HotelTimeEngine.parseDate(booking.actualCheckout)
                HotelTimeEngine.nightsWithCutoff(checkin, checkout)
            } else booking.calculatedNights
            val refreshed = booking.copy(
                calculatedNights = liveNights,
                totalDueCached = summary.totalAmount,
                totalPaidCached = summary.paidAmount,
                remainingBalanceCached = summary.remainingAmount,
                isFullyPaid = summary.isFullyPaid
            )
            if (refreshed != booking) {
                bookingsRepository.updateComputedFields(refreshed)
            }
            _state.value = _state.value.copy(
                isLoading = false,
                booking = refreshed,
                payments = payments,
                nights = nights,
                roomPrice = price,
                debtRemaining = debtRemaining,
                error = null
            )
        }.launchIn(viewModelScope)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null, error = null, action = null, whatsappMessage = null)
    }

    fun consumeReceipt() {
        _state.value = _state.value.copy(receipt = null)
    }

    fun dismissExtensionProposal() {
        _state.value = _state.value.copy(extensionProposal = null)
    }

    fun setAdmin(isAdmin: Boolean) {
        _state.value = _state.value.copy(isAdmin = isAdmin)
    }

    /**
     * Dart `_processPayment` (l.1571-1830). يتحقق من المبلغ ثم إما يعرض
     * إقتراح التمديد التلقائي (عند الفائض) أو يحفظ الدفعة مباشرة.
     * [isPendingBalance] يتخطى فرع التمديد (رصيد تراكمي).
     */
    fun processPayment(
        amount: Double,
        method: String,
        notes: String?,
        isPendingBalance: Boolean = false,
        revenueType: String = "room"
    ) {
        val booking = _state.value.booking ?: return
        if (amount <= 0) {
            _state.value = _state.value.copy(message = "يرجى إدخال مبلغ صحيح", tone = MsgTone.INFO)
            return
        }
        if (amount % 1.0 != 0.0) {
            _state.value = _state.value.copy(message = "المبلغ يجب أن يكون بدون كسور", tone = MsgTone.INFO)
            return
        }
        viewModelScope.launch {
            try {
                val totals = calculateCurrentTotals()
                if (!isPendingBalance && amount > totals.remaining) {
                    val surplus = amount - totals.remaining
                    val rate = _state.value.roomPrice
                    if (rate <= 0) {
                        _state.value = _state.value.copy(
                            message = "لا يمكن حساب الليالي الإضافية — سعر الغرفة غير محدد",
                            tone = MsgTone.ERROR
                        )
                        return@launch
                    }
                    val extraNights = kotlin.math.ceil(surplus / rate).toInt()
                    if (extraNights <= 0) {
                        _state.value = _state.value.copy(
                            message = "لا يمكن حساب الليالي الإضافية",
                            tone = MsgTone.INFO
                        )
                        return@launch
                    }
                    _state.value = _state.value.copy(
                        extensionProposal = ExtensionProposal(
                            amount, totals.remaining, surplus, extraNights, notes ?: ""
                        )
                    )
                } else {
                    savePayment(booking, amount, method, notes, revenueType, isPendingBalance)
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    error = "تعذّر تسجيل الدفعة: ${e.message}",
                    tone = MsgTone.ERROR
                )
            }
        }
    }

    /** تأكيد حوار «تسجيل دفعة مع تمديد» — تمديد + دفعة (Dart l.1698-1767). */
    fun confirmExtensionAndPay(method: String) {
        val proposal = _state.value.extensionProposal ?: return
        val booking = _state.value.booking ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, extensionProposal = null)
            try {
                val extraNights = proposal.extraNights
                val nightsWord = if (extraNights == 1) "ليلة" else "ليالي"
                // Dart l.1698-1704: (checkoutDate ?? now + 1 day) + extraNights.
                val baseCheckout = HotelTimeEngine.parseDate(booking.checkoutDate)
                    ?: (System.currentTimeMillis() + 24L * 3600 * 1000)
                val newCheckout = java.util.Calendar.getInstance().apply {
                    timeInMillis = baseCheckout
                    add(java.util.Calendar.DAY_OF_YEAR, extraNights)
                }.timeInMillis
                val updated = booking.copy(
                    checkoutDate = HotelTimeEngine.formatIso(newCheckout),
                    expectedNights = booking.expectedNights + extraNights,
                    notes = (booking.notes?.let { "$it\n" } ?: "") +
                        "تمديد تلقائي: $extraNights $nightsWord"
                )
                bookingsRepository.update(updated)
                savePayment(updated, proposal.amount, method, proposal.notes.ifBlank { null }, "room", false)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    error = "تعذّر تسجيل الدفعة: ${e.message}",
                    tone = MsgTone.ERROR
                )
            }
        }
    }

    /** Dart `_processCheckout` (l.2715-2795). */
    fun completeCheckout() {
        val booking = _state.value.booking ?: return
        viewModelScope.launch {
            try {
                val now = System.currentTimeMillis()
                val checkin = HotelTimeEngine.parseDate(booking.checkinDate) ?: now
                val finalNights = HotelTimeEngine.nightsWithCutoff(checkin, now)
                bookingsRepository.update(
                    booking.copy(
                        status = "مكتمل",
                        actualCheckout = HotelTimeEngine.formatIso(now),
                        calculatedNights = finalNights
                    )
                )
                // تحرير الغرفة فوراً (الحالة → شاغرة).
                roomsRepository.getByNumber(booking.roomNumber)?.let { room ->
                    if (StatusUtils.isRoomOccupied(room.status)) {
                        roomsRepository.update(room.copy(status = "شاغرة"))
                    }
                }
                pushSilently()
                _state.value = _state.value.copy(
                    message = "تم تسجيل المغادرة بنجاح وتحرير الغرفة",
                    tone = MsgTone.SUCCESS,
                    finished = true
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    error = "فشل تسجيل المغادرة: ${e.message}",
                    tone = MsgTone.ERROR_DARK
                )
            }
        }
    }

    /**
     * Dart `_processEarlyCheckout` (l.2255-2358): الحجز → مكتمل، المردود
     * يُسجّل كدفعة سالبة، وتُحرَّر الغرفة.
     */
    fun processEarlyCheckout(refundAmount: Double, unusedNights: Int, actualNights: Int) {
        val booking = _state.value.booking ?: return
        viewModelScope.launch {
            try {
                val now = System.currentTimeMillis()
                bookingsRepository.update(
                    booking.copy(
                        status = "مكتمل",
                        actualCheckout = HotelTimeEngine.formatIso(now),
                        calculatedNights = actualNights
                    )
                )
                if (refundAmount > 0) {
                    val nightsWord = if (unusedNights == 1) "ليلة" else "ليالي"
                    val refund = kotlin.math.round(refundAmount).toDouble()
                    savePayment(
                        booking.copy(status = "مكتمل"),
                        -refund,
                        "نقدي",
                        "مردود مغادرة مبكرة - $unusedNights $nightsWord غير مستخدمة",
                        "room",
                        false,
                        emitUi = false
                    )
                    _state.value = _state.value.copy(
                        message = "تم تسجيل مغادرة مبكرة — المردود: " +
                            "${CurrencyFormatter.formatAmount(refundAmount)} ($unusedNights $nightsWord)",
                        tone = MsgTone.SUCCESS,
                        finished = true,
                        whatsappMessage = buildRefundWhatsAppMessage(refundAmount, unusedNights)
                    )
                } else {
                    _state.value = _state.value.copy(
                        message = "تم تسجيل المغادرة بنجاح وتحرير الغرفة",
                        tone = MsgTone.SUCCESS,
                        finished = true
                    )
                }
                roomsRepository.getByNumber(booking.roomNumber)?.let { room ->
                    if (StatusUtils.isRoomOccupied(room.status)) {
                        roomsRepository.update(room.copy(status = "شاغرة"))
                    }
                }
                pushSilently()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    error = "فشل تسجيل المغادرة المبكرة: ${e.message}",
                    tone = MsgTone.ERROR_DARK
                )
            }
        }
    }

    /** Dart `_processCancelTodayPayments` (l.2967-3005) — حذف ناعم لمدفوعات اليوم. */
    fun cancelTodayPayments() {
        viewModelScope.launch {
            try {
                val hotelDay = HotelTimeEngine.currentHotelDayKey()
                val todays = _state.value.payments.filter { p ->
                    !p.isVoided && (p.hotelDayKey == hotelDay ||
                        (p.hotelDayKey == null && p.paymentDate.startsWith(hotelDay)))
                }
                if (todays.isEmpty()) {
                    _state.value = _state.value.copy(message = "لا توجد دفعات اليوم", tone = MsgTone.INFO)
                    return@launch
                }
                todays.forEach { paymentsRepository.softDelete(it.id) }
                pushSilently()
                _state.value = _state.value.copy(
                    message = "تم إلغاء ${todays.size} دفعة بنجاح",
                    tone = MsgTone.SUCCESS
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    error = "فشل إلغاء الدفعات: ${e.message}",
                    tone = MsgTone.ERROR_DARK
                )
            }
        }
    }

    /** Dart `_createDebtFromRemainingBalance` (l.2400-2511). */
    fun createDebtFromRemainingBalance() {
        val booking = _state.value.booking ?: return
        val remaining = _state.value.summary?.remainingAmount ?: 0.0
        if (remaining <= 0) return
        viewModelScope.launch {
            try {
                val nowIso = HotelTimeEngine.formatIso(System.currentTimeMillis())
                debtsRepository.insert(
                    Debt(
                        bookingLocalId = booking.id,
                        guestName = booking.guestName,
                        checkinDate = booking.checkinDate,
                        checkoutDate = booking.actualCheckout ?: booking.checkoutDate ?: nowIso,
                        dateRecorded = nowIso,
                        debtReason = "مبلغ متبقي من إقامة - غرفة ${booking.roomNumber}",
                        totalAmount = remaining,
                        paidAmount = 0.0,
                        remainingAmount = remaining,
                        paymentDate = nowIso,
                        isSettled = false,
                        note = "تم إنشاء هذا الدين تلقائياً من شاشة المدفوعات " +
                            "عند وجود مبلغ متبقي لدى النزيل."
                    )
                )
                pushSilently()
                _state.value = _state.value.copy(
                    message = "✅ تم إنشاء دين بقيمة ${CurrencyFormatter.formatAmount(remaining)} " +
                        "وإضافته إلى قائمة الديون",
                    tone = MsgTone.WARN,
                    action = "عرض الديون"
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    error = "فشل إنشاء الدين: ${e.message}",
                    tone = MsgTone.ERROR
                )
            }
        }
    }

    /**
     * Dart `_showDiscountAmountDialog` (l.2521-2695): للمدير فقط، يُضاف إلى
     * الخصم الحالي مع discountType='total'.
     */
    fun applyAdminDiscount(amount: Double) {
        val booking = _state.value.booking ?: return
        val summary = _state.value.summary ?: return
        if (amount <= 0) {
            _state.value = _state.value.copy(message = "⚠️ المبلغ غير صالح", tone = MsgTone.ERROR)
            return
        }
        if (amount > summary.remainingAmount) {
            _state.value = _state.value.copy(
                message = "⚠️ مبلغ الخصم يتجاوز المتبقي (${CurrencyFormatter.formatAmount(summary.remainingAmount)})",
                tone = MsgTone.ERROR
            )
            return
        }
        viewModelScope.launch {
            try {
                val newDiscount = booking.discount + amount
                bookingsRepository.update(booking.copy(discount = newDiscount, discountType = "total"))
                pushSilently()
                _state.value = _state.value.copy(
                    message = "✅ تم خصم ${CurrencyFormatter.formatAmount(amount)} من الليالي الفعلية. " +
                        "المتبقي الجديد: ${CurrencyFormatter.formatAmount((summary.remainingAmount - amount).coerceAtLeast(0.0))}",
                    tone = MsgTone.SUCCESS
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    error = "فشل تطبيق الخصم: ${e.message}",
                    tone = MsgTone.ERROR
                )
            }
        }
    }

    /** Dart `_buildAccountStatementMessage` (l.3607-3702) — WhatsApp كشف حساب. */
    fun buildAccountStatement(): String? {
        val booking = _state.value.booking ?: return null
        val summary = _state.value.summary ?: return null
        val sb = StringBuilder()
        sb.append("كشف حساب - MARINA HOTEL\n")
        sb.append("━━━━━━━━━━━\n")
        sb.append("العميل: ${booking.guestName}\n")
        val checkinDate = HotelTimeEngine.parseDate(booking.checkinDate)
        sb.append(
            "الغرفة: ${booking.roomNumber} | ${summary.nightsCount} ليلة | الوصول: " +
                (checkinDate?.let { HotelTimeEngine.formatDisplayDateOnly(it) } ?: "—") + "\n"
        )
        val checkoutText = HotelTimeEngine.parseDate(booking.actualCheckout ?: booking.checkoutDate)
            ?.let { HotelTimeEngine.formatDisplayDateOnly(it) } ?: "لم يحدد"
        sb.append("المغادرة: $checkoutText\n")
        sb.append("━━━━━━━━━━━\n")
        sb.append("الإجمالي: ${CurrencyFormatter.formatAmount(summary.totalAmount)} ريال\n")
        if (booking.discount > 0) {
            val unit = if (booking.discountType == "per_night") "/ليلة" else ""
            sb.append("الخصم: -${CurrencyFormatter.formatAmount(booking.discount)} ريال$unit\n")
        }
        sb.append("المدفوع: ${CurrencyFormatter.formatAmount(summary.paidAmount)} ريال\n")
        sb.append("المتبقي: ${CurrencyFormatter.formatAmount(summary.remainingAmount)} ريال\n")
        sb.append("الحالة: ${if (summary.isFullyPaid) "مكتمل ✓" else "دفع جزئي"}\n")
        sb.append("━━━━━━━━━━━\n")
        val sorted = _state.value.payments.sortedBy { it.paymentDate }
        if (sorted.isNotEmpty()) {
            sb.append("سجل المدفوعات المفصّل (${sorted.size}):\n")
            sorted.forEachIndexed { index, p ->
                if (sb.length > 950) {
                    val remainingCount = sorted.size - index
                    if (remainingCount > 0) sb.append("+ $remainingCount دفعات أخرى...\n")
                    return@forEachIndexed
                }
                sb.append(
                    "${index + 1}. ${CurrencyFormatter.formatAmount(p.amount)} ريال | " +
                        "${p.paymentMethod} | ${p.paymentDate.take(16).replace("T", " ")}\n"
                )
            }
            if (sb.length < 970) {
                sb.append("إجمالي المدفوع: ${CurrencyFormatter.formatAmount(summary.paidAmount)} ريال\n")
            }
        }
        if (_state.value.debtRemaining > 0 && sb.length < 960) {
            sb.append("━━━━━━━━━━━\n")
            sb.append("ديون سابقة: ${CurrencyFormatter.formatAmount(_state.value.debtRemaining)} ريال\n")
        }
        if (sb.length < 980) {
            sb.append("━━━━━━━━━━━\n")
            sb.append("مارينا هوتل | 9677734587456\n")
        }
        var msg = sb.toString()
        if (msg.length > 1000) msg = msg.substring(0, 997) + "..."
        return msg
    }

    fun buildPaymentWhatsAppMessage(amount: Double, remaining: Double): String? {
        val booking = _state.value.booking ?: return null
        return "عزيزي ${booking.guestName}\n" +
            "تم استلام دفعتك بقيمة ${CurrencyFormatter.formatAmount(amount)} ريال\n" +
            "رقم الغرفة: ${booking.roomNumber}\n" +
            "المبلغ المتبقي: ${CurrencyFormatter.formatAmount(remaining)} ريال\n" +
            "شكراً لاختيارك فندق مارينا\n" +
            "للاستفسار: 9677734587456"
    }

    // -------------------------------------------------------------------------

    /** رسالة واتساب تأكيد المردود — Dart `_sendRefundConfirmation` (l.2361-2398). */
    private fun buildRefundWhatsAppMessage(refundAmount: Double, unusedNights: Int): String? {
        val booking = _state.value.booking ?: return null
        val nightsWord = if (unusedNights == 1) "ليلة" else "ليالي"
        return "عزيزي ${booking.guestName}، تم تسجيل مغادرتكم المبكرة\n" +
            "رقم الغرفة: ${booking.roomNumber}\n" +
            "مبلغ المردود: ${CurrencyFormatter.formatAmount(refundAmount)} ريال\n" +
            "عدد الليالي غير المستخدمة: $unusedNights $nightsWord\n" +
            "شكراً لاختيارك فندق مارينا\n" +
            "للاستفسار: 9677734587456"
    }

    /**
     * يُدرج الدفعة ويثبّت الإيصال والرسائل — Dart نهاية `_processPayment`
     * (l.1768-1825): سناك-بار + إيصال + رسالة واتساب.
     */
    private suspend fun savePayment(
        booking: Booking,
        amount: Double,
        method: String,
        notes: String?,
        revenueType: String,
        isPendingBalance: Boolean,
        emitUi: Boolean = true
    ) {
        paymentsRepository.insert(
            Payment(
                bookingLocalId = booking.id,
                roomNumber = booking.roomNumber,
                amount = amount,
                paymentMethod = method,
                revenueType = revenueType,
                notes = notes?.takeIf { it.isNotBlank() },
                isPendingBalance = isPendingBalance
            )
        )
        pushSilently()
        if (!emitUi) return
        val remaining = (calculateCurrentTotals().remaining).coerceAtLeast(0.0)
        val phone = BookingFinancials.cleanAndFormatPhone(booking.guestPhone)
        _state.value = _state.value.copy(
            isSaving = false,
            message = "تم تسجيل دفعة بقيمة ${CurrencyFormatter.formatAmount(amount)}",
            tone = MsgTone.INFO,
            receipt = PaymentReceiptUi(
                amount = amount,
                methodLabel = PayMethodUi.fromDb(method).label,
                remaining = remaining
            ),
            whatsappMessage = if (phone.isNotBlank()) {
                buildPaymentWhatsAppMessage(amount, remaining)
            } else null
        )
    }

    /** Dart `_calculateCurrentTotals` (l.1492-1569). */
    private suspend fun calculateCurrentTotals(): PaymentTotals {
        val booking = _state.value.booking ?: return PaymentTotals(0.0, 0.0)
        val rate = _state.value.roomPrice
        val payments = paymentsRepository.getByBookingOnce(booking.id)
        val nights = nightsRepository.getByBooking(booking.id)
        val summary = BookingFinancials.calculate(booking, rate, payments, nights)
        return PaymentTotals(summary.totalAmount, summary.remainingAmount)
    }

    private suspend fun pushSilently() {
        try {
            syncRepository.syncNow()
        } catch (_: Exception) {
            // Sync failure never fails the business operation (Dart contract).
        }
    }
}
