package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.SyncQueueEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SyncQueueDao {
    @Query("SELECT * FROM sync_queue ORDER BY id DESC")
    fun getAll(): Flow<List<SyncQueueEntity>>

    @Query("SELECT * FROM sync_queue ORDER BY id DESC")
    suspend fun getAllOnce(): List<SyncQueueEntity>

    @Query("SELECT * FROM sync_queue WHERE id = :id")
    suspend fun getById(id: Long): SyncQueueEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: SyncQueueEntity): Long

    @Query("DELETE FROM sync_queue WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("DELETE FROM sync_queue")
    suspend fun clearAll()

    @Query("SELECT * FROM sync_queue WHERE status = :status ORDER BY id ASC")
    suspend fun getByStatus(status: String): List<SyncQueueEntity>

    @Query("UPDATE sync_queue SET status = :status WHERE id = :id")
    suspend fun setStatus(id: Long, status: String): Int
}
