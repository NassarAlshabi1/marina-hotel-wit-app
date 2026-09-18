package com.marina.marina.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface ExpensesDao {
    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL ORDER BY date DESC")
    fun getAll(): Flow<List<Expense>>

    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL ORDER BY date DESC")
    fun getAllOnce(): List<Expense>

    @Query("SELECT * FROM expenses WHERE id = :id AND deleted_at IS NULL")
    fun getById(id: Long): Expense?

    @Query("SELECT * FROM expenses WHERE expense_type LIKE :search AND deleted_at IS NULL ORDER BY date DESC")
    fun search(search: String): Flow<List<Expense>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(expense: Expense): Long

    @Update
    suspend fun update(expense: Expense)

    @Query("UPDATE expenses SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
}