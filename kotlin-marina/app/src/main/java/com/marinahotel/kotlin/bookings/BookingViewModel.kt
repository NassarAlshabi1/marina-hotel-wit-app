package com.marinahotel.kotlin.bookings

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.entities.BookingEntity
import com.marinahotel.kotlin.data.repository.BookingRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class BookingViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = BookingRepository(HotelDatabase.getInstance(application).bookingDao())

    private val _booking = MutableStateFlow<BookingEntity?>(null)
    val booking: StateFlow<BookingEntity?> = _booking.asStateFlow()

    fun loadBooking(id: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            val entity = repository.getBookingById(id)
            _booking.value = entity
        }
    }

    suspend fun saveBooking(entity: BookingEntity): Int {
        return withContext(Dispatchers.IO) {
            repository.saveBooking(entity)
        }
    }
}
