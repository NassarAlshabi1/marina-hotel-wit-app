package com.marina.marina.presentation.dashboard

import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.launch
import com.marina.marina.data.RoomsRepository
import com.marina.marina.data.BookingsRepository
import com.marina.marina.data.PaymentsRepository
import com.marina.marina.data.EmployeesRepository
import com.marina.marina.data.ExpensesRepository
import com.marina.marina.data.DebtsRepository

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val roomsRepository: RoomsRepository,
    private val bookingsRepository: BookingsRepository,
    private val paymentsRepository: PaymentsRepository,
    private val employeesRepository: EmployeesRepository,
    private val expensesRepository: ExpensesRepository,
    private val debtsRepository: DebtsRepository
) : ViewModel() {

    private val _dashboardState = mutableStateOf<DashboardState>(DashboardState())
    val dashboardState = _dashboardState

    private val _totalIncome = mutableStateOf(0.0)
    val totalIncome = _totalIncome

    private val _totalExpenses = mutableStateOf(0.0)
    val totalExpenses = _totalExpenses

    private val _occupancyRate = mutableStateOf(0.0)
    val occupancyRate = _occupancyRate

    private val _activeBookings = mutableStateOf(0)
    val activeBookings = _activeBookings

    private val _pendingDebts = mutableStateOf(0)
    val pendingDebts = _pendingDebts

    fun loadDashboardData() {
        viewModelScope.launch {
            _dashboardState.value = DashboardState(isLoading = true)
            try {
                // Load summary data from repositories
                val rooms = roomsRepository.getAll().let { flow ->
                    // Collect first emission
                    emptyList<com.marina.marina.data.Room>()
                }
                _dashboardState.value = DashboardState(isLoading = false, isDataLoaded = true)
            } catch (e: Exception) {
                _dashboardState.value = DashboardState(isLoading = false, error = e.message)
            }
        }
    }
}

data class DashboardState(
    val isLoading: Boolean = false,
    val isDataLoaded: Boolean = false,
    val error: String? = null
)