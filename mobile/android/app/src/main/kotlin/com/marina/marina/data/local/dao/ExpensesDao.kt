package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.ExpenseEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ExpensesDao {
    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL ORDER BY date DESC")
    fun getAll(): Flow<List<ExpenseEntity>>

    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL ORDER BY date DESC")
    suspend fun getAllOnce(): List<ExpenseEntity>

    @Query("SELECT * FROM expenses WHERE id = :id AND deleted_at IS NULL")
    suspend fun getById(id: Long): ExpenseEntity?

    @Query("SELECT * FROM expenses WHERE expense_type LIKE :search AND deleted_at IS NULL ORDER BY date DESC")
    fun search(search: String): Flow<List<ExpenseEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(expense: ExpenseEntity): Long

    @Update
    suspend fun update(expense: ExpenseEntity)

    @Query("UPDATE expenses SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
    @Query("SELECT * FROM expenses WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): ExpenseEntity?

}
