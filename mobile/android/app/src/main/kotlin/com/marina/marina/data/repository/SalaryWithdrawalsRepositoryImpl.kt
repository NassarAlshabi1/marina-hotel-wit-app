package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.EmployeesDao
import com.marina.marina.data.local.dao.SalaryWithdrawalsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.SalaryWithdrawal
import com.marina.marina.domain.repository.SalaryWithdrawalsRepository
import com.marina.marina.domain.util.ExpenseReasonMatcher
import com.marina.marina.domain.util.HotelTimeEngine
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class SalaryWithdrawalsRepositoryImpl @Inject constructor(
    private val salaryWithdrawalsDao: SalaryWithdrawalsDao,
    private val employeesDao: EmployeesDao,
    private val outboxRepository: OutboxRepository
) : SalaryWithdrawalsRepository {

    override fun getAll(): Flow<List<SalaryWithdrawal>> =
        salaryWithdrawalsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override fun getByEmployee(employeeId: Long): Flow<List<SalaryWithdrawal>> =
        salaryWithdrawalsDao.getByEmployee(employeeId).map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(withdrawal: SalaryWithdrawal): Long {
        val employee = employeesDao.getByIdIncludingDeleted(withdrawal.employeeId)
            ?: throw IllegalArgumentException("لا يمكن تسجيل سحب لموظف غير موجود")
        val employeeUuid = employee.localUuid.trim()
        require(employeeUuid.isNotEmpty()) { "لا يمكن مزامنة سحب راتب بلا employee_uuid" }
        val now = System.currentTimeMillis()
        val prepared = withdrawal.copy(
            employeeUuid = employeeUuid,
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

    /**
     * Dart saveFromExpense (salary_withdrawals_repository.dart l.164-395):
     * upsert the withdrawal paired with a salary expense via the
     * `exp_<expenseId>` reason key — update in place when it already exists
     * (so repeated edits never duplicate), insert otherwise. Ambiguous
     * legacy matches are rejected; no unrelated withdrawal is auto-deleted.
     */
    override suspend fun saveFromExpense(
        expenseId: Long,
        employeeId: Long,
        employeeUuid: String?,
        employeeName: String,
        action: String,
        amount: Double,
        date: String,
        note: String?,
        hotelDayKey: String
    ) {
        val reasonText = "exp_$expenseId"
        val localEmployeeUuid = employeesDao.getByIdIncludingDeleted(employeeId)
            ?.localUuid?.trim()?.takeIf { it.isNotEmpty() }
        val suppliedEmployeeUuid = employeeUuid?.trim()?.takeIf { it.isNotEmpty() }
        if (
            localEmployeeUuid != null && suppliedEmployeeUuid != null &&
            uuidComparable(localEmployeeUuid) != uuidComparable(suppliedEmployeeUuid)
        ) {
            throw IllegalArgumentException("employee_uuid does not match the selected employee")
        }
        val stableEmployeeUuid = localEmployeeUuid ?: suppliedEmployeeUuid
        val now = System.currentTimeMillis()

        // `exp_<id>` is a legacy local cache, not a global expense key.
        // Scope candidates to the employee and refuse ambiguous matches rather
        // than tombstoning another device's real withdrawal by guess.
        val candidates = salaryWithdrawalsDao.getByReasonLike(reasonText)
            .filter { matchesExpenseRef(it.reason, expenseId) }
            .filter { belongsToEmployee(it.employeeUuid, it.employeeId, stableEmployeeUuid, employeeId) }
        if (candidates.size > 1) {
            throw IllegalStateException(
                "يوجد أكثر من سحب مرشح للمصروف $expenseId للموظف نفسه؛ أوقف التعديل للمراجعة اليدوية"
            )
        }
        val matched = candidates.singleOrNull()

        if (matched != null) {
            // Dart l.259-287: تحديث السجل المقترن في مكانه بكل الحقول المزامنة.
            val updated = matched.toDomain().copy(
                employeeId = employeeId,
                employeeUuid = stableEmployeeUuid
                    ?: matched.employeeUuid?.takeIf { matched.employeeId == employeeId },
                employeeName = employeeName,
                amount = amount,
                withdrawDate = HotelTimeEngine.parseDate(date) ?: now,
                hotelDayKey = hotelDayKey,
                withdrawalType = action,
                reason = reasonText,
                description = note,
                updatedAt = now
            )
            salaryWithdrawalsDao.update(updated.toEntity())
            outboxRepository.enqueueObject("salary_withdrawals", "update", updated.localUuid, updated)
        } else {
            insert(
                SalaryWithdrawal(
                    employeeId = employeeId,
                    employeeUuid = employeeUuid,
                    employeeName = employeeName,
                    amount = amount,
                    withdrawDate = HotelTimeEngine.parseDate(date) ?: now,
                    hotelDayKey = hotelDayKey,
                    withdrawalType = action,
                    reason = reasonText,
                    description = note
                )
            )
        }
    }

    /**
     * Soft-delete only the unique withdrawal associated with this expense
     * and employee. Never guess across duplicate or cross-employee matches.
     */
    override suspend fun deleteByExpenseId(
        expenseId: Long,
        employeeId: Long?,
        employeeUuid: String?
    ) {
        val stableEmployeeUuid = employeeUuid?.trim()?.takeIf { it.isNotEmpty() }
            ?: employeeId?.let { employeesDao.getByIdIncludingDeleted(it)?.localUuid?.trim() }
                ?.takeIf { it.isNotEmpty() }
        if (employeeId == null && stableEmployeeUuid == null) return

        val candidates = salaryWithdrawalsDao.getByReasonLike("exp_$expenseId")
            .filter { matchesExpenseRef(it.reason, expenseId) }
            .filter { belongsToEmployee(it.employeeUuid, it.employeeId, stableEmployeeUuid, employeeId) }
        if (candidates.size > 1) {
            throw IllegalStateException(
                "يوجد أكثر من سحب مرشح للمصروف $expenseId للموظف نفسه؛ لم يُرسل أي حذف"
            )
        }
        val linked = candidates.singleOrNull() ?: return
        val now = System.currentTimeMillis()
        salaryWithdrawalsDao.softDelete(linked.id, now, now)
        val deleted = linked.toDomain().copy(deletedAt = now, updatedAt = now)
        outboxRepository.enqueueObject("salary_withdrawals", "delete", deleted.localUuid, deleted)
    }

    private fun belongsToEmployee(
        currentUuid: String?,
        currentEmployeeId: Long,
        targetUuid: String?,
        targetEmployeeId: Long?
    ): Boolean {
        val target = targetUuid?.trim()?.takeIf { it.isNotEmpty() }
        val current = currentUuid?.trim()?.takeIf { it.isNotEmpty() }
        if (target != null) {
            return current != null && uuidComparable(target) == uuidComparable(current)
        }
        if (current != null) return false
        return targetEmployeeId != null && targetEmployeeId == currentEmployeeId
    }

    private fun uuidComparable(value: String): String =
        value.replace("-", "").trim().lowercase()

    /** Dart expense_reason_matcher.dart حرفياً — exp_<id>(?!\\d). */
    private fun matchesExpenseRef(reason: String?, expenseId: Long): Boolean =
        ExpenseReasonMatcher.matchesExpenseRef(reason, expenseId)

    override suspend fun getTotalForEmployee(employeeId: Long): Double =
        salaryWithdrawalsDao.getTotalForEmployee(employeeId)

    override suspend fun getTotalForEmployeeByType(employeeId: Long, type: String): Double =
        salaryWithdrawalsDao.getTotalForEmployeeByType(employeeId, type)
}
