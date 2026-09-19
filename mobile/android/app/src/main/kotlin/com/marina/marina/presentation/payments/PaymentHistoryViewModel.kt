package com.marina.marina.presentation.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.model.PaymentVoid
import com.marina.marina.domain.repository.PaymentVoidsRepository
import com.marina.marina.domain.repository.PaymentsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class PaymentHistoryUiState(
    val isLoading: Boolean = true,
    val payments: List<Payment> = emptyList(),
    val voids: List<PaymentVoid> = emptyList(),
    val bookingFilter: Long? = null,
    val showVoidedOnly: Boolean = false,
    val error: String? = null
) {
    val visible: List<Payment>
        get() {
            var list = payments
            bookingFilter?.let { id -> list = list.filter { it.bookingLocalId == id } }
            if (showVoidedOnly) list = list.filter { it.isVoided }
            return list.sortedByDescending { it.createdAt }
        }
}

@HiltViewModel
class PaymentHistoryViewModel @Inject constructor(
    private val paymentsRepository: PaymentsRepository,
    private val voidsRepository: PaymentVoidsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(PaymentHistoryUiState())
    val state: StateFlow<PaymentHistoryUiState> = _state.asStateFlow()

    init {
        paymentsRepository.getAll().onEach { payments ->
            _state.value = _state.value.copy(isLoading = false, payments = payments)
        }.launchIn(viewModelScope)
        voidsRepository.getAll().onEach { voids ->
            _state.value = _state.value.copy(voids = voids)
        }.launchIn(viewModelScope)
    }

    fun filterBooking(id: Long?) { _state.value = _state.value.copy(bookingFilter = id) }

    fun toggleVoidedOnly() { _state.value = _state.value.copy(showVoidedOnly = !_state.value.showVoidedOnly) }

    fun voidPayment(payment: Payment, reason: String, by: String, hotelDayKey: String) {
        viewModelScope.launch {
            try {
                voidsRepository.voidPayment(
                    PaymentVoid(
                        originalPaymentUuid = payment.localUuid,
                        originalPaymentId = payment.id,
                        bookingUuid = "",
                        voidedAmount = payment.amount.toLong(),
                        voidReason = reason,
                        voidedBy = by,
                        voidedAt = System.currentTimeMillis(),
                        voidedAtIso = "",
                        hotelDayKey = hotelDayKey
                    )
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
