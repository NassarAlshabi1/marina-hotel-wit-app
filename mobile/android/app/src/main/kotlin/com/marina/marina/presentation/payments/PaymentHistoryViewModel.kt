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

/**
 * تاريخ المدفوعات — 1:1 port of `payment_history_screen.dart`:
 * watchAll (voided included), filters = revenueType (4) + method (نقدي/تحويل)
 * + date range, total banner sums the filtered list.
 */
data class PaymentHistoryUiState(
    val isLoading: Boolean = true,
    val payments: List<Payment> = emptyList(),
    val bookingFilter: Long? = null,
    val selectedRevenueType: String? = null,
    val selectedPaymentMethod: String? = null,
    val fromDate: Long? = null,
    val toDate: Long? = null,
    val error: String? = null
) {
    val visible: List<Payment>
        get() {
            var list = payments
            bookingFilter?.let { id -> list = list.filter { it.bookingLocalId == id } }
            selectedRevenueType?.let { type -> list = list.filter { it.revenueType == type } }
            selectedPaymentMethod?.let { method -> list = list.filter { it.paymentMethod == method } }
            fromDate?.let { from ->
                list = list.filter { p ->
                    val t = HotelTimeEngine.parseDate(p.paymentDate)
                    t == null || t >= from
                }
            }
            toDate?.let { to ->
                list = list.filter { p ->
                    val t = HotelTimeEngine.parseDate(p.paymentDate)
                    t == null || t <= to
                }
            }
            return list.sortedByDescending { it.paymentDate }
        }

    /** Dart l.180-218 — total banner sums the visible (filtered) list. */
    val totalAmount: Double get() = visible.sumOf { it.amount }

    val hasActiveFilters: Boolean
        get() = selectedRevenueType != null || selectedPaymentMethod != null ||
            fromDate != null || toDate != null
}

@HiltViewModel
class PaymentHistoryViewModel @Inject constructor(
    private val paymentsRepository: PaymentsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(PaymentHistoryUiState())
    val state: StateFlow<PaymentHistoryUiState> = _state.asStateFlow()

    init {
        // Dart watchAll() — voided payments stay visible in the history.
        paymentsRepository.getAllIncludingVoided().onEach { payments ->
            _state.value = _state.value.copy(isLoading = false, payments = payments)
        }.launchIn(viewModelScope)
    }

    fun filterBooking(id: Long?) {
        _state.value = _state.value.copy(bookingFilter = id)
    }

    fun setRevenueType(type: String?) {
        _state.value = _state.value.copy(selectedRevenueType = type)
    }

    fun setMethod(method: String?) {
        _state.value = _state.value.copy(selectedPaymentMethod = method)
    }

    fun setDateRange(from: Long?, to: Long?) {
        _state.value = _state.value.copy(fromDate = from, toDate = to)
    }

    fun clearFilters() {
        _state.value = _state.value.copy(
            selectedRevenueType = null,
            selectedPaymentMethod = null,
            fromDate = null,
            toDate = null
        )
    }

    fun consumeError() {
        _state.value = _state.value.copy(error = null)
    }
}
