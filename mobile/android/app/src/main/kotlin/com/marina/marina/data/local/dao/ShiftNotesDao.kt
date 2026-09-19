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
    @Query("SELECT * FROM shift_notes WHERE is_read = 0 ORDER BY created_at DESC")
    fun getUnread(): Flow<List<ShiftNoteEntity>>

    @Query("SELECT * FROM shift_notes ORDER BY created_at DESC")
    fun getAll(): Flow<List<ShiftNoteEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(note: ShiftNoteEntity): Long

    @Update
    suspend fun update(note: ShiftNoteEntity)

    @Query("UPDATE shift_notes SET is_read = 1 WHERE id = :id")
    suspend fun markRead(id: Long): Int

    @Query("DELETE FROM shift_notes WHERE id = :id")
    suspend fun delete(id: Long): Int
}
