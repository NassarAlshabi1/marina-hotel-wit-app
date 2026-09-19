package com.marina.marina.presentation.bookings

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.repository.BookingsRepository
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

data class BookingEditUiState(
    val isLoading: Boolean = false,
    val isEdit: Boolean = false,
    val booking: Booking? = null,
    val availableRooms: List<com.marina.marina.domain.model.Room> = emptyList(),
    val saved: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class BookingEditViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val bookingsRepository: BookingsRepository,
    private val roomsRepository: RoomsRepository
) : ViewModel() {

    private val bookingId: Long = savedStateHandle.get<Long>("bookingId") ?: 0L
    private val preselectedRoom: String = savedStateHandle.get<String>("roomNumber") ?: ""

    private val _state = MutableStateFlow(BookingEditUiState(isLoading = true, isEdit = bookingId > 0))
    val state: StateFlow<BookingEditUiState> = _state.asStateFlow()

    init {
        combine(bookingsRepository.getAll(), roomsRepository.getAll()) { bookings, rooms ->
            val editing = bookings.find { it.id == bookingId }
            // Rooms that are free (or the room already used by this booking).
            val freeRooms = rooms.filter {
                StatusUtils.isRoomAvailable(it.status) || (editing != null && it.roomNumber == editing.roomNumber)
            }
            editing to freeRooms
        }.onEach { (editing, freeRooms) ->
            _state.value = _state.value.copy(
                isLoading = false,
                booking = editing,
                availableRooms = freeRooms
            )
        }.launchIn(viewModelScope)
    }

    /**
     * Validates and saves the booking. Returns an error message via state when
     * validation fails (checkout must be after check-in, guest name required).
     */
    fun save(guestName: String, guestPhone: String, idNumber: String, nationality: String,
             roomNumber: String, checkinDate: String, checkoutDate: String, notes: String) {
        viewModelScope.launch {
            try {
                if (guestName.isBlank()) {
                    _state.value = _state.value.copy(error = "اسم الضيف مطلوب")
                    return@launch
                }
                if (roomNumber.isBlank()) {
                    _state.value = _state.value.copy(error = "يرجى اختيار غرفة")
                    return@launch
                }
                val checkinMillis = HotelTimeEngine.parseDate(checkinDate)
                if (checkinMillis == null) {
                    _state.value = _state.value.copy(error = "تاريخ الدخول غير صالح")
                    return@launch
                }
                val checkoutMillis = HotelTimeEngine.parseDate(checkoutDate)
                if (checkoutMillis != null && checkoutMillis <= checkinMillis) {
                    _state.value = _state.value.copy(error = "تاريخ المغادرة يجب أن يكون بعد الدخول")
                    return@launch
                }
                val nights = HotelTimeEngine.calculateDays(checkinMillis, checkoutMillis)

                val existing = _state.value.booking
                // New bookings default to مؤقت between 09:00–14:00 else محجوزة (Flutter parity).
                val defaultStatus = if (HotelTimeEngine.isAfterCutoff(checkinMillis) ||
                    java.util.Calendar.getInstance().apply { timeInMillis = System.currentTimeMillis() }
                        .get(java.util.Calendar.HOUR_OF_DAY) < 9) "محجوزة" else "مؤقت"

                val booking = (existing ?: Booking()).copy(
                    guestName = guestName.trim(),
                    guestPhone = guestPhone.trim(),
                    guestIdNumber = idNumber.trim(),
                    guestNationality = nationality.trim().ifBlank { "يمني" },
                    roomNumber = roomNumber,
                    checkinDate = checkinDate.trim(),
                    checkoutDate = checkoutDate.trim().ifBlank { null },
                    status = existing?.status ?: defaultStatus,
                    notes = notes.trim().ifBlank { null },
                    expectedNights = nights,
                    calculatedNights = nights,
                    hotelDayCheckin = HotelTimeEngine.hotelDayKey(checkinMillis)
                )

                if (existing == null) {
                    bookingsRepository.insert(booking)
                } else {
                    bookingsRepository.update(booking)
                }

                // Mark the room as occupied.
                roomsRepository.getByNumber(roomNumber)?.let { room ->
                    if (StatusUtils.isRoomAvailable(room.status)) {
                        roomsRepository.update(room.copy(status = "محجوزة"))
                    }
                }

                _state.value = _state.value.copy(saved = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
