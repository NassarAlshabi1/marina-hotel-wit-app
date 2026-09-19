package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.IntegrityViolationEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface IntegrityViolationsDao {
    @Query("SELECT * FROM integrity_violations ORDER BY id DESC")
    fun getAll(): Flow<List<IntegrityViolationEntity>>

    @Query("SELECT * FROM integrity_violations ORDER BY id DESC")
    suspend fun getAllOnce(): List<IntegrityViolationEntity>

    @Query("SELECT * FROM integrity_violations WHERE id = :id")
    suspend fun getById(id: Long): IntegrityViolationEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: IntegrityViolationEntity): Long

    @Query("DELETE FROM integrity_violations WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("DELETE FROM integrity_violations")
    suspend fun clearAll()
}
