package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.SalaryCycleEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SalaryCyclesDao {
    @Query("SELECT * FROM salary_cycles WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<SalaryCycleEntity>>

    @Query("SELECT * FROM salary_cycles WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<SalaryCycleEntity>

    @Query("SELECT * FROM salary_cycles WHERE id = :id")
    suspend fun getById(id: Long): SalaryCycleEntity?

    @Query("SELECT * FROM salary_cycles WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): SalaryCycleEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: SalaryCycleEntity): Long

    @Update
    suspend fun update(entity: SalaryCycleEntity)

    @Query("UPDATE salary_cycles SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM salary_cycles WHERE id = :id")
    suspend fun delete(id: Long)
}
