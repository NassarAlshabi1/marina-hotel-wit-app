package com.marina.marina.presentation.debts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class CreateDebtUiState(
    val isLoading: Boolean = true,
    val booking: Booking? = null,
    val saved: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class CreateDebtFromBookingViewModel @Inject constructor(
    private val bookingsRepository: BookingsRepository,
    private val debtsRepository: DebtsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(CreateDebtUiState())
    val state: StateFlow<CreateDebtUiState> = _state.asStateFlow()

    fun load(bookingId: Long) {
        viewModelScope.launch {
            try {
                _state.value = CreateDebtUiState(isLoading = false, booking = bookingsRepository.getById(bookingId))
            } catch (e: Exception) {
                _state.value = CreateDebtUiState(isLoading = false, error = e.message)
            }
        }
    }

    fun saveDebt(amount: Double, reason: String, paymentDate: String) {
        val booking = _state.value.booking ?: return
        viewModelScope.launch {
            try {
                debtsRepository.insert(
                    Debt(
                        bookingLocalId = booking.id,
                        guestName = booking.guestName,
                        guestPhone = booking.guestPhone,
                        checkinDate = booking.checkinDate,
                        checkoutDate = booking.checkoutDate.orEmpty(),
                        dateRecorded = paymentDate,
                        debtReason = reason,
                        totalAmount = amount,
                        paidAmount = 0.0,
                        remainingAmount = amount,
                        paymentDate = paymentDate
                    )
                )
                _state.value = _state.value.copy(saved = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
