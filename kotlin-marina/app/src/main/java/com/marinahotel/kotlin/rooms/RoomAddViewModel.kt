package com.marinahotel.kotlin.rooms

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.R
import android.database.sqlite.SQLiteConstraintException
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

    private val _room = MutableStateFlow<RoomEntity?>(null)
    val room: StateFlow<RoomEntity?> = _room.asStateFlow()

    fun loadRoom(roomNumber: String) {
        if (_room.value != null) return
        viewModelScope.launch(Dispatchers.IO) {
            val entity = repository.getRoom(roomNumber)
            _room.value = entity
        }
    }

    fun saveRoom(number: String, type: String, price: Double, status: String) {
        if (_state.value.isSaving) return
        viewModelScope.launch(Dispatchers.IO) {
            _state.value = AddRoomState(isSaving = true)
            val app = getApplication<Application>()
            try {
                val existing = _room.value
                if (existing == null) {
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
                } else {
                    if (number != existing.roomNumber) {
                        _state.value = AddRoomState(error = app.getString(R.string.error_room_exists))
                        return@launch
                    }
                    repository.updateRoom(
                        RoomEntity(
                            roomNumber = existing.roomNumber,
                            type = type,
                            price = price,
                            status = status
                        )
                    )
                    _state.value = AddRoomState(success = true)
                    _room.value = repository.getRoom(number)
                }
            } catch (ex: Exception) {
                val message = ex.message?.takeIf { it.isNotBlank() } ?: app.getString(R.string.error_unexpected)
                _state.value = AddRoomState(error = message)
            }
        }
    }

    fun deleteCurrentRoom() {
        val existing = _room.value ?: return
        if (_state.value.isSaving) return
        viewModelScope.launch(Dispatchers.IO) {
            _state.value = AddRoomState(isSaving = true)
            val app = getApplication<Application>()
            try {
                repository.deleteRoom(existing.roomNumber)
                _state.value = AddRoomState(deleted = true)
            } catch (ex: SQLiteConstraintException) {
                _state.value = AddRoomState(error = app.getString(R.string.error_room_in_use))
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
    val deleted: Boolean = false,
    val error: String? = null
)
