package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.SalaryCarryOverLogEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SalaryCarryOverLogsDao {
    @Query("SELECT * FROM salary_carry_over_logs WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<SalaryCarryOverLogEntity>>

    @Query("SELECT * FROM salary_carry_over_logs WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<SalaryCarryOverLogEntity>

    @Query("SELECT * FROM salary_carry_over_logs WHERE id = :id")
    suspend fun getById(id: Long): SalaryCarryOverLogEntity?

    @Query("SELECT * FROM salary_carry_over_logs WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): SalaryCarryOverLogEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: SalaryCarryOverLogEntity): Long

    @Update
    suspend fun update(entity: SalaryCarryOverLogEntity)

    @Query("UPDATE salary_carry_over_logs SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM salary_carry_over_logs WHERE id = :id")
    suspend fun delete(id: Long)
}
