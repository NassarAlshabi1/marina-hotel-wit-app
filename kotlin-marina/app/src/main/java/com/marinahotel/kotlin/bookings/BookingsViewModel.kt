package com.marinahotel.kotlin.bookings

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.repository.BookingRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

class BookingsViewModel(application: Application) : AndroidViewModel(application) {
    private val repo = BookingRepository(HotelDatabase.getInstance(application).bookingDao())

    private val query = MutableStateFlow("")
    private val statusFilters = MutableStateFlow<Set<String>>(emptySet())

    val bookings: StateFlow<List<BookingUi>> = repo.flowAllBookings()
        .map { list ->
            list.map {
                BookingUi(
                    code = "BKG-${it.bookingId}",
                    guestName = it.guestName,
                    roomNumber = it.roomNumber,
                    status = it.status,
                    arrivalDate = it.checkinDate,
                    departureDate = it.checkoutDate ?: ""
                )
            }
        }
        .combine(query) { list, q ->
            if (q.isBlank()) list else list.filter { it.guestName.contains(q) || it.code.contains(q) }
        }
        .combine(statusFilters) { list, filters ->
            if (filters.isEmpty()) list else list.filter { item -> filters.any { f -> item.status.contains(f) } }
        }
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    fun setQuery(value: String) { query.value = value }
    fun setStatusFilters(values: Set<String>) { statusFilters.value = values }
}