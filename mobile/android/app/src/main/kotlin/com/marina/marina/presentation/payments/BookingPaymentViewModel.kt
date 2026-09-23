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

/** Auto-extension proposal surfaced to the UI for user confirmation (Dart l.1615-1706). */
data class ExtensionProposal(
    val amount: Double,
    val remaining: Double,
    val surplus: Double,
    val extraNights: Int
)

/** Dart `_PaymentTotals` (l.4171-4175). */
data class PaymentTotals(val total: Double, val remaining: Double)

data class BookingPaymentUiState(
    val isLoading: Boolean = false,
    val booking: Booking? = null,
    val payments: List<Payment> = emptyList(),
    val nights: List<BookingNight> = emptyList(),
    val roomPrice: Double = 0.0,
    val debtRemaining: Double = 0.0,
    val isAdmin: Boolean = false,
    val isSaving: Boolean = false,
    val error: String? = null,
    val message: String? = null,
    val finished: Boolean = false,
    /** Pending auto-extension proposal awaiting user confirmation. */
    val extensionProposal: ExtensionProposal? = null,
    /** Message to send via WhatsApp after the next successful action. */
    val whatsappMessage: String? = null
) {
    val summary: BookingFinancials.Summary?
        get() = booking?.let { BookingFinancials.calculate(it, roomPrice, payments, nights, debtRemaining) }
    val stayBalance: BookingFinancials.StayBalance?
        get() = booking?.let {
            BookingFinancials.stayBalance(it, roomPrice, summary?.paidAmount ?: 0.0)
        }
    val extendedStayActive: Boolean
        get() = booking?.let { BookingFinancials.isExtendedStayActive(it) } ?: false
    val extraNightsBeyondExpected: Int
        get() = booking?.let {
            val checkin = HotelTimeEngine.parseDate(it.checkinDate) ?: return@let 0
            (HotelTimeEngine.nightsWithCutoff(checkin) - it.expectedNights).coerceAtLeast(0)
        } ?: 0
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
            val debtRemaining = debts
                .filter { it.bookingLocalId == booking.id && !it.isSettled && it.remainingAmount > 0 }
                .sumOf { it.remainingAmount }

            // Derived-fields refresh (Dart refreshForBookingId with
            // enqueueOutbox:false) — only writes when a cached value actually
            // changed so the outbox is not spammed by screen opens.
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
                // Dart refreshForBookingId(enqueueOutbox: false) — display-only.
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
        _state.value = _state.value.copy(message = null, error = null, whatsappMessage = null)
    }

    fun dismissExtensionProposal() {
        _state.value = _state.value.copy(extensionProposal = null)
    }

    /**
     * Dart `_processPayment` (l.1571-1830). Entry point: validates, then
     * either surfaces an auto-extension proposal (surplus over remaining) or
     * saves the payment directly. [isPendingBalance] skips the
     * auto-extension branch entirely (رصيد تراكمي).
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
            _state.value = _state.value.copy(message = "يرجى إدخال مبلغ صحيح")
            return
        }
        if (amount % 1.0 != 0.0) {
            _state.value = _state.value.copy(message = "المبلغ يجب أن يكون بدون كسور")
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
                            message = "لا يمكن حساب الليالي الإضافية — سعر الغرفة غير محدد"
                        )
                        return@launch
                    }
                    val extraNights = kotlin.math.ceil(surplus / rate).toInt()
                    _state.value = _state.value.copy(
                        extensionProposal = ExtensionProposal(amount, totals.remaining, surplus, extraNights)
                    )
                } else {
                    savePayment(booking, amount, method, notes, revenueType, isPendingBalance)
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "تعذّر تسجيل الدفعة: ${e.message}")
            }
        }
    }

    /** User confirmed the "تسجيل دفعة مع تمديد" dialog — extend + pay atomically. */
    fun confirmExtensionAndPay(method: String, notes: String?) {
        val proposal = _state.value.extensionProposal ?: return
        val booking = _state.value.booking ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, extensionProposal = null)
            try {
                val extraNights = proposal.extraNights
                // Dart l.1698-1704: (checkoutDate ?? now + 1 day) + extraNights —
                // a booking without a planned checkout still gets one on extension.
                val baseCheckout = HotelTimeEngine.parseDate(booking.checkoutDate)
                    ?: (System.currentTimeMillis() + 24L * 3600 * 1000)
                val newCheckout = java.util.Calendar.getInstance().apply {
                    timeInMillis = baseCheckout
                    add(java.util.Calendar.DAY_OF_YEAR, extraNights)
                }.timeInMillis
                val newExpected = booking.expectedNights + extraNights
                val updated = booking.copy(
                    checkoutDate = HotelTimeEngine.formatIso(newCheckout),
                    expectedNights = newExpected,
                    notes = (booking.notes ?: "") + "\nتمديد تلقائي: $extraNights ليلة/ليالي"
                )
                bookingsRepository.update(updated)
                savePayment(updated, proposal.amount, method, notes, "room", false)
                _state.value = _state.value.copy(
                    isSaving = false,
                    message = "تم تسجيل دفعة بقيمة ${CurrencyFormatter.formatAmount(proposal.amount)}",
                    whatsappMessage = buildExtensionWhatsAppMessage(extraNights, proposal.amount, newCheckout)
                )
                pushSilently()
            } catch (e: Exception) {
                _state.value = _state.value.copy(isSaving = false, error = "تعذّر تسجيل الدفعة: ${e.message}")
            }
        }
    }

    /** Dart `_processDailyPayment` (l.1377-1446) — pay N extra nights. */
    fun processDailyPayment(nightsCount: Int) {
        val booking = _state.value.booking ?: return
        val rate = _state.value.roomPrice
        if (nightsCount <= 0 || rate <= 0) return
        val amount = nightsCount * rate
        val note = if (nightsCount == 1) "دفع ليلة إضافية واحدة" else "دفع $nightsCount ليالي إضافية"
        viewModelScope.launch {
            try {
                savePayment(booking, amount, "نقدي", note, "room", false)
                _state.value = _state.value.copy(
                    message = "تم تسجيل دفع $nightsCount ليلة/ليالي إضافية - ${CurrencyFormatter.formatAmount(amount)}",
                    whatsappMessage = buildPaymentWhatsAppMessage(amount)
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "تعذّر تسجيل الدفعة: ${e.message}")
            }
        }
    }

    /** Dart `_processExtendStay` (l.4010-4109). */
    fun extendStay(additionalNights: Int) {
        val booking = _state.value.booking ?: return
        val rate = _state.value.roomPrice
        if (additionalNights <= 0 || rate <= 0) {
            _state.value = _state.value.copy(message = "يرجى إدخال عدد ليالي صحيح وسعر غرفة صحيح")
            return
        }
        viewModelScope.launch {
            try {
                // Dart l.4033-4039: (checkoutDate ?? now + 1 day) + additionalNights.
                val baseCheckout = HotelTimeEngine.parseDate(booking.checkoutDate)
                    ?: (System.currentTimeMillis() + 24L * 3600 * 1000)
                val newCheckout = java.util.Calendar.getInstance().apply {
                    timeInMillis = baseCheckout
                    add(java.util.Calendar.DAY_OF_YEAR, additionalNights)
                }.timeInMillis
                val updated = booking.copy(
                    checkoutDate = HotelTimeEngine.formatIso(newCheckout),
                    expectedNights = booking.expectedNights + additionalNights,
                    notes = (booking.notes ?: "") + "\nتمديد: $additionalNights ليلة/ليالي"
                )
                bookingsRepository.update(updated)
                val amount = additionalNights * rate
                val note = if (additionalNights == 1) "تمديد 1 ليلة إضافية" else "تمديد $additionalNights ليالي إضافية"
                savePayment(updated, amount, "نقدي", note, "room", false)
                _state.value = _state.value.copy(
                    message = "تم تمديد الإقامة $additionalNights ليلة/ليالي وتسجيل الدفعة",
                    whatsappMessage = buildExtensionWhatsAppMessage(additionalNights, amount, newCheckout)
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "تعذّر تسجيل الدفعة: ${e.message}")
            }
        }
    }

    /** Dart `_processCheckout` (l.2715-2795). */
    fun completeCheckout() {
        val booking = _state.value.booking ?: return
        viewModelScope.launch {
            try {
                val now = System.currentTimeMillis()
                val checkinMillis = HotelTimeEngine.parseDate(booking.checkinDate) ?: now
                val finalNights = HotelTimeEngine.nightsWithCutoff(checkinMillis, now)
                // Single write (Dart repo.update): status + actualCheckout +
                // calculatedNights land together, and the outbox entry is the
                // single cloud change. The old double checkout()+update() wrote
                // the row twice with two different column sets.
                bookingsRepository.update(
                    booking.copy(
                        status = "مكتمل",
                        actualCheckout = HotelTimeEngine.formatIso(now),
                        calculatedNights = finalNights
                    )
                )
                roomsRepository.getByNumber(booking.roomNumber)?.let { room ->
                    if (StatusUtils.isRoomOccupied(room.status)) {
                        roomsRepository.update(room.copy(status = "شاغرة"))
                    }
                }
                pushSilently()
                _state.value = _state.value.copy(
                    message = "تم تسجيل المغادرة بنجاح وتحرير الغرفة",
                    finished = true
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "تعذّر تسجيل المغادرة: ${e.message}")
            }
        }
    }

    /**
     * Dart `_processEarlyCheckout` (l.2255-2358): booking → مكتمل, refund
     * inserted as a NEGATIVE payment, room freed.
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
                    // Dart l.2255-2358 records the refund as a NEGATIVE integer
                    // payment (-round(refund)).
                    val refund = kotlin.math.round(refundAmount).toDouble()
                    savePayment(
                        booking.copy(status = "مكتمل"),
                        -refund,
                        "نقدي",
                        "مردود مغادرة مبكرة - $unusedNights ليلة/ليالي غير مستخدمة",
                        "room",
                        false
                    )
                }
                roomsRepository.getByNumber(booking.roomNumber)?.let { room ->
                    if (StatusUtils.isRoomOccupied(room.status)) {
                        roomsRepository.update(room.copy(status = "شاغرة"))
                    }
                }
                pushSilently()
                _state.value = _state.value.copy(
                    message = if (refundAmount > 0) {
                        "تم تسجيل مغادرة مبكرة — المردود: ${CurrencyFormatter.formatAmount(refundAmount)} ($unusedNights ليلة/ليالي)"
                    } else {
                        "تم تسجيل المغادرة بنجاح وتحرير الغرفة"
                    },
                    finished = true,
                    whatsappMessage = if (refundAmount > 0) {
                        "تم تسجيل مغادرتكم المبكرة\nمبلغ المردود: ${CurrencyFormatter.formatAmount(refundAmount)} ريال\nعدد الليالي غير المستخدمة: $unusedNights"
                    } else null
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "تعذّر تسجيل المغادرة: ${e.message}")
            }
        }
    }

    /** Dart `_processCancelTodayPayments` (l.2967-3005) — soft-delete today's payments. */
    fun cancelTodayPayments() {
        viewModelScope.launch {
            try {
                val hotelDay = HotelTimeEngine.currentHotelDayKey()
                val todays = _state.value.payments.filter { p ->
                    !p.isVoided && (p.hotelDayKey == hotelDay ||
                        (p.hotelDayKey == null && p.paymentDate.startsWith(hotelDay)))
                }
                if (todays.isEmpty()) {
                    _state.value = _state.value.copy(message = "لا توجد دفعات اليوم")
                    return@launch
                }
                todays.forEach { paymentsRepository.softDelete(it.id) }
                pushSilently()
                _state.value = _state.value.copy(message = "تم إلغاء ${todays.size} دفعة بنجاح")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "تعذّر إلغاء الدفعات: ${e.message}")
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
                        note = "تم إنشاء هذا الدين تلقائياً من شاشة المدفوعات عند وجود مبلغ متبقي لدى النزيل."
                    )
                )
                pushSilently()
                _state.value = _state.value.copy(
                    message = "تم إنشاء دين بقيمة ${CurrencyFormatter.formatAmount(remaining)} وإضافته إلى قائمة الديون"
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "تعذّر إنشاء الدين: ${e.message}")
            }
        }
    }

    /**
     * Dart `_showDiscountAmountDialog` / apply (l.2521-2695): admin-only,
     * additive to the existing discount, type 'total'.
     */
    fun applyAdminDiscount(amount: Double) {
        val booking = _state.value.booking ?: return
        val summary = _state.value.summary ?: return
        if (amount <= 0) {
            _state.value = _state.value.copy(message = "المبلغ غير صالح")
            return
        }
        if (amount > summary.remainingAmount) {
            _state.value = _state.value.copy(
                message = "مبلغ الخصم يتجاوز المتبقي (${CurrencyFormatter.formatAmount(summary.remainingAmount)})"
            )
            return
        }
        viewModelScope.launch {
            try {
                val newDiscount = booking.discount + amount
                bookingsRepository.update(booking.copy(discount = newDiscount, discountType = "total"))
                pushSilently()
                _state.value = _state.value.copy(
                    message = "تم خصم ${CurrencyFormatter.formatAmount(amount)} من الليالي الفعلية. المتبقي الجديد: ${CurrencyFormatter.formatAmount((summary.remainingAmount - amount).coerceAtLeast(0.0))}"
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "تعذّر تطبيق الخصم: ${e.message}")
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
                    sb.append("+ ${sorted.size - index} دفعات أخرى...\n")
                    return@forEachIndexed
                }
                sb.append("${index + 1}. ${CurrencyFormatter.formatAmount(p.amount)} ريال | ${p.paymentMethod} | ${p.paymentDate.take(16).replace("T", " ")}\n")
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

    /** Dart `_sendPaymentReminder` (l.3842-3906). */
    fun buildPaymentReminder(): String? {
        val booking = _state.value.booking ?: return null
        val summary = _state.value.summary ?: return null
        return "عزيزي ${booking.guestName}\n" +
            "الإجمالي: ${CurrencyFormatter.formatAmount(summary.totalAmount)} ريال\n" +
            "المدفوع: ${CurrencyFormatter.formatAmount(summary.paidAmount)} ريال\n" +
            "المبلغ المتبقي: ${CurrencyFormatter.formatAmount(summary.remainingAmount)} ريال\n" +
            "نرجو منكم تسديد المبلغ المتبقي في أقرب وقت ممكن\n" +
            "شكراً لاختيارك فندق مارينا\nللاستفسار: 9677734587456"
    }

    fun buildPaymentWhatsAppMessage(amount: Double, remaining: Double): String? {
        val booking = _state.value.booking ?: return null
        return "عزيزي ${booking.guestName}\n" +
            "تم استلام دفعتك بقيمة ${CurrencyFormatter.formatAmount(amount)} ريال\n" +
            "رقم الغرفة: ${booking.roomNumber}\n" +
            "المبلغ المتبقي: ${CurrencyFormatter.formatAmount(remaining)} ريال\n" +
            "شكراً لاختيارك فندق مارينا\nللاستفسار: 9677734587456"
    }

    fun setAdmin(isAdmin: Boolean) {
        _state.value = _state.value.copy(isAdmin = isAdmin)
    }

    // -------------------------------------------------------------------------

    private fun buildPaymentWhatsAppMessage(amount: Double): String? {
        val remaining = (_state.value.summary?.remainingAmount ?: 0.0)
        return buildPaymentWhatsAppMessage(amount, remaining)
    }

    private fun buildExtensionWhatsAppMessage(extraNights: Int, amount: Double, newCheckout: Long?): String? {
        val booking = _state.value.booking ?: return null
        return "تم تمديد إقامتكم\n" +
            "ليالي إضافية: $extraNights\n" +
            "المبلغ المدفوع: ${CurrencyFormatter.formatAmount(amount)}\n" +
            "تاريخ المغادرة الجديد: " +
            (newCheckout?.let {
                java.util.Calendar.getInstance().apply { timeInMillis = it }.let { c ->
                    "${c.get(java.util.Calendar.DAY_OF_MONTH)}/${c.get(java.util.Calendar.MONTH) + 1}/${c.get(java.util.Calendar.YEAR)}"
                }
            } ?: "—")
    }

    /**
     * Inserts the payment, refreshes the booking financial cache and pushes
     * to the cloud (Dart single-transaction path l.1713-1767).
     */
    private suspend fun savePayment(
        booking: Booking,
        amount: Double,
        method: String,
        notes: String?,
        revenueType: String,
        isPendingBalance: Boolean
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
        if (!isPendingBalance) {
            val remaining = (calculateCurrentTotals().remaining).coerceAtLeast(0.0)
            val phone = BookingFinancials.cleanAndFormatPhone(booking.guestPhone)
            _state.value = _state.value.copy(
                message = "تم تسجيل دفعة بقيمة ${CurrencyFormatter.formatAmount(amount)}",
                whatsappMessage = if (phone.isNotBlank()) buildPaymentWhatsAppMessage(amount, remaining) else null
            )
        } else {
            _state.value = _state.value.copy(message = "تم تسجيل الدفعة")
        }
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
