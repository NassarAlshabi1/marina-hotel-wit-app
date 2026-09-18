package com.marina.marina.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface ShiftNotesDao {
    @Query("SELECT * FROM shift_notes WHERE is_read = 0 ORDER BY created_at DESC")
    fun getUnread(): Flow<List<ShiftNote>>

    @Query("SELECT * FROM shift_notes ORDER BY created_at DESC")
    fun getAll(): Flow<List<ShiftNote>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(note: ShiftNote): Long

    @Update
    suspend fun update(note: ShiftNote)

    @Query("UPDATE shift_notes SET is_read = 1 WHERE id = :id")
    suspend fun markRead(id: Long): Int
}