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
import kotlinx.coroutines.flow.stateIn

class GuestsViewModel(application: Application) : AndroidViewModel(application) {
    private val database = HotelDatabase.getInstance(application)
    private val repo = BookingRepository(database.bookingDao(), database.guestDao())
    private val query = MutableStateFlow("")

    private val guestsFlow = repo.flowAllGuests()
    private val bookingsFlow = repo.flowAllBookingsWithGuests()

    val guests: StateFlow<List<GuestItem>> = combine(guestsFlow, bookingsFlow) { guests, bookings ->
        guests.map { guest ->
            val visits = bookings.count { it.guest.guestId == guest.guestId }
            GuestItem(
                name = guest.guestName,
                contact = guest.guestPhone.orEmpty(),
                visits = visits
            )
        }.sortedBy { it.name }
    }.combine(query) { list, q ->
        if (q.isBlank()) list else list.filter { it.name.contains(q) || it.contact.contains(q) }
    }.stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    fun setQuery(value: String) { query.value = value }
}
