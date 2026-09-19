package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.EmployeeEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface EmployeesDao {
    @Query("SELECT * FROM employees WHERE deleted_at IS NULL ORDER BY name")
    fun getAll(): Flow<List<EmployeeEntity>>

    @Query("SELECT * FROM employees WHERE deleted_at IS NULL ORDER BY name")
    suspend fun getAllOnce(): List<EmployeeEntity>

    @Query("SELECT * FROM employees WHERE id = :id AND deleted_at IS NULL")
    suspend fun getById(id: Long): EmployeeEntity?

    @Query("SELECT * FROM employees WHERE name LIKE :search AND deleted_at IS NULL ORDER BY name")
    fun search(search: String): Flow<List<EmployeeEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(employee: EmployeeEntity): Long

    @Update
    suspend fun update(employee: EmployeeEntity)

    @Query("UPDATE employees SET status = :status, termination_date = :terminationDate, termination_reason = :terminationReason, updated_at = :updatedAt WHERE id = :id")
    suspend fun terminate(id: Long, status: String, terminationDate: String?, terminationReason: String?, updatedAt: Long): Int

    @Query("UPDATE employees SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
    @Query("SELECT * FROM employees WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): EmployeeEntity?

}
