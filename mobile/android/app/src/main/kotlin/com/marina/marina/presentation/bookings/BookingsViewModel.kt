package com.marina.marina.presentation.bookings

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

data class BookingsUiState(
    val isLoading: Boolean = false,
    val bookings: List<Booking> = emptyList(),
    val roomPrices: Map<String, Double> = emptyMap(),
    val searchQuery: String = "",
    // Dart bookings_list l.113-122 — the DEFAULT view hides ONLY
    // مكتمل/completed/غادر/departed; cancelled (ملغي) bookings stay visible.
    val statusFilter: String = "default", // default | all | مكتمل | ملغي | النشطة
    val error: String? = null,
    val message: String? = null
) {
    val filtered: List<Booking>
        get() {
            var list = bookings
            list = when (statusFilter) {
                "default" -> list.filter {
                    it.status !in listOf("مكتمل", "completed", "غادر", "departed")
                }
                "النشطة" -> list.filter { StatusUtils.isBookingActive(it.status) }
                "all" -> list
                else -> list.filter { it.status == statusFilter || statusFilter.contains(it.status) }
            }
            val q = searchQuery.trim()
            if (q.isNotBlank()) {
                list = list.filter {
                    it.guestName.contains(q, ignoreCase = true) ||
                        it.guestPhone.contains(q) ||
                        it.roomNumber.contains(q) ||
                        it.guestIdNumber.contains(q)
                }
            }
            return list
        }

    val activeCount: Int get() = bookings.count { StatusUtils.isBookingActive(it.status) }
}

@HiltViewModel
class BookingsViewModel @Inject constructor(
    private val bookingsRepository: BookingsRepository,
    private val roomsRepository: RoomsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(BookingsUiState(isLoading = true))
    val state: StateFlow<BookingsUiState> = _state.asStateFlow()

    init {
        combine(bookingsRepository.getAll(), roomsRepository.getAll()) { bookings, rooms ->
            bookings to rooms.associate { it.roomNumber to it.price }
        }.onEach { (bookings, prices) ->
            _state.value = _state.value.copy(
                isLoading = false,
                bookings = bookings,
                roomPrices = prices,
                error = null
            )
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }

    fun setStatusFilter(filter: String) {
        _state.value = _state.value.copy(statusFilter = filter)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    /** Creates a new booking; nights are derived from the hotel-day engine. */
    fun saveBooking(booking: Booking) {
        viewModelScope.launch {
            try {
                val checkinMillis = HotelTimeEngine.parseDate(booking.checkinDate) ?: System.currentTimeMillis()
                val checkoutMillis = HotelTimeEngine.parseDate(booking.checkoutDate)
                // Dart booking screens use Time.nightsWithCutoff (not the
                // calendar-day calculateDays variant).
                val nights = if (checkoutMillis == null) 1
                else HotelTimeEngine.nightsWithCutoff(checkinMillis, checkoutMillis)
                val prepared = booking.copy(
                    expectedNights = nights,
                    calculatedNights = nights,
                    hotelDayCheckin = HotelTimeEngine.hotelDayKey(checkinMillis)
                )
                if (prepared.id == 0L) {
                    bookingsRepository.insert(prepared)
                    _state.value = _state.value.copy(message = "تم إنشاء الحجز")
                } else {
                    bookingsRepository.update(prepared)
                    _state.value = _state.value.copy(message = "تم تحديث الحجز")
                }
                // Keep the room's stored status in sync with occupancy.
                val room = roomsRepository.getByNumber(prepared.roomNumber)
                if (room != null && StatusUtils.isBookingActive(prepared.status) && !StatusUtils.isRoomOccupied(room.status)) {
                    roomsRepository.update(room.copy(status = "محجوزة"))
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun cancelBooking(booking: Booking) {
        viewModelScope.launch {
            try {
                bookingsRepository.update(booking.copy(status = "ملغي"))
                roomsRepository.getByNumber(booking.roomNumber)?.let { room ->
                    if (StatusUtils.isRoomOccupied(room.status)) {
                        roomsRepository.update(room.copy(status = "شاغرة"))
                    }
                }
                _state.value = _state.value.copy(message = "تم إلغاء الحجز")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
