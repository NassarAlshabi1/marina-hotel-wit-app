package com.marinahotel.kotlin.notes

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.repository.NotesRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

class NotesViewModel(application: Application) : AndroidViewModel(application) {
    private val repo = NotesRepository(HotelDatabase.getInstance(application).bookingNoteDao())

    fun notesForBooking(bookingId: Int): StateFlow<List<NoteItem>> = repo.flowByBooking(bookingId)
        .map { list -> list.map { NoteItem(title = "ملاحظة", body = it.noteText, meta = it.createdAt, priority = it.alertType, read = !it.isActive) } }
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())
}