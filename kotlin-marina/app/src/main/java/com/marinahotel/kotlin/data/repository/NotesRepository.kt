package com.marinahotel.kotlin.data.repository

import com.marinahotel.kotlin.data.db.BookingNoteDao
import com.marinahotel.kotlin.data.entities.BookingNoteEntity
import kotlinx.coroutines.flow.Flow

class NotesRepository(private val noteDao: BookingNoteDao) {
    fun flowByBooking(bookingId: Int): Flow<List<BookingNoteEntity>> = noteDao.flowByBooking(bookingId)
    suspend fun getByBooking(bookingId: Int): List<BookingNoteEntity> = noteDao.getByBooking(bookingId)
    suspend fun save(note: BookingNoteEntity) = noteDao.insert(note)
}