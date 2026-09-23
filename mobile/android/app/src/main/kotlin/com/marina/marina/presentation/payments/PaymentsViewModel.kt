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
    /** Active bookings — Dart tab 3 (الحجوزات النشطة). */
    val activeBookings: List<Booking> = emptyList(),
    val searchQuery: String = "",
    val methodFilter: String = "all",
    val revenueFilter: String = "all",
    val error: String? = null,
    val message: String? = null
) {
    private val todayKey: String = HotelTimeEngine.currentHotelDayKey()

    val filtered: List<Payment>
        get() {
            var list = payments
            if (methodFilter != "all") list = list.filter { it.paymentMethod == methodFilter }
            if (revenueFilter != "all") list = list.filter { it.revenueType == revenueFilter }
            val q = searchQuery.trim()
            if (q.isNotBlank()) {
                list = list.filter {
                    (it.roomNumber ?: "").contains(q) ||
                        it.amount.toInt().toString() == q ||
                        (it.notes ?: "").contains(q, ignoreCase = true)
                }
            }
            return list
        }

    /** Dart l.163-174: today's payments exclude voided; legacy fallback on paymentDate prefix. */
    val todayPayments: List<Payment>
        get() = payments.filter {
            !it.isVoided && (it.hotelDayKey == todayKey ||
                (it.hotelDayKey == null && it.paymentDate.startsWith(todayKey)))
        }

    val todayTotal: Double get() = todayPayments.sumOf { it.amount }
    val todayCount: Int get() = todayPayments.size

    /** Dart l.160 quirk: the grand-total stat card sums ALL payments (voided included). */
    val grandTotal: Double get() = payments.sumOf { it.amount }

    /** Dart l.181-192: month stat parses paymentDate and keeps payments at/after
     * the current month start (00:00 of day 1). Voided included. A payment taken
     * at 00:30 on the 1st still belongs to the CURRENT month (unlike the hotel-day
     * key, which would attribute it to the previous month). */
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

    /** Dart late windows: 22:00-23:00 warning, 23:00-05:00 overdue. */
    val lateWindow: LateWindow
        get() {
            val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
            return when {
                hour >= 22 && hour < 23 -> LateWindow.WARNING
                hour >= 23 || hour < 5 -> LateWindow.OVERDUE
                else -> LateWindow.NONE
            }
        }
}

enum class LateWindow { NONE, WARNING, OVERDUE }

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
            payments to bookings.filter { StatusUtils.isBookingActive(it.status) }
        }.onEach { (payments, activeBookings) ->
            _state.value = _state.value.copy(
                isLoading = false,
                payments = payments,
                activeBookings = activeBookings,
                error = null
            )
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }

    fun setMethodFilter(method: String) {
        _state.value = _state.value.copy(methodFilter = method)
    }

    fun setRevenueFilter(revenue: String) {
        _state.value = _state.value.copy(revenueFilter = revenue)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null, error = null)
    }

    /** Dart `_saveStandalonePayment` (l.831-913) — revenueType 'other', no booking. */
    fun addStandalonePayment(amount: Double, method: String, notes: String?, reference: String?) {
        if (amount <= 0) {
            _state.value = _state.value.copy(message = "يرجى إدخال مبلغ صحيح")
            return
        }
        viewModelScope.launch {
            try {
                paymentsRepository.insert(
                    Payment(
                        amount = amount,
                        paymentMethod = method,
                        revenueType = "other",
                        notes = notes,
                        referenceNumber = reference
                    )
                )
                try { syncRepository.syncNow() } catch (_: Exception) { }
                _state.value = _state.value.copy(
                    message = "تم تسجيل الدفعة ${CurrencyFormatter.formatAmount(amount)} بنجاح"
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "فشل تسجيل الدفعة: ${e.message}")
            }
        }
    }
}
