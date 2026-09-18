package com.marina.marina.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface BookingNotesDao {
    @Query("SELECT * FROM booking_notes WHERE is_active = 1 ORDER BY created_at DESC")
    fun getAll(): Flow<List<BookingNote>>

    @Query("SELECT * FROM booking_notes WHERE booking_id = :bookingId AND is_active = 1 ORDER BY created_at DESC")
    fun getByBooking(bookingId: Long): Flow<List<BookingNote>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(note: BookingNote): Long

    @Update
    suspend fun update(note: BookingNote)

    @Query("UPDATE booking_notes SET is_active = 0, updated_at = :updatedAt WHERE id = :id")
    suspend fun deactivate(id: Long, updatedAt: Long): Int
}