package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.SalaryWithdrawalsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.SalaryWithdrawal
import com.marina.marina.domain.repository.SalaryWithdrawalsRepository
import com.marina.marina.domain.util.HotelTimeEngine
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class SalaryWithdrawalsRepositoryImpl @Inject constructor(
    private val salaryWithdrawalsDao: SalaryWithdrawalsDao,
    private val outboxRepository: OutboxRepository
) : SalaryWithdrawalsRepository {

    override fun getAll(): Flow<List<SalaryWithdrawal>> =
        salaryWithdrawalsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override fun getByEmployee(employeeId: Long): Flow<List<SalaryWithdrawal>> =
        salaryWithdrawalsDao.getByEmployee(employeeId).map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(withdrawal: SalaryWithdrawal): Long {
        val now = System.currentTimeMillis()
        val prepared = withdrawal.copy(
            localUuid = withdrawal.localUuid.ifBlank { UUID.randomUUID().toString() },
            withdrawDate = if (withdrawal.withdrawDate == 0L) now else withdrawal.withdrawDate,
            hotelDayKey = withdrawal.hotelDayKey ?: HotelTimeEngine.currentHotelDayKey(),
            createdAt = if (withdrawal.createdAt == 0L) now else withdrawal.createdAt,
            updatedAt = now
        )
        val id = salaryWithdrawalsDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("salary_withdrawals", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        val entity = salaryWithdrawalsDao.getAllOnce().find { it.id == id } ?: return
        salaryWithdrawalsDao.softDelete(id, deletedAt = now, updatedAt = now)
        val deleted = entity.toDomain().copy(deletedAt = now, updatedAt = now)
        outboxRepository.enqueueObject("salary_withdrawals", "delete", deleted.localUuid, deleted)
    }

    /**
     * Dart createFromExpense — paired with the salary expense: reason carries
     * `exp_<expenseId>` so the reports can dedup expense vs withdrawal.
     */
    override suspend fun insertFromExpense(
        expenseId: Long,
        employeeId: Long,
        employeeUuid: String?,
        employeeName: String,
        amount: Double,
        dateIso: String,
        hotelDayKey: String,
        withdrawalType: String,
        description: String?
    ): Long {
        return insert(
            SalaryWithdrawal(
                employeeId = employeeId,
                employeeUuid = employeeUuid,
                employeeName = employeeName,
                amount = amount,
                withdrawDate = HotelTimeEngine.parseDate(dateIso) ?: System.currentTimeMillis(),
                hotelDayKey = hotelDayKey,
                withdrawalType = withdrawalType,
                reason = "exp_$expenseId",
                description = description
            )
        )
    }

    /** Dart deleteByExpenseId — removes the paired withdrawal of a deleted expense. */
    override suspend fun deleteByExpenseId(expenseId: Long) {
        val linked = salaryWithdrawalsDao.getByReason("exp_$expenseId") ?: return
        val now = System.currentTimeMillis()
        salaryWithdrawalsDao.softDelete(linked.id, deletedAt = now, updatedAt = now)
        val deleted = linked.toDomain().copy(deletedAt = now, updatedAt = now)
        outboxRepository.enqueueObject("salary_withdrawals", "delete", deleted.localUuid, deleted)
    }

    override suspend fun getTotalForEmployee(employeeId: Long): Double =
        salaryWithdrawalsDao.getTotalForEmployee(employeeId)

    override suspend fun getTotalForEmployeeByType(employeeId: Long, type: String): Double =
        salaryWithdrawalsDao.getTotalForEmployeeByType(employeeId, type)
}
