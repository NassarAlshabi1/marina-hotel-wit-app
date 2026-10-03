package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.EmployeesDao
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
    private val employeesDao: EmployeesDao,
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
        val employee = employeesDao.getByIdIncludingDeleted(cycle.employeeId)
            ?: throw IllegalArgumentException("لا يمكن إنشاء دورة راتب لموظف غير موجود")
        val employeeUuid = employee.localUuid.trim()
        require(employeeUuid.isNotEmpty()) { "لا يمكن مزامنة دورة راتب بلا employee_uuid" }
        val now = System.currentTimeMillis()
        val prepared = cycle.copy(
            employeeUuid = employeeUuid,
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
        val employee = employeesDao.getByIdIncludingDeleted(cycle.employeeId)
            ?: throw IllegalArgumentException("لا يمكن تحديث دورة راتب لموظف غير موجود")
        val employeeUuid = employee.localUuid.trim()
        require(employeeUuid.isNotEmpty()) { "لا يمكن مزامنة دورة راتب بلا employee_uuid" }
        val prepared = cycle.copy(
            employeeUuid = employeeUuid,
            updatedAt = System.currentTimeMillis(),
            remainingAmount = cycle.expectedAmount - cycle.actualPaid
        )
        cyclesDao.update(prepared.toEntity())
        outboxRepository.enqueueObject("salary_cycles", "update", prepared.localUuid, prepared)
    }

    override suspend fun getPayments(cycleId: Long): List<SalaryPayment> =
        paymentsDao.getByCycle(cycleId).map { it.toDomain() }

    override suspend fun insertPayment(payment: SalaryPayment): Long {
        val cycle = cyclesDao.getById(payment.cycleId)
            ?: throw IllegalArgumentException("لا يمكن تسجيل دفعة لدورة راتب غير موجودة")
        val cycleUuid = cycle.localUuid.trim()
        require(cycleUuid.isNotEmpty()) { "لا يمكن مزامنة دفعة بلا cycle_uuid" }
        val employeeUuid = cycle.employeeUuid?.trim()?.takeIf { it.isNotEmpty() }
            ?: employeesDao.getByIdIncludingDeleted(cycle.employeeId)?.localUuid?.trim()?.takeIf { it.isNotEmpty() }
            ?: throw IllegalArgumentException("لا يمكن مزامنة دفعة لدورة بلا employee_uuid")
        val now = System.currentTimeMillis()
        val prepared = payment.copy(
            cycleUuid = cycleUuid,
            employeeUuid = employeeUuid,
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
        val employee = employeesDao.getByIdIncludingDeleted(employeeId)
            ?: throw IllegalArgumentException("لا يمكن ترحيل رصيد لموظف غير موجود")
        val employeeUuid = employee.localUuid.trim()
        require(employeeUuid.isNotEmpty()) { "لا يمكن مزامنة ترحيل رصيد بلا employee_uuid" }
        val now = System.currentTimeMillis()
        val log = SalaryCarryOverLog(
            employeeId = employeeId,
            employeeUuid = employeeUuid,
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
