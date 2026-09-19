package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.AppSessionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AppSessionsDao {
    @Query("SELECT * FROM app_sessions ORDER BY id DESC")
    fun getAll(): Flow<List<AppSessionEntity>>

    @Query("SELECT * FROM app_sessions ORDER BY id DESC")
    suspend fun getAllOnce(): List<AppSessionEntity>

    @Query("SELECT * FROM app_sessions WHERE id = :id")
    suspend fun getById(id: Long): AppSessionEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: AppSessionEntity): Long

    @Query("DELETE FROM app_sessions WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("DELETE FROM app_sessions")
    suspend fun clearAll()
}
