package com.marina.marina.presentation.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class PaymentsUiState(
    val isLoading: Boolean = false,
    val payments: List<Payment> = emptyList(),
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

    val todayTotal: Double get() = payments.filter { it.hotelDayKey == todayKey }.sumOf { it.amount }
    val todayCount: Int get() = payments.count { it.hotelDayKey == todayKey }
    val monthTotal: Double
        get() {
            val monthPrefix = todayKey.take(7)
            return payments.filter { (it.hotelDayKey ?: "").startsWith(monthPrefix) }.sumOf { it.amount }
        }
    val grandTotal: Double get() = payments.sumOf { it.amount }
}

@HiltViewModel
class PaymentsViewModel @Inject constructor(
    private val paymentsRepository: PaymentsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(PaymentsUiState(isLoading = true))
    val state: StateFlow<PaymentsUiState> = _state.asStateFlow()

    init {
        paymentsRepository.getAll().onEach { payments ->
            _state.value = _state.value.copy(isLoading = false, payments = payments, error = null)
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
        _state.value = _state.value.copy(message = null)
    }

    /** Standalone (booking-less) payment — revenueType 'other' like the Flutter app. */
    fun addStandalonePayment(amount: Double, method: String, notes: String?) {
        if (amount <= 0) {
            _state.value = _state.value.copy(message = "المبلغ غير صالح")
            return
        }
        viewModelScope.launch {
            try {
                paymentsRepository.insert(
                    Payment(
                        amount = amount,
                        paymentMethod = method,
                        revenueType = "other",
                        notes = notes
                    )
                )
                _state.value = _state.value.copy(message = "تم تسجيل الدفعة")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
