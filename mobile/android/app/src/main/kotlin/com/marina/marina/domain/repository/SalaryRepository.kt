package com.marina.marina.domain.repository

import com.marina.marina.domain.model.SalaryCarryOverLog
import com.marina.marina.domain.model.SalaryCycle
import com.marina.marina.domain.model.SalaryPayment
import kotlinx.coroutines.flow.Flow

interface SalaryRepository {
    fun getCycles(employeeId: Long): Flow<List<SalaryCycle>>
    suspend fun getCycleByKey(cycleKey: String): SalaryCycle?
    suspend fun insertCycle(cycle: SalaryCycle): Long
    suspend fun updateCycle(cycle: SalaryCycle)
    suspend fun getPayments(cycleId: Long): List<SalaryPayment>
    suspend fun insertPayment(payment: SalaryPayment): Long
    suspend fun carryOver(employeeId: Long, amount: Double, fromCycle: String, toCycle: String, reason: String, performedBy: String?): Long
    suspend fun getCarryOverLogs(employeeId: Long): List<SalaryCarryOverLog>
}
