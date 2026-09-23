package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.BookingNoteEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface BookingNotesDao {
    @Query("SELECT * FROM booking_notes WHERE is_active = 1 ORDER BY created_at DESC")
    fun getAll(): Flow<List<BookingNoteEntity>>

    @Query("SELECT * FROM booking_notes WHERE booking_id = :bookingId AND is_active = 1 ORDER BY created_at DESC")
    fun getByBooking(bookingId: Long): Flow<List<BookingNoteEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(note: BookingNoteEntity): Long

    @Update
    suspend fun update(note: BookingNoteEntity)

    @Query("UPDATE booking_notes SET is_active = 0, updated_at = :updatedAt WHERE id = :id")
    suspend fun deactivate(id: Long, updatedAt: Long): Int

    // ✅ (2026-09-24) سحب المزامنة: إيجاد الصف المحلي بمفتاح local_uuid
    // (توجيه سجلات pull عبر _entity — عقد الـ worker).
    @Query("SELECT * FROM booking_notes WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): BookingNoteEntity?
}
