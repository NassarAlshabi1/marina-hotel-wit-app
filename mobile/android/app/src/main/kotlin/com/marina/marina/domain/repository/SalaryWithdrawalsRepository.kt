package com.marina.marina.domain.repository

import com.marina.marina.domain.model.SalaryWithdrawal
import kotlinx.coroutines.flow.Flow

interface SalaryWithdrawalsRepository {
    fun getAll(): Flow<List<SalaryWithdrawal>>
    fun getByEmployee(employeeId: Long): Flow<List<SalaryWithdrawal>>
    suspend fun insert(withdrawal: SalaryWithdrawal): Long

    /** UUID-only mirror upsert; creation is explicitly authorized by the expense transaction. */
    suspend fun saveFromExpense(
        expenseId: Long,
        employeeId: Long,
        employeeUuid: String?,
        employeeName: String,
        action: String,
        amount: Double,
        date: String,
        note: String?,
        hotelDayKey: String,
        allowCreate: Boolean = false
    )

    /** Dart deleteByExpenseId — orphan cleanup when a salary expense is deleted. */
    suspend fun deleteByExpenseId(
        expenseId: Long,
        employeeId: Long? = null,
        employeeUuid: String? = null
    )

    suspend fun softDelete(id: Long)
    suspend fun getTotalForEmployee(employeeId: Long): Double
    suspend fun getTotalForEmployeeByType(employeeId: Long, type: String): Double
}
