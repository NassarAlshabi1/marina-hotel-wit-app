package com.marina.marina.presentation.notes

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.ShiftNote
import com.marina.marina.domain.repository.ShiftNotesRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class NotesUiState(
    val isLoading: Boolean = false,
    val notes: List<ShiftNote> = emptyList(),
    val tab: Int = 0, // 0 = all, 1 = unread, 2 = high priority
    val error: String? = null,
    val message: String? = null
) {
    val filtered: List<ShiftNote>
        get() = when (tab) {
            1 -> notes.filter { !it.isRead }
            2 -> notes.filter { it.priority.equals("high", ignoreCase = true) }
            else -> notes
        }

    val unreadCount: Int get() = notes.count { !it.isRead }
    val highCount: Int get() = notes.count { it.priority.equals("high", ignoreCase = true) }
}

@HiltViewModel
class NotesViewModel @Inject constructor(
    private val shiftNotesRepository: ShiftNotesRepository
) : ViewModel() {

    private val _state = MutableStateFlow(NotesUiState(isLoading = true))
    val state: StateFlow<NotesUiState> = _state.asStateFlow()

    init {
        shiftNotesRepository.getAll().onEach { notes ->
            _state.value = _state.value.copy(isLoading = false, notes = notes, error = null)
        }.launchIn(viewModelScope)
    }

    fun setTab(tab: Int) {
        _state.value = _state.value.copy(tab = tab)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    fun saveNote(note: ShiftNote) {
        viewModelScope.launch {
            try {
                if (note.id == 0L) {
                    shiftNotesRepository.insert(note)
                    _state.value = _state.value.copy(message = "تمت إضافة الملاحظة")
                } else {
                    shiftNotesRepository.update(note)
                    _state.value = _state.value.copy(message = "تم تحديث الملاحظة")
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun markRead(note: ShiftNote) {
        viewModelScope.launch {
            try {
                shiftNotesRepository.markRead(note.id)
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun deleteNote(note: ShiftNote) {
        viewModelScope.launch {
            try {
                shiftNotesRepository.delete(note.id)
                _state.value = _state.value.copy(message = "تم حذف الملاحظة")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
