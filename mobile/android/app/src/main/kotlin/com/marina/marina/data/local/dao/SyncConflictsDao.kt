package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.SyncConflictEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SyncConflictsDao {
    @Query("SELECT * FROM sync_conflicts ORDER BY id DESC")
    fun getAll(): Flow<List<SyncConflictEntity>>

    @Query("SELECT * FROM sync_conflicts ORDER BY id DESC")
    suspend fun getAllOnce(): List<SyncConflictEntity>

    @Query("SELECT * FROM sync_conflicts WHERE id = :id")
    suspend fun getById(id: Long): SyncConflictEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: SyncConflictEntity): Long

    @Query("DELETE FROM sync_conflicts WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("DELETE FROM sync_conflicts")
    suspend fun clearAll()
}
