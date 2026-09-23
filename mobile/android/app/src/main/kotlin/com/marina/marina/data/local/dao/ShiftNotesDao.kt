package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.ShiftNoteEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ShiftNotesDao {
    // Dart shift_notes_dao.dart l.18-40 — the notes list shows only live
    // user-created notes (soft-deleted rows and system/blacklist notes stay
    // hidden).
    @Query("SELECT * FROM shift_notes WHERE is_read = 0 AND deleted_at IS NULL AND created_by = 'user' ORDER BY created_at DESC")
    fun getUnread(): Flow<List<ShiftNoteEntity>>

    @Query("SELECT * FROM shift_notes WHERE deleted_at IS NULL AND created_by = 'user' ORDER BY created_at DESC")
    fun getAll(): Flow<List<ShiftNoteEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(note: ShiftNoteEntity): Long

    @Update
    suspend fun update(note: ShiftNoteEntity)

    @Query("SELECT * FROM shift_notes WHERE id = :id")
    suspend fun getById(id: Long): ShiftNoteEntity?

    // Dart markAsRead (l.172-217) bumps the OCC version alongside the flag.
    @Query("UPDATE shift_notes SET is_read = 1, version = version + 1, updated_at = :updatedAt WHERE id = :id")
    suspend fun markRead(id: Long, updatedAt: Long): Int

    // Dart delete (l.268-313) is a SOFT delete, so it propagates via outbox.
    @Query("UPDATE shift_notes SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
}
