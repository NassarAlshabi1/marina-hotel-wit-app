package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.AutoFixRunEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AutoFixRunsDao {
    @Query("SELECT * FROM auto_fix_runs ORDER BY id DESC")
    fun getAll(): Flow<List<AutoFixRunEntity>>

    @Query("SELECT * FROM auto_fix_runs ORDER BY id DESC")
    suspend fun getAllOnce(): List<AutoFixRunEntity>

    @Query("SELECT * FROM auto_fix_runs WHERE id = :id")
    suspend fun getById(id: Long): AutoFixRunEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: AutoFixRunEntity): Long

    @Query("DELETE FROM auto_fix_runs WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("DELETE FROM auto_fix_runs")
    suspend fun clearAll()
}
