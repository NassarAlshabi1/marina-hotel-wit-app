package com.marina.marina.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.repository.SyncRepository
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
 * الإعدادات — 1:1 port of the `settings_screen.dart` hub state:
 * quick stats (الغرف / النشطة / الموظفين / المستخدمين), cloud-sync status
 * and pending outbox count.
 */
data class SettingsUiState(
    val isLoading: Boolean = true,
    val roomsCount: Int = 0,
    val activeBookings: Int = 0,
    val employeesCount: Int = 0,
    val usersCount: Int = 1,
    val pendingOutbox: Int = 0,
    val lastSyncText: String = "لم تتم بعد",
    val isSyncing: Boolean = false,
    val message: String? = null,
    val error: String? = null
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val roomsRepository: RoomsRepository,
    private val bookingsRepository: BookingsRepository,
    private val employeesRepository: EmployeesRepository,
    private val syncRepository: SyncRepository
) : ViewModel() {

    private val _state = MutableStateFlow(SettingsUiState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        combine(
            roomsRepository.getAll(),
            bookingsRepository.getAll(),
            employeesRepository.getAll(),
            syncRepository.pendingCount()
        ) { rooms, bookings, employees, pending ->
            SettingsUiState(
                isLoading = false,
                roomsCount = rooms.size,
                activeBookings = bookings.count { StatusUtils.isBookingActive(it.status) },
                employeesCount = employees.size,
                pendingOutbox = pending
            )
        }.onEach { _state.value = it }.launchIn(viewModelScope)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null, error = null)
    }

    fun syncNow() {
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(isSyncing = true)
                val result = syncRepository.syncNow()
                _state.value = _state.value.copy(
                    isSyncing = false,
                    message = result.lastMessage.ifBlank { "تمت المزامنة (رفع ${result.pushedCount} / استقبل ${result.pulledCount})" },
                    lastSyncText = "الآن"
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isSyncing = false, error = "تعذرت المزامنة: ${e.message}")
            }
        }
    }
}
