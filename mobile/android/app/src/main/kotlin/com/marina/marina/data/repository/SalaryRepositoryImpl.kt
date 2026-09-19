package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.SalaryCarryOverLogsDao
import com.marina.marina.data.local.dao.SalaryCyclesDao
import com.marina.marina.data.local.dao.SalaryPaymentsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.SalaryCarryOverLog
import com.marina.marina.domain.model.SalaryCycle
import com.marina.marina.domain.model.SalaryPayment
import com.marina.marina.domain.repository.SalaryRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class SalaryRepositoryImpl @Inject constructor(
    private val cyclesDao: SalaryCyclesDao,
    private val paymentsDao: SalaryPaymentsDao,
    private val carryOverDao: SalaryCarryOverLogsDao,
    private val outboxRepository: OutboxRepository
) : SalaryRepository {

    override fun getCycles(employeeId: Long): Flow<List<SalaryCycle>> =
        cyclesDao.getAll().map { list -> list.filter { it.employeeId == employeeId }.map { it.toDomain() } }

    override suspend fun getCycleByKey(cycleKey: String): SalaryCycle? =
        cyclesDao.getByKey(cycleKey)?.toDomain()

    override suspend fun insertCycle(cycle: SalaryCycle): Long {
        val now = System.currentTimeMillis()
        val prepared = cycle.copy(
            localUuid = cycle.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (cycle.createdAt == 0L) now else cycle.createdAt,
            updatedAt = now,
            remainingAmount = cycle.expectedAmount - cycle.actualPaid
        )
        val id = cyclesDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("salary_cycles", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun updateCycle(cycle: SalaryCycle) {
        val prepared = cycle.copy(
            updatedAt = System.currentTimeMillis(),
            remainingAmount = cycle.expectedAmount - cycle.actualPaid
        )
        cyclesDao.update(prepared.toEntity())
        outboxRepository.enqueueObject("salary_cycles", "update", prepared.localUuid, prepared)
    }

    override suspend fun getPayments(cycleId: Long): List<SalaryPayment> =
        paymentsDao.getByCycle(cycleId).map { it.toDomain() }

    override suspend fun insertPayment(payment: SalaryPayment): Long {
        val now = System.currentTimeMillis()
        val prepared = payment.copy(
            localUuid = payment.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (payment.createdAt == 0L) now else payment.createdAt
        )
        val id = paymentsDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("salary_payments", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun carryOver(
        employeeId: Long,
        amount: Double,
        fromCycle: String,
        toCycle: String,
        reason: String,
        performedBy: String?
    ): Long {
        val now = System.currentTimeMillis()
        val log = SalaryCarryOverLog(
            employeeId = employeeId,
            amount = amount,
            previousCycleStart = fromCycle,
            previousCycleEnd = fromCycle,
            newCycleStart = toCycle,
            newCycleEnd = toCycle,
            reason = reason,
            carriedAt = now,
            localUuid = UUID.randomUUID().toString()
        )
        val id = carryOverDao.insert(log.toEntity())
        outboxRepository.enqueueObject("salary_carry_over_logs", "insert", log.localUuid, log)
        return id
    }

    override suspend fun getCarryOverLogs(employeeId: Long): List<SalaryCarryOverLog> =
        carryOverDao.getAllOnce().filter { it.employeeId == employeeId }.map { it.toDomain() }
}
