package com.marinahotel.kotlin.presentation.booking

import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.data.repository.HotelRepository
import com.marinahotel.kotlin.domain.model.Booking
import com.marinahotel.kotlin.domain.model.BookingStatus
import com.marinahotel.kotlin.domain.model.Guest
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max

class BookingFormViewModel(
    private val repository: HotelRepository,
    private val bookingId: Int,
    private val preselectedRoomNumber: String
) : ViewModel() {

    private val _state = MutableStateFlow(
        BookingFormState(
            roomNumber = preselectedRoomNumber,
            isUpdate = bookingId > 0,
            bookingId = bookingId
        )
    )
    val state: StateFlow<BookingFormState> = _state.asStateFlow()

    private val eventsFlow = MutableSharedFlow<BookingFormEvent>()
    val events: SharedFlow<BookingFormEvent> = eventsFlow

    private var currentGuestId: Int = 0
    private var guestCreatedAt: Long = System.currentTimeMillis()

    private val dateFormatter = DateTimeFormatter.ofPattern("dd MMM yyyy", Locale.getDefault())

    init {
        observeAvailableRooms()
        if (bookingId > 0) {
            loadBooking(bookingId)
        }
    }

    private fun observeAvailableRooms() {
        viewModelScope.launch {
            repository.observeAvailableRooms().collect { rooms ->
                val options = rooms.map { it.number }
                val currentRoom = state.value.roomNumber
                val enriched = if (currentRoom.isNotBlank() && !options.contains(currentRoom)) {
                    options + currentRoom
                } else {
                    options
                }
                _state.update { it.copy(roomOptions = enriched.sorted()) }
            }
        }
    }

    private fun loadBooking(id: Int) {
        viewModelScope.launch {
            repository.observeBookingDetails(id).collect { summary ->
                if (summary != null) {
                    currentGuestId = summary.guest.id
                    guestCreatedAt = summary.guest.createdAt
                    _state.update {
                        it.copy(
                            guestName = summary.guest.name,
                            guestPhone = summary.guest.phone,
                            idType = summary.guest.idType,
                            idNumber = summary.guest.idNumber,
                            nationality = summary.guest.nationality.orEmpty(),
                            roomNumber = summary.room.number,
                            checkinDate = summary.booking.checkinDate,
                            checkoutDate = summary.booking.checkoutDate,
                            notes = summary.booking.notes.orEmpty()
                        )
                    }
                }
            }
        }
    }

    fun onGuestNameChanged(value: String) {
        _state.update { it.copy(guestName = value) }
    }

    fun onGuestPhoneChanged(value: String) {
        _state.update { it.copy(guestPhone = value) }
    }

    fun onIdTypeChanged(value: String) {
        _state.update { it.copy(idType = value) }
    }

    fun onIdNumberChanged(value: String) {
        _state.update { it.copy(idNumber = value) }
    }

    fun onNationalityChanged(value: String) {
        _state.update { it.copy(nationality = value) }
    }

    fun onRoomChanged(value: String) {
        _state.update { it.copy(roomNumber = value) }
    }

    fun onCheckinSelected(timestamp: Long) {
        _state.update { state ->
            val checkout = state.checkoutDate?.takeIf { it >= timestamp }
            state.copy(checkinDate = timestamp, checkoutDate = checkout)
        }
    }

    fun onCheckoutSelected(timestamp: Long?) {
        _state.update { it.copy(checkoutDate = timestamp) }
    }

    fun onNotesChanged(value: String) {
        _state.update { it.copy(notes = value) }
    }

    fun saveBooking() {
        val current = _state.value
        if (current.guestName.isBlank() || current.guestPhone.isBlank()) {
            emitMessage(BookingFormEvent.ShowMessage(R.string.error_required_field))
            return
        }
        if (current.roomNumber.isBlank()) {
            emitMessage(BookingFormEvent.ShowMessage(R.string.error_select_room))
            return
        }
        val checkin = current.checkinDate ?: run {
            emitMessage(BookingFormEvent.ShowMessage(R.string.error_select_checkin))
            return
        }

        viewModelScope.launch {
            _state.update { it.copy(isSaving = true) }
            val guest = Guest(
                id = currentGuestId,
                name = current.guestName,
                idType = current.idType.ifBlank { DEFAULT_ID_TYPES.first() },
                idNumber = current.idNumber,
                phone = current.guestPhone,
                nationality = current.nationality.ifBlank { null },
                createdAt = guestCreatedAt
            )

            val booking = Booking(
                id = current.bookingId,
                guestId = currentGuestId.takeIf { it != 0 },
                roomNumber = current.roomNumber,
                checkinDate = checkin,
                checkoutDate = current.checkoutDate,
                status = BookingStatus.RESERVED,
                notes = current.notes.ifBlank { null },
                calculatedNights = computeNights(checkin, current.checkoutDate ?: checkin)
            )

            try {
                if (current.isUpdate) {
                    repository.updateBooking(guest, booking)
                    _state.update { it.copy(isSaving = false) }
                    emitMessage(BookingFormEvent.ShowMessage(R.string.message_booking_updated))
                    eventsFlow.emit(BookingFormEvent.BookingSaved(booking.id))
                } else {
                    val newId = repository.createBooking(guest, booking)
                    _state.update { it.copy(isSaving = false) }
                    emitMessage(BookingFormEvent.ShowMessage(R.string.message_booking_saved))
                    eventsFlow.emit(BookingFormEvent.BookingSaved(newId))
                }
            } catch (exception: IllegalStateException) {
                _state.update { it.copy(isSaving = false) }
                emitMessage(BookingFormEvent.ShowMessage(R.string.error_select_room))
            }
        }
    }

    private fun emitMessage(event: BookingFormEvent) {
        viewModelScope.launch {
            eventsFlow.emit(event)
        }
    }

    private fun computeNights(checkin: Long, checkout: Long): Int {
        val millisPerNight = 86_400_000L
        val diff = max(0L, checkout - checkin)
        val nights = (diff / millisPerNight).toInt()
        return max(1, nights)
    }

    fun formatDate(timestamp: Long?): String {
        return timestamp?.let {
            val instant = Instant.ofEpochMilli(it)
            dateFormatter.format(instant.atZone(ZoneId.systemDefault()).toLocalDate())
        } ?: ""
    }

    data class BookingFormState(
        val guestName: String = "",
        val guestPhone: String = "",
        val idType: String = DEFAULT_ID_TYPES.first(),
        val idNumber: String = "",
        val nationality: String = "",
        val roomNumber: String = "",
        val roomOptions: List<String> = emptyList(),
        val checkinDate: Long? = null,
        val checkoutDate: Long? = null,
        val notes: String = "",
        val isUpdate: Boolean = false,
        val isSaving: Boolean = false,
        val bookingId: Int = 0
    )

    sealed class BookingFormEvent {
        data class ShowMessage(@StringRes val messageRes: Int) : BookingFormEvent()
        data class BookingSaved(val bookingId: Int) : BookingFormEvent()
    }

    companion object {
        val DEFAULT_ID_TYPES = listOf("بطاقة شخصية", "جواز سفر", "إقامة")
        val DEFAULT_NATIONALITIES = listOf("السعودية", "الإمارات", "الكويت", "مصر", "الأردن")
    }
}
