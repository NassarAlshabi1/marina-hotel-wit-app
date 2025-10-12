package com.marinahotel.kotlin.settings.guests

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

class GuestsViewModel(application: Application) : AndroidViewModel(application) {
    private val repo = BookingRepository(HotelDatabase.getInstance(application).bookingDao())
    private val query = MutableStateFlow("")

    val guests: StateFlow<List<GuestItem>> = repo.flowAllBookings()
        .map { list ->
            list.groupBy { it.guestName }.map { (name, bookings) ->
                val contact = bookings.firstOrNull()?.guestPhone ?: ""
                GuestItem(name = name, contact = contact, visits = bookings.size)
            }.sortedBy { it.name }
        }
        .combine(query) { list, q -> if (q.isBlank()) list else list.filter { it.name.contains(q) || it.contact.contains(q) } }
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    fun setQuery(value: String) { query.value = value }
}