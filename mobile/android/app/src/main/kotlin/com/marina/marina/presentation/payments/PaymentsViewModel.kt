package com.marina.marina.presentation.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class PaymentsUiState(
    val isLoading: Boolean = false,
    val payments: List<Payment> = emptyList(),
    /** كل الحجوزات (للتفريق بين «لا حجوزات» و«كل الحجوزات مكتملة» في Dart). */
    val allBookings: List<Booking> = emptyList(),
    /** Active bookings — Dart tab 3 (الحجوزات النشطة). */
    val activeBookings: List<Booking> = emptyList(),
    val isSaving: Boolean = false,
    val tone: MsgTone = MsgTone.INFO,
    val error: String? = null,
    val message: String? = null
) {
    private val todayKey: String = HotelTimeEngine.currentHotelDayKey()

    /** Dart l.147-161: today's payments exclude voided; legacy fallback on paymentDate prefix. */
    val todayPayments: List<Payment>
        get() = payments.filter {
            !it.isVoided && (it.hotelDayKey == todayKey ||
                (it.hotelDayKey == null && it.paymentDate.startsWith(todayKey)))
        }

    val todayTotal: Double get() = todayPayments.sumOf { it.amount }

    /** Dart l.160 quirk: the grand-total stat card sums ALL payments (voided included). */
    val grandTotal: Double get() = payments.sumOf { it.amount }

    /** Dart l.181-192: month stat keeps payments at/after the current month start. */
    val monthTotal: Double
        get() {
            val cal = java.util.Calendar.getInstance()
            cal.set(java.util.Calendar.DAY_OF_MONTH, 1)
            cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
            cal.set(java.util.Calendar.MINUTE, 0)
            cal.set(java.util.Calendar.SECOND, 0)
            cal.set(java.util.Calendar.MILLISECOND, 0)
            val monthStart = cal.timeInMillis
            return payments.filter {
                HotelTimeEngine.parseDate(it.paymentDate)?.let { t -> t >= monthStart } ?: false
            }.sumOf { it.amount }
        }

    /** Dart l.328-338: today's payments sorted desc by paymentDate, take(10). */
    val recentTodayPayments: List<Payment>
        get() = todayPayments.sortedByDescending { it.paymentDate }.take(10)
}

@HiltViewModel
class PaymentsViewModel @Inject constructor(
    private val paymentsRepository: PaymentsRepository,
    private val bookingsRepository: BookingsRepository,
    private val syncRepository: SyncRepository
) : ViewModel() {

    private val _state = MutableStateFlow(PaymentsUiState(isLoading = true))
    val state: StateFlow<PaymentsUiState> = _state.asStateFlow()

    init {
        // Dart payments_main: watchAll() (voided included) + watchList() filtered to active.
        combine(
            paymentsRepository.getAllIncludingVoided(),
            bookingsRepository.getAll()
        ) { payments, bookings ->
            payments to bookings
        }.onEach { (payments, bookings) ->
            _state.value = _state.value.copy(
                isLoading = false,
                payments = payments,
                allBookings = bookings,
                activeBookings = bookings.filter { StatusUtils.isBookingActive(it.status) },
                error = null
            )
        }.launchIn(viewModelScope)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null, error = null)
    }

    /**
     * Dart `_saveStandalonePayment` (l.831-913) — revenueType 'other', no booking.
     * رقم المرجع يُجمع في الحوار لكن Dart لا يخزّنه في الدفعة المستقلة.
     */
    fun addStandalonePayment(amount: Double, method: String, notes: String?, reference: String?) {
        if (amount <= 0) {
            _state.value = _state.value.copy(
                message = "يرجى إدخال مبلغ صحيح",
                tone = MsgTone.ERROR
            )
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true)
            try {
                paymentsRepository.insert(
                    Payment(
                        amount = amount,
                        paymentMethod = method,
                        revenueType = "other",
                        notes = notes
                    )
                )
                try { syncRepository.syncNow() } catch (_: Exception) { }
                _state.value = _state.value.copy(
                    isSaving = false,
                    message = "تم تسجيل الدفعة ${CurrencyFormatter.formatAmount(amount)} بنجاح",
                    tone = MsgTone.SUCCESS
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    error = "فشل تسجيل الدفعة: ${e.message}",
                    tone = MsgTone.ERROR
                )
            }
        }
    }
}
