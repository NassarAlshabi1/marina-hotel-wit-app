package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.AncestorCacheEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AncestorCacheDao {
    @Query("SELECT * FROM ancestor_cache ORDER BY id DESC")
    fun getAll(): Flow<List<AncestorCacheEntity>>

    @Query("SELECT * FROM ancestor_cache ORDER BY id DESC")
    suspend fun getAllOnce(): List<AncestorCacheEntity>

    @Query("SELECT * FROM ancestor_cache WHERE id = :id")
    suspend fun getById(id: Long): AncestorCacheEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: AncestorCacheEntity): Long

    @Query("DELETE FROM ancestor_cache WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("DELETE FROM ancestor_cache")
    suspend fun clearAll()
}
