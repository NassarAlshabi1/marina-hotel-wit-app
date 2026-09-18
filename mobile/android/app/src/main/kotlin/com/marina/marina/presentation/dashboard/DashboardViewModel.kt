package com.marina.marina.presentation.dashboard

import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val roomsRepository: RoomsRepository,
    private val bookingsRepository: BookingsRepository,
    private val paymentsRepository: PaymentsRepository,
    private val employeesRepository: EmployeesRepository,
    private val expensesRepository: ExpensesRepository,
    private val debtsRepository: DebtsRepository
) : ViewModel() {

    private val _dashboardState = mutableStateOf(DashboardState())
    val dashboardState = _dashboardState

    fun loadDashboardData() {
        viewModelScope.launch {
            _dashboardState.value = _dashboardState.value.copy(isLoading = true, error = null)
            try {
                val rooms = roomsRepository.getAll().first()
                val bookings = bookingsRepository.getAll().first()
                val payments = paymentsRepository.getAll().first()
                val expenses = expensesRepository.getAll().first()
                val unsettledDebts = debtsRepository.getUnsettled().first()

                val occupiedRooms = rooms.count { StatusUtils.isRoomOccupied(it.status) }
                val activeBookings = bookings.count { StatusUtils.isBookingActive(it.status) }

                _dashboardState.value = DashboardState(
                    isLoading = false,
                    isDataLoaded = true,
                    totalIncome = payments.filter { !it.isVoided }.sumOf { it.amount },
                    totalExpenses = expenses.sumOf { it.amount },
                    occupancyRate = if (rooms.isEmpty()) 0.0 else occupiedRooms.toDouble() / rooms.size,
                    activeBookings = activeBookings,
                    pendingDebts = unsettledDebts.size
                )
            } catch (e: Exception) {
                _dashboardState.value = _dashboardState.value.copy(isLoading = false, error = e.message)
            }
        }
    }
}

data class DashboardState(
    val isLoading: Boolean = false,
    val isDataLoaded: Boolean = false,
    val error: String? = null,
    val totalIncome: Double = 0.0,
    val totalExpenses: Double = 0.0,
    val occupancyRate: Double = 0.0,
    val activeBookings: Int = 0,
    val pendingDebts: Int = 0
)
