package com.marina.marina.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface EmployeesDao {
    @Query("SELECT * FROM employees WHERE deleted_at IS NULL ORDER BY name")
    fun getAll(): Flow<List<Employee>>

    @Query("SELECT * FROM employees WHERE deleted_at IS NULL ORDER BY name")
    fun getAllOnce(): List<Employee>

    @Query("SELECT * FROM employees WHERE id = :id AND deleted_at IS NULL")
    fun getById(id: Long): Employee?

    @Query("SELECT * FROM employees WHERE name LIKE :search AND deleted_at IS NULL ORDER BY name")
    fun search(search: String): Flow<List<Employee>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(employee: Employee): Long

    @Update
    suspend fun update(employee: Employee)

    @Query("UPDATE employees SET status = :status, termination_date = :terminationDate, termination_reason = :terminationReason, updated_at = :updatedAt WHERE id = :id")
    suspend fun terminate(id: Long, status: String, terminationDate: String?, terminationReason: String?, updatedAt: Long): Int

    @Query("UPDATE employees SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
}