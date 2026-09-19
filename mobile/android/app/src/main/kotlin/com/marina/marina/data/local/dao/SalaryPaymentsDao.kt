package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.SalaryPaymentEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SalaryPaymentsDao {
    @Query("SELECT * FROM salary_payments WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<SalaryPaymentEntity>>

    @Query("SELECT * FROM salary_payments WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<SalaryPaymentEntity>

    @Query("SELECT * FROM salary_payments WHERE id = :id")
    suspend fun getById(id: Long): SalaryPaymentEntity?

    @Query("SELECT * FROM salary_payments WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): SalaryPaymentEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: SalaryPaymentEntity): Long

    @Update
    suspend fun update(entity: SalaryPaymentEntity)

    @Query("UPDATE salary_payments SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM salary_payments WHERE id = :id")
    suspend fun delete(id: Long)
}
