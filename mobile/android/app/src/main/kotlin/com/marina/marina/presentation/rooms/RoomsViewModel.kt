package com.marina.marina.presentation.rooms

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.RoomsRepository
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

data class RoomsUiState(
    val isLoading: Boolean = false,
    val rooms: List<Room> = emptyList(),
    val activeBookingRooms: Set<String> = emptySet(),
    val searchQuery: String = "",
    val error: String? = null,
    val message: String? = null
) {
    /** Rooms whose *effective* occupancy is derived from active bookings (like the Flutter app). */
    val filtered: List<Room>
        get() = if (searchQuery.isBlank()) rooms else rooms.filter {
            it.roomNumber.contains(searchQuery.trim()) || it.type.contains(searchQuery.trim(), ignoreCase = true)
        }

    val floors: Map<Int, List<Room>>
        get() = filtered.groupBy { room ->
            room.roomNumber.trim().take(1).toIntOrNull() ?: 0
        }.toSortedMap()

    val total: Int get() = rooms.size
    val availableCount: Int get() = rooms.count { StatusUtils.isRoomAvailable(it.status) }
    val occupiedCount: Int get() = rooms.count { StatusUtils.isRoomOccupied(it.status) }
    val maintenanceCount: Int get() = rooms.count { StatusUtils.isRoomUnderMaintenance(it.status) }
}

@HiltViewModel
class RoomsViewModel @Inject constructor(
    private val roomsRepository: RoomsRepository,
    private val bookingsRepository: BookingsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(RoomsUiState(isLoading = true))
    val state: StateFlow<RoomsUiState> = _state.asStateFlow()

    init {
        combine(roomsRepository.getAll(), bookingsRepository.getAll()) { rooms, bookings ->
            val activeRooms = bookings
                .filter { StatusUtils.isBookingActive(it.status) }
                .map { it.roomNumber }
                .toSet()
            rooms to activeRooms
        }.onEach { (rooms, activeRooms) ->
            _state.value = _state.value.copy(
                isLoading = false,
                rooms = rooms,
                activeBookingRooms = activeRooms,
                error = null
            )
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    fun saveRoom(room: Room) {
        viewModelScope.launch {
            try {
                if (room.id == 0L) {
                    roomsRepository.insert(room)
                    _state.value = _state.value.copy(message = "تمت إضافة الغرفة")
                } else {
                    roomsRepository.update(room)
                    _state.value = _state.value.copy(message = "تم تحديث الغرفة")
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    /** Quick toggle between شاغرة and محجوزة (blocked when an active booking exists). */
    fun toggleStatus(room: Room) {
        if (room.roomNumber in _state.value.activeBookingRooms) {
            _state.value = _state.value.copy(message = "لا يمكن تغيير الحالة — يوجد حجز نشط على الغرفة")
            return
        }
        val newStatus = if (StatusUtils.isRoomAvailable(room.status)) "محجوزة" else "شاغرة"
        saveRoom(room.copy(status = newStatus))
    }

    fun deleteRoom(room: Room) {
        viewModelScope.launch {
            try {
                roomsRepository.softDelete(room.id)
                _state.value = _state.value.copy(message = "تم حذف الغرفة")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
