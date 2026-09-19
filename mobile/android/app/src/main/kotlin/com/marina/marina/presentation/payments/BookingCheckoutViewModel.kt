package com.marina.marina.presentation.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.BookingNight
import com.marina.marina.domain.model.BookingPriceAdjustment
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.BookingNightsRepository
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.PaymentsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class CheckoutUiState(
    val isLoading: Boolean = true,
    val booking: Booking? = null,
    val nights: List<BookingNight> = emptyList(),
    val adjustments: List<BookingPriceAdjustment> = emptyList(),
    val payments: List<Payment> = emptyList(),
    val checkedOut: Boolean = false,
    val error: String? = null
) {
    val nightsTotal: Double get() = nights.sumOf { it.finalRate }
    val adjustmentsTotal: Double get() = adjustments.filter { it.isActive }.sumOf { it.amount }
    val grandTotal: Double get() = (booking?.totalDueCached ?: 0.0) + nightsTotal + adjustmentsTotal
    val paidTotal: Double get() = payments.sumOf { it.amount }
    val remaining: Double get() = grandTotal - paidTotal
}

@HiltViewModel
class BookingCheckoutViewModel @Inject constructor(
    private val bookingsRepository: BookingsRepository,
    private val paymentsRepository: PaymentsRepository,
    private val nightsRepository: BookingNightsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(CheckoutUiState())
    val state: StateFlow<CheckoutUiState> = _state.asStateFlow()

    fun load(bookingId: Long) {
        viewModelScope.launch {
            try {
                val booking = bookingsRepository.getById(bookingId)
                val nights = nightsRepository.getByBooking(bookingId)
                val adjustments = booking?.let { nightsRepository.getActiveAdjustments(it.localUuid) }.orEmpty()
                _state.value = CheckoutUiState(
                    isLoading = false, booking = booking, nights = nights,
                    adjustments = adjustments, payments = emptyList()
                )
            } catch (e: Exception) {
                _state.value = CheckoutUiState(isLoading = false, error = e.message)
            }
        }
    }

    fun checkout(actualCheckout: String?) {
        val booking = _state.value.booking ?: return
        viewModelScope.launch {
            try {
                bookingsRepository.checkout(booking.id, status = "checked_out", actualCheckout = actualCheckout)
                _state.value = _state.value.copy(checkedOut = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
