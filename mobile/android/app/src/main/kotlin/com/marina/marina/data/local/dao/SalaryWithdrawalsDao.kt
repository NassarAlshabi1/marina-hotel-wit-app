package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.SalaryWithdrawalEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SalaryWithdrawalsDao {

    @Query("SELECT * FROM salary_withdrawals WHERE deleted_at IS NULL ORDER BY withdraw_date DESC")
    fun getAll(): Flow<List<SalaryWithdrawalEntity>>

    @Query("SELECT * FROM salary_withdrawals WHERE deleted_at IS NULL ORDER BY withdraw_date DESC")
    suspend fun getAllOnce(): List<SalaryWithdrawalEntity>

    @Query("SELECT * FROM salary_withdrawals WHERE deleted_at IS NULL AND employee_id = :employeeId ORDER BY withdraw_date DESC")
    fun getByEmployee(employeeId: Long): Flow<List<SalaryWithdrawalEntity>>

    @Query("SELECT * FROM salary_withdrawals WHERE deleted_at IS NULL AND hotel_day_key = :hotelDayKey ORDER BY withdraw_date DESC")
    fun getByHotelDay(hotelDayKey: String): Flow<List<SalaryWithdrawalEntity>>

    @Query("SELECT COALESCE(SUM(amount), 0) FROM salary_withdrawals WHERE deleted_at IS NULL AND employee_id = :employeeId")
    suspend fun getTotalForEmployee(employeeId: Long): Double

    @Query("SELECT COALESCE(SUM(amount), 0) FROM salary_withdrawals WHERE deleted_at IS NULL AND withdrawal_type = :type AND employee_id = :employeeId")
    suspend fun getTotalForEmployeeByType(employeeId: Long, type: String): Double

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(withdrawal: SalaryWithdrawalEntity): Long

    @Update
    suspend fun update(withdrawal: SalaryWithdrawalEntity)

    @Query("SELECT * FROM salary_withdrawals WHERE deleted_at IS NULL AND reason = :reason LIMIT 1")
    suspend fun getByReason(reason: String): SalaryWithdrawalEntity?

    @Query("UPDATE salary_withdrawals SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
}
