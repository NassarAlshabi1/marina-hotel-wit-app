package com.marina.marina.domain.repository

import com.marina.marina.domain.model.SalaryWithdrawal
import kotlinx.coroutines.flow.Flow

interface SalaryWithdrawalsRepository {
    fun getAll(): Flow<List<SalaryWithdrawal>>
    fun getByEmployee(employeeId: Long): Flow<List<SalaryWithdrawal>>
    suspend fun insert(withdrawal: SalaryWithdrawal): Long

    /**
     * Dart createFromExpense (salary_withdrawals_repository.dart l.158-395):
     * the withdrawal linked to a salary expense via the `exp_<expenseId>`
     * reason convention (dedup contract shared with the reports).
     */
    suspend fun insertFromExpense(
        expenseId: Long,
        employeeId: Long,
        employeeUuid: String?,
        employeeName: String,
        amount: Double,
        dateIso: String,
        hotelDayKey: String,
        withdrawalType: String,
        description: String?
    ): Long

    /** Dart deleteByExpenseId — orphan cleanup when a salary expense is deleted. */
    suspend fun deleteByExpenseId(expenseId: Long)

    suspend fun softDelete(id: Long)
    suspend fun getTotalForEmployee(employeeId: Long): Double
    suspend fun getTotalForEmployeeByType(employeeId: Long, type: String): Double
}
