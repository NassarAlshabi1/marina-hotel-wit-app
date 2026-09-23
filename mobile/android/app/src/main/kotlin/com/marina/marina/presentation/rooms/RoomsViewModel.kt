package com.marina.marina.presentation.rooms

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
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
    /** Room numbers that currently host an ACTIVE booking (Dart derives room
     *  occupancy from bookings, not the stored status). */
    val activeBookingRooms: Set<String> = emptySet(),
    /** Latest active booking per room — used to route occupied-room taps to
     *  the payment screen (Dart rooms_dashboard l.216-273). */
    val activeBookingByRoom: Map<String, Booking> = emptyMap(),
    val searchQuery: String = "",
    val error: String? = null,
    val message: String? = null
) {
    val filtered: List<Room>
        get() = if (searchQuery.isBlank()) rooms else rooms.filter {
            it.roomNumber.contains(searchQuery.trim()) || it.type.contains(searchQuery.trim(), ignoreCase = true)
        }

    /** Floor key = first character of the room number (Dart rooms l.35-57). */
    val floors: Map<String, List<Room>>
        get() = filtered.groupBy { room -> room.roomNumber.trim().take(1).ifBlank { "0" } }
            .toSortedMap(compareBy { it.toIntOrNull() ?: Int.MAX_VALUE })

    val total: Int get() = rooms.size
    val availableCount: Int get() = rooms.count { isEffectivelyAvailable(it) }
    val occupiedCount: Int get() = rooms.count { it.roomNumber in activeBookingRooms }
    val maintenanceCount: Int get() = rooms.count { StatusUtils.isRoomUnderMaintenance(it.status) }

    /** Dart effective availability: not maintenance, and no active booking. */
    fun isEffectivelyAvailable(room: Room): Boolean =
        !StatusUtils.isRoomUnderMaintenance(room.status) && room.roomNumber !in activeBookingRooms
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
            // Latest active booking per room (latest check-in wins).
            val activeByRoom = bookings
                .filter { StatusUtils.isBookingActive(it.status) }
                .sortedBy { it.checkinDate }
                .groupBy { it.roomNumber }
                .mapValues { (_, list) -> list.last() }
            rooms to activeByRoom
        }.onEach { (rooms, activeByRoom) ->
            _state.value = _state.value.copy(
                isLoading = false,
                rooms = rooms,
                activeBookingRooms = activeByRoom.keys,
                activeBookingByRoom = activeByRoom,
                error = null
            )
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }

    /** Dart rooms_dashboard l.238-248 — an occupied room tap with no active booking. */
    fun onRoomWithoutBooking(room: Room) {
        _state.value = _state.value.copy(message = "لا يوجد حجز محجوز للغرفة ${room.roomNumber}")
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    fun saveRoom(room: Room) {
        viewModelScope.launch {
            try {
                if (room.id == 0L) {
                    roomsRepository.insert(room)
                    // Dart rooms_list l.643-659.
                    _state.value = _state.value.copy(message = "تمت إضافة الغرفة ${room.roomNumber}")
                } else {
                    roomsRepository.update(room)
                    _state.value = _state.value.copy(message = "تم تحديث الغرفة ${room.roomNumber}")
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "فشل حفظ الغرفة: ${e.message}")
            }
        }
    }

    /**
     * Dart quick status toggle (rooms_list l.425-456): blocked with the room
     * number AND the guest name when an active booking exists; success message
     * names the room and the new status.
     */
    fun toggleStatus(room: Room) {
        val active = _state.value.activeBookingByRoom[room.roomNumber]
        if (active != null) {
            _state.value = _state.value.copy(
                message = "لا يمكن تحويل الغرفة ${room.roomNumber}: يوجد حجز نشط (${active.guestName})"
            )
            return
        }
        val newStatus = if (StatusUtils.isRoomAvailable(room.status)) "محجوزة" else "شاغرة"
        viewModelScope.launch {
            try {
                roomsRepository.update(room.copy(status = newStatus))
                _state.value = _state.value.copy(message = "تم تغيير حالة الغرفة ${room.roomNumber} إلى $newStatus")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "فشل حفظ الغرفة: ${e.message}")
            }
        }
    }

    fun deleteRoom(room: Room) {
        viewModelScope.launch {
            try {
                roomsRepository.softDelete(room.id)
                _state.value = _state.value.copy(message = "تم حذف الغرفة ${room.roomNumber}")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
