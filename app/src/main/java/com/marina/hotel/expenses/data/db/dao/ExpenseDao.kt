package com.marina.hotel.expenses.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.marina.hotel.expenses.data.model.Employee
import com.marina.hotel.expenses.data.model.Expense
import kotlinx.coroutines.flow.Flow

@Dao
interface ExpenseDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(expense: Expense): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(expenses: List<Expense>): List<Long>

    @Update
    suspend fun update(expense: Expense): Int

    @Query("DELETE FROM expenses WHERE id = :id")
    suspend fun deleteById(id: Long): Int

    @Query("SELECT * FROM expenses WHERE id = :id AND deleted_at IS NULL")
    suspend fun getById(id: Long): Expense?

    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL ORDER BY date DESC")
    fun getAll(): Flow<List<Expense>>

    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL AND date BETWEEN :start AND :end ORDER BY date DESC")
    fun getByDateRange(start: Long, end: Long): Flow<List<Expense>>

    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL AND expense_type = :type ORDER BY date DESC")
    fun getByType(type: String): Flow<List<Expense>>

    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL AND expense_type = :type AND date BETWEEN :start AND :end ORDER BY date DESC")
    fun getByTypeAndDateRange(type: String, start: Long, end: Long): Flow<List<Expense>>

    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL AND hotel_day_key = :dayKey ORDER BY date DESC")
    fun getByHotelDayKey(dayKey: String): Flow<List<Expense>>

    @Query("SELECT SUM(amount) FROM expenses WHERE deleted_at IS NULL AND date BETWEEN :start AND :end")
    suspend fun getTotalByDateRange(start: Long, end: Long): Double?

    @Query("SELECT SUM(amount) FROM expenses WHERE deleted_at IS NULL AND expense_type = :type AND date BETWEEN :start AND :end")
    suspend fun getTotalByTypeAndDateRange(type: String, start: Long, end: Long): Double?

    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL AND employee_uuid = :employeeUuid ORDER BY date DESC")
    fun getByEmployeeUuid(employeeUuid: String): Flow<List<Expense>>

    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL AND expense_type = 'رواتب' ORDER BY date DESC")
    fun getSalaryExpenses(): Flow<List<Expense>>

    @Transaction
    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL AND expense_type = 'رواتب' AND expense_kind IN ('سحب من الراتب', 'خصم من الراتب', 'سلفة') ORDER BY date DESC")
    fun getSalaryActionExpenses(): Flow<List<Expense>>
}

@Dao
interface EmployeeDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(employee: Employee): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(employees: List<Employee>): List<Long>

    @Update
    suspend fun update(employee: Employee): Int

    @Query("SELECT * FROM employees WHERE id = :id AND deleted_at IS NULL")
    suspend fun getById(id: Long): Employee?

    @Query("SELECT * FROM employees WHERE deleted_at IS NULL ORDER BY name ASC")
    fun getAllActive(): Flow<List<Employee>>

    @Query("SELECT * FROM employees WHERE deleted_at IS NULL AND status = 'active' ORDER BY name ASC")
    fun getActiveEmployees(): Flow<List<Employee>>

    @Query("SELECT * FROM employees WHERE id = :id")
    suspend fun getByIdIncludeDeleted(id: Long): Employee?
}