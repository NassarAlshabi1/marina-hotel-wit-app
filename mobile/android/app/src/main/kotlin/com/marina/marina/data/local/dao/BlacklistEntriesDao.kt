package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.BlacklistEntryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface BlacklistEntriesDao {
    @Query("SELECT * FROM blacklist_entries WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<BlacklistEntryEntity>>

    @Query("SELECT * FROM blacklist_entries WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<BlacklistEntryEntity>

    @Query("SELECT * FROM blacklist_entries WHERE id = :id")
    suspend fun getById(id: Long): BlacklistEntryEntity?

    @Query("SELECT * FROM blacklist_entries WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): BlacklistEntryEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: BlacklistEntryEntity): Long

    @Update
    suspend fun update(entity: BlacklistEntryEntity)

    @Query("UPDATE blacklist_entries SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM blacklist_entries WHERE id = :id")
    suspend fun delete(id: Long)
}
