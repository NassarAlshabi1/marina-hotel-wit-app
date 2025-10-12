package com.marinahotel.kotlin.rooms

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.repository.RoomsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

class RoomsViewModel(application: Application) : AndroidViewModel(application) {
    private val repo = RoomsRepository(HotelDatabase.getInstance(application).roomDao())
    private val query = MutableStateFlow("")

    val rooms: StateFlow<List<RoomItem>> = repo.flowAllRooms()
        .map { list -> list.map { RoomItem(number = it.roomNumber, status = it.status, type = it.type) } }
        .combine(query) { list, q ->
            if (q.isBlank()) list else list.filter { it.number.contains(q) || it.status.contains(q) }
        }
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    fun setQuery(value: String) { query.value = value }
}