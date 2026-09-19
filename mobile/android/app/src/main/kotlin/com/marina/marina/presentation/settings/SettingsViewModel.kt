package com.marina.marina.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.repository.SyncManager
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.RoomsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class SettingsUiState(
    val isLoading: Boolean = false,
    val roomCount: Int = 0,
    val activeBookings: Int = 0,
    val employeeCount: Int = 0,
    val pendingOutbox: Int = 0,
    val sync: SyncManager.SyncUiState = SyncManager.SyncUiState(),
    val error: String? = null,
    val message: String? = null
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val syncManager: SyncManager,
    private val roomsRepository: RoomsRepository,
    private val bookingsRepository: BookingsRepository,
    private val employeesRepository: EmployeesRepository
) : ViewModel() {

    private val _state = MutableStateFlow(SettingsUiState(isLoading = true))
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        combine(
            roomsRepository.getAll(),
            bookingsRepository.getAll(),
            employeesRepository.getAll(),
            syncManager.pendingCount()
        ) { rooms, bookings, employees, pending ->
            SettingsUiState(
                isLoading = false,
                roomCount = rooms.size,
                activeBookings = bookings.count { com.marina.marina.domain.util.StatusUtils.isBookingActive(it.status) },
                employeeCount = employees.size,
                pendingOutbox = pending,
                sync = syncManager.syncState.value
            )
        }.onEach { newState ->
            _state.value = newState.copy(message = _state.value.message, error = _state.value.error)
        }.launchIn(viewModelScope)

        syncManager.syncState.onEach { sync ->
            _state.value = _state.value.copy(sync = sync)
        }.launchIn(viewModelScope)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    /** Triggers a full push + pull cycle via [SyncManager]. */
    fun syncNow() {
        viewModelScope.launch {
            val result = syncManager.syncNow()
            _state.value = _state.value.copy(
                message = if (result.isError) result.lastMessage else result.lastMessage
            )
        }
    }
}
