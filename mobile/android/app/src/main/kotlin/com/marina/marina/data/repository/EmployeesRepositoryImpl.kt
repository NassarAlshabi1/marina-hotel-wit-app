package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.EmployeesDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.repository.EmployeeFinancialHistory
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.util.StatusUtils
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class EmployeesRepositoryImpl @Inject constructor(
    private val employeesDao: EmployeesDao,
    private val outboxRepository: OutboxRepository
) : EmployeesRepository {

    override fun getAll(): Flow<List<Employee>> =
        employeesDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(employee: Employee): Long {
        val now = System.currentTimeMillis()
        val prepared = employee.copy(
            localUuid = employee.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (employee.createdAt == 0L) now else employee.createdAt,
            updatedAt = now
        )
        val id = employeesDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("employees", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(employee: Employee) {
        val prepared = employee.copy(updatedAt = System.currentTimeMillis())
        employeesDao.update(prepared.toEntity())
        outboxRepository.enqueueObject("employees", "update", prepared.localUuid, prepared)
    }

    /**
     * Dart terminate (employees_repository.dart l.314-350): the termination
     * TYPE is canonicalized INTO the status field (terminated / resigned /
     * laid_off), the date is a yyyy-MM-dd hotel-day date, and the change is
     * written through the outbox so it syncs to the cloud.
     */
    override suspend fun terminate(id: Long, terminationType: String, terminationDate: String, reason: String?) {
        val canonical = StatusUtils.canonicalEmployeeStatus(terminationType)
        val now = System.currentTimeMillis()
        employeesDao.terminate(
            id,
            status = canonical,
            terminationDate = terminationDate,
            terminationReason = reason,
            updatedAt = now
        )
        val entity = employeesDao.getById(id) ?: return
        val terminated = entity.toDomain().copy(
            status = canonical,
            terminationDate = terminationDate,
            terminationReason = reason,
            updatedAt = now
        )
        outboxRepository.enqueueObject("employees", "update", terminated.localUuid, terminated)
    }

    /** Dart reactivate (employees_repository.dart l.353-383) — status `active` + clear termination fields + outbox. */
    override suspend fun reactivate(id: Long) {
        val now = System.currentTimeMillis()
        employeesDao.reactivate(id, updatedAt = now)
        val entity = employeesDao.getById(id) ?: return
        val reactivated = entity.toDomain().copy(
            status = "active",
            terminationDate = null,
            terminationReason = null,
            updatedAt = now
        )
        outboxRepository.enqueueObject("employees", "update", reactivated.localUuid, reactivated)
    }

    /** Dart delete flow (employees_list.dart l.567-650) — soft delete + outbox. */
    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        val entity = employeesDao.getById(id) ?: return
        employeesDao.softDelete(id, deletedAt = now, updatedAt = now)
        val deleted = entity.toDomain().copy(deletedAt = now, updatedAt = now)
        outboxRepository.enqueueObject("employees", "delete", deleted.localUuid, deleted)
    }

    /**
     * Dart financialHistoryCount (employees_repository.dart l.429-489) — the
     * row is missing locally => `EmployeeFinancialHistory.unknown()` parity
     * (isKnown = false, which also blocks deletion).
     */
    override suspend fun financialHistoryCount(id: Long, localUuid: String): EmployeeFinancialHistory {
        val dashless = localUuid.replace("-", "")
        val counts = employeesDao.financialHistoryCounts(id, dashless)
            ?: return EmployeeFinancialHistory(isKnown = false)
        return EmployeeFinancialHistory(
            withdrawals = counts.withdrawals,
            cycles = counts.cycles,
            payments = counts.payments,
            carryOvers = counts.carryOvers,
            expenses = counts.expenses,
            isKnown = true
        )
    }
}
