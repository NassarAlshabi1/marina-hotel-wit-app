package com.marinahotel.kotlin.rooms

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.entities.RoomEntity
import com.marinahotel.kotlin.data.repository.RoomsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class RoomAddViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = RoomsRepository(HotelDatabase.getInstance(application).roomDao())

    private val _state = MutableStateFlow(AddRoomState())
    val state: StateFlow<AddRoomState> = _state.asStateFlow()

    fun saveRoom(number: String, type: String, price: Double, status: String) {
        if (_state.value.isSaving) return
        viewModelScope.launch(Dispatchers.IO) {
            _state.value = AddRoomState(isSaving = true)
            val app = getApplication<Application>()
            try {
                val exists = repository.exists(number)
                if (exists) {
                    _state.value = AddRoomState(error = app.getString(R.string.error_room_exists))
                    return@launch
                }
                repository.saveRoom(
                    RoomEntity(
                        roomNumber = number,
                        type = type,
                        price = price,
                        status = status
                    )
                )
                _state.value = AddRoomState(success = true)
            } catch (ex: Exception) {
                val message = ex.message?.takeIf { it.isNotBlank() } ?: app.getString(R.string.error_unexpected)
                _state.value = AddRoomState(error = message)
            }
        }
    }

    fun clearError() {
        val current = _state.value
        if (current.error != null) {
            _state.value = current.copy(error = null)
        }
    }

    fun resetState() {
        _state.value = AddRoomState()
    }
}

data class AddRoomState(
    val isSaving: Boolean = false,
    val success: Boolean = false,
    val error: String? = null
)
