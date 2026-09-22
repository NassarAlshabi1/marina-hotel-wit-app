package com.marina.marina.presentation.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
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

/**
 * التقارير (hub) — 1:1 port of `reports_screen.dart`:
 * quick financial summary for the current hotel day (income / expenses /
 * net) + occupancy + shortcuts to the six report screens.
 */
data class ReportsHubUiState(
    val isLoading: Boolean = true,
    val hotelDayKey: String = "",
    val income: Double = 0.0,
    val expenses: Double = 0.0,
    val net: Double = 0.0,
    val totalRooms: Int = 0,
    val occupiedRooms: Int = 0,
    val activeBookings: Int = 0,
    val unsettledDebts: Int = 0,
    val unsettledDebtsTotal: Double = 0.0,
    val error: String? = null
) {
    val occupancyPercent: Int
        get() = if (totalRooms > 0) (occupiedRooms * 100 / totalRooms) else 0
}

@HiltViewModel
class ReportsHubViewModel @Inject constructor(
    private val paymentsRepository: PaymentsRepository,
    private val expensesRepository: ExpensesRepository,
    private val bookingsRepository: BookingsRepository,
    private val debtsRepository: DebtsRepository,
    private val roomsRepository: RoomsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(ReportsHubUiState())
    val state: StateFlow<ReportsHubUiState> = _state.asStateFlow()

    init {
        combine(
            paymentsRepository.getAll(),
            expensesRepository.getAll(),
            bookingsRepository.getAll(),
            debtsRepository.getAll(),
            roomsRepository.getAll()
        ) { payments, expenses, bookings, debts, rooms ->
            val hotelDay = HotelTimeEngine.currentHotelDayKey()
            // Dart l.90-116: hotel-day key equality + legacy paymentDate LIKE fallback,
            // voided excluded.
            val dayIncome = payments.filter {
                !it.isVoided && (it.hotelDayKey == hotelDay ||
                    (it.hotelDayKey == null && it.paymentDate.startsWith(hotelDay)))
            }.sumOf { it.amount }
            val dayExpenses = expenses.filter {
                it.hotelDayKey == hotelDay ||
                    (it.hotelDayKey == null && it.date.startsWith(hotelDay))
            }.sumOf { it.amount }
            val activeBookings = bookings.filter { StatusUtils.isBookingActive(it.status) }
            val unsettled = debts.filter { !it.isSettled }
            // Dart l.127-136: occupancy = busy rooms / total rooms.
            val busy = rooms.count { StatusUtils.isRoomOccupied(it.status) }
            val totalRooms = if (rooms.isNotEmpty()) rooms.size else 1
            ReportsHubUiState(
                isLoading = false,
                hotelDayKey = hotelDay,
                income = dayIncome,
                expenses = dayExpenses,
                net = dayIncome - dayExpenses,
                totalRooms = totalRooms,
                occupiedRooms = busy,
                activeBookings = activeBookings.size,
                unsettledDebts = unsettled.size,
                unsettledDebtsTotal = unsettled.sumOf { it.remainingAmount }
            )
        }.onEach { _state.value = it }.launchIn(viewModelScope)
    }

    fun refresh() {
        // Streams are live; a manual refresh re-reads once.
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(error = null)
            } catch (_: Exception) { }
        }
    }
}
