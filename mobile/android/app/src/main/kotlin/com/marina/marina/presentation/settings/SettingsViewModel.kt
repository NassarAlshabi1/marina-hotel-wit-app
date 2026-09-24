package com.marina.marina.presentation.settings

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.util.StatusUtils
import com.marina.marina.ui.theme.ThemePrefs
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
 * الإعدادات — حالة مركز `settings_screen.dart`:
 * عدّادات سريعة (الغرف/النشطة/الموظفين/المستخدمين) + زر المزامنة
 * (نظير SyncActionButton — بنفس رسائل Dart) + الوضع الداكن.
 */
data class SettingsUiState(
    val isLoading: Boolean = true,
    val roomsCount: Int = 0,
    val activeBookings: Int = 0,
    val employeesCount: Int = 0,
    val usersCount: Int = 1,
    val isSyncing: Boolean = false,
    val isError: Boolean = false,
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
        ) { rooms, bookings, employees, _ ->
            SettingsUiState(
                isLoading = false,
                roomsCount = rooms.size,
                activeBookings = bookings.count { StatusUtils.isBookingActive(it.status) },
                employeesCount = employees.size
            )
        }.onEach { base ->
            // الحفاظ على حالة المزامنة/الرسائل الحية فوق العدّادات.
            _state.value = base.copy(
                isSyncing = _state.value.isSyncing,
                isError = _state.value.isError,
                message = _state.value.message,
                error = _state.value.error
            )
        }.launchIn(viewModelScope)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null, error = null)
    }

    /**
     * نظير SyncActionButton._runSync في Dart — بنفس رسائل السناك-بار:
     * 'لا توجد تغييرات جديدة' / 'تمت المزامنة: رفع X / سحب Y' /
     * 'فشل في المزامنة: ...'.
     */
    fun syncNow() {
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(isSyncing = true, error = null)
                val result = syncRepository.syncNow()
                val pushed = result.pushedCount
                val pulled = result.pulledCount
                _state.value = _state.value.copy(
                    isSyncing = false,
                    isError = false,
                    message = if (pushed == 0 && pulled == 0) {
                        "لا توجد تغييرات جديدة"
                    } else {
                        "تمت المزامنة: رفع $pushed / سحب $pulled"
                    }
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSyncing = false,
                    isError = true,
                    error = "فشل في المزامنة: ${e.message ?: "سبب غير معروف"}"
                )
            }
        }
    }

    /** تبديل الوضع الداكن — نظير themeSettingsProvider في Dart. */
    fun setDarkMode(context: Context, dark: Boolean) {
        viewModelScope.launch { ThemePrefs.setDark(context, dark) }
    }
}
