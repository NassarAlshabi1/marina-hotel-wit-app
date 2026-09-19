package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.SyncRemoteMetaEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SyncRemoteMetaDao {
    @Query("SELECT * FROM sync_remote_meta ORDER BY collection, doc_id")
    fun getAll(): Flow<List<SyncRemoteMetaEntity>>

    @Query("SELECT * FROM sync_remote_meta ORDER BY collection, doc_id")
    suspend fun getAllOnce(): List<SyncRemoteMetaEntity>

    @Query("SELECT * FROM sync_remote_meta WHERE collection = :collection AND doc_id = :docId LIMIT 1")
    suspend fun get(collection: String, docId: String): SyncRemoteMetaEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: SyncRemoteMetaEntity)

    @Query("DELETE FROM sync_remote_meta WHERE collection = :collection AND doc_id = :docId")
    suspend fun delete(collection: String, docId: String)

    @Query("DELETE FROM sync_remote_meta")
    suspend fun clearAll()
}
