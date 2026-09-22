package com.marina.marina.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

/**
 * تذكير المتبقي — port of `active_bookings_reminder_screen.dart`:
 * active bookings with a remaining balance; per-booking WhatsApp reminder.
 */
data class BookingsReminderUiState(
    val isLoading: Boolean = true,
    val bookings: List<Booking> = emptyList()
) {
    val withRemaining: List<Booking>
        get() = bookings.filter { StatusUtils.isBookingActive(it.status) && it.remainingBalanceCached > 0 }
}

@HiltViewModel
class BookingsReminderViewModel @Inject constructor(
    private val bookingsRepository: BookingsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(BookingsReminderUiState())
    val state: StateFlow<BookingsReminderUiState> = _state.asStateFlow()

    init {
        bookingsRepository.getAll().onEach { bookings ->
            _state.value = _state.value.copy(isLoading = false, bookings = bookings)
        }.launchIn(viewModelScope)
    }
}
