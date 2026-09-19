package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.RestoreFixLogEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface RestoreFixLogDao {
    @Query("SELECT * FROM restore_fix_log ORDER BY id DESC")
    fun getAll(): Flow<List<RestoreFixLogEntity>>

    @Query("SELECT * FROM restore_fix_log ORDER BY id DESC")
    suspend fun getAllOnce(): List<RestoreFixLogEntity>

    @Query("SELECT * FROM restore_fix_log WHERE id = :id")
    suspend fun getById(id: Long): RestoreFixLogEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: RestoreFixLogEntity): Long

    @Query("DELETE FROM restore_fix_log WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("DELETE FROM restore_fix_log")
    suspend fun clearAll()
}
