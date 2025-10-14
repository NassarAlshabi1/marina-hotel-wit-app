package com.marinahotel.kotlin.bookings

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.repository.BookingDraft
import com.marinahotel.kotlin.data.repository.BookingRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class BookingViewModel(application: Application) : AndroidViewModel(application) {
    private val database = HotelDatabase.getInstance(application)
    private val repository = BookingRepository(database.bookingDao(), database.guestDao())

    private val _booking = MutableStateFlow<BookingDraft?>(null)
    val booking: StateFlow<BookingDraft?> = _booking.asStateFlow()

    fun loadBooking(id: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            val draft = repository.getBookingDraftById(id)
            _booking.value = draft
        }
    }

    suspend fun saveBooking(draft: BookingDraft): Int {
        return withContext(Dispatchers.IO) {
            repository.saveBooking(draft)
        }
    }
}
