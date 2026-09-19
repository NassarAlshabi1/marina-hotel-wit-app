package com.marina.marina.presentation.finance

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
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

data class RoomPaymentGroup(
    val roomNumber: String,
    val payments: List<Payment>,
    val total: Double
)

data class FinanceUiState(
    val isLoading: Boolean = false,
    val hotelDayKey: String = "",
    val isAfterCutoff: Boolean = false,
    val todayIncome: Double = 0.0,
    val todayExpenses: Double = 0.0,
    val todayPaymentsCount: Int = 0,
    val roomGroups: List<RoomPaymentGroup> = emptyList(),
    val generalPayments: List<Payment> = emptyList(),
    val activeBookings: List<Booking> = emptyList(),
    val roomRemaining: Map<String, Double> = emptyMap(),
    val error: String? = null,
    val message: String? = null
) {
    val balance: Double get() = todayIncome - todayExpenses
    val isDeficit: Boolean get() = balance < 0
}

@HiltViewModel
class FinanceViewModel @Inject constructor(
    private val paymentsRepository: PaymentsRepository,
    private val expensesRepository: ExpensesRepository,
    private val bookingsRepository: BookingsRepository,
    private val roomsRepository: RoomsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(FinanceUiState(isLoading = true))
    val state: StateFlow<FinanceUiState> = _state.asStateFlow()

    init {
        combine(
            paymentsRepository.getAll(),
            expensesRepository.getAll(),
            bookingsRepository.getAll(),
            roomsRepository.getAll()
        ) { payments, expenses, bookings, rooms ->
            val todayKey = HotelTimeEngine.currentHotelDayKey()

            val todayPayments = payments.filter { it.hotelDayKey == todayKey }
            val todayExpensesList = expenses.filter { it.hotelDayKey == todayKey }

            val priceByRoom = rooms.associate { it.roomNumber to it.price }
            val active = bookings.filter { StatusUtils.isBookingActive(it.status) }

            // Payments grouped by room (Flutter parity: "today's payments grouped by room").
            val grouped = todayPayments.filter { !it.roomNumber.isNullOrBlank() }
                .groupBy { it.roomNumber!! }
                .map { (room, list) -> RoomPaymentGroup(room, list, list.sumOf { it.amount }) }
                .sortedByDescending { it.total }

            val general = todayPayments.filter { it.roomNumber.isNullOrBlank() }

            // Remaining per active booking (denormalized cache first, recomputed fallback).
            val remaining = active.associate { booking ->
                val cached = booking.remainingBalanceCached
                val price = priceByRoom[booking.roomNumber] ?: 0.0
                val nights = if (booking.calculatedNights > 0) booking.calculatedNights else booking.expectedNights
                val paidForBooking = payments.filter { it.bookingLocalId == booking.id }.sumOf { it.amount }
                val due = if (cached > 0) booking.totalDueCached else nights * price - booking.discount
                booking.roomNumber to (due - paidForBooking).coerceAtLeast(0.0)
            }

            FinanceUiState(
                isLoading = false,
                hotelDayKey = todayKey,
                isAfterCutoff = HotelTimeEngine.isAfterCutoff(System.currentTimeMillis()),
                todayIncome = todayPayments.sumOf { it.amount },
                todayExpenses = todayExpensesList.sumOf { it.amount },
                todayPaymentsCount = todayPayments.size,
                roomGroups = grouped,
                generalPayments = general,
                activeBookings = active.sortedBy { it.roomNumber },
                roomRemaining = remaining,
                error = null
            )
        }.onEach { newState ->
            _state.value = newState.copy(message = _state.value.message)
        }.launchIn(viewModelScope)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    /** Quick standalone payment recorded at the cash desk. */
    fun addQuickPayment(amount: Double, method: String, notes: String?) {
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
