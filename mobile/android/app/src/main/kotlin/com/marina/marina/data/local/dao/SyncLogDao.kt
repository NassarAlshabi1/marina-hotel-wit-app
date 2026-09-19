package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.SyncLogEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SyncLogDao {
    @Query("SELECT * FROM sync_log ORDER BY id DESC")
    fun getAll(): Flow<List<SyncLogEntity>>

    @Query("SELECT * FROM sync_log ORDER BY id DESC")
    suspend fun getAllOnce(): List<SyncLogEntity>

    @Query("SELECT * FROM sync_log WHERE id = :id")
    suspend fun getById(id: Long): SyncLogEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: SyncLogEntity): Long

    @Query("DELETE FROM sync_log WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("DELETE FROM sync_log")
    suspend fun clearAll()
}
