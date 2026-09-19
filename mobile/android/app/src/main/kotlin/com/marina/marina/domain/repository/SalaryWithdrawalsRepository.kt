package com.marina.marina.domain.repository

import com.marina.marina.domain.model.SalaryWithdrawal
import kotlinx.coroutines.flow.Flow

interface SalaryWithdrawalsRepository {
    fun getAll(): Flow<List<SalaryWithdrawal>>
    fun getByEmployee(employeeId: Long): Flow<List<SalaryWithdrawal>>
    suspend fun insert(withdrawal: SalaryWithdrawal): Long
    suspend fun softDelete(id: Long)
    suspend fun getTotalForEmployee(employeeId: Long): Double
    suspend fun getTotalForEmployeeByType(employeeId: Long, type: String): Double
}
