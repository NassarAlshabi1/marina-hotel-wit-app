package com.marina.marina.data.repository

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

    /**
     * Dart saveFromExpense (salary_withdrawals_repository.dart l.164-395):
     * upsert the withdrawal paired with a salary expense via the
     * `exp_<expenseId>` reason key — update in place when it already exists
     * (so repeated edits never duplicate), insert otherwise, **plus** the
     * stale-record cleanup that soft-deletes any OTHER withdrawal still
     * referencing the same expense (the anti-duplication guarantee the
     * expenses report relies on).
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
        val now = System.currentTimeMillis()

        // Dart l.181-191 (الطريقة 2): بحث عبر المرجع مع تحقق lookahead —
        // exp_1 لا تطابق exp_10/exp_100 (expense_reason_matcher.dart).
        // (لا عمود expense_id في مخطط Kotlin — tier-1 يتطلب تغيير مخطط؛
        //  كل الروابط التي ينتجها التطبيق تمر عبر reason فتُغطى هنا).
        val reasonMatches = salaryWithdrawalsDao.getByReasonLike(reasonText)
            .filter { matchesExpenseRef(it.reason, expenseId) }
        val matched = reasonMatches.firstOrNull()

        // Dart l.212-250: سجلات قديمة أخرى بنفس مرجع المصروف — تنظيف فوري
        // (soft-delete + دفع deleted_at للسحابة) لمنع التكرار عند التعديل.
        if (matched != null) {
            reasonMatches.filter { it.id != matched.id }.forEach { stale ->
                salaryWithdrawalsDao.softDelete(stale.id, now, now)
                val deleted = stale.toDomain().copy(deletedAt = now, updatedAt = now)
                outboxRepository.enqueueObject("salary_withdrawals", "delete", deleted.localUuid, deleted)
            }
        }

        if (matched != null) {
            // Dart l.259-287: تحديث السجل المقترن في مكانه بكل الحقول المزامنة.
            val updated = matched.toDomain().copy(
                employeeId = employeeId,
                employeeUuid = employeeUuid,
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
     * Dart deleteByExpenseId (l.411-470) — soft-delete لكل السحوبات المقترنة
     * بمصروف عبر مرجع exp_<expenseId> + دفع الحذف للسحابة. يُستدعى عند حذف
     * مصروف راتب وتحويله لنوع غير راتبي (عقد expenses_list.dart).
     */
    override suspend fun deleteByExpenseId(expenseId: Long) {
        val now = System.currentTimeMillis()
        val toDelete = salaryWithdrawalsDao.getByReasonLike("exp_$expenseId")
            .filter { matchesExpenseRef(it.reason, expenseId) }
        toDelete.forEach { linked ->
            salaryWithdrawalsDao.softDelete(linked.id, now, now)
            val deleted = linked.toDomain().copy(deletedAt = now, updatedAt = now)
            outboxRepository.enqueueObject("salary_withdrawals", "delete", deleted.localUuid, deleted)
        }
    }

    /** Dart expense_reason_matcher.dart حرفياً — exp_<id>(?!\d). */
    private fun matchesExpenseRef(reason: String?, expenseId: Long): Boolean =
        ExpenseReasonMatcher.matchesExpenseRef(reason, expenseId)

    override suspend fun getTotalForEmployee(employeeId: Long): Double =
        salaryWithdrawalsDao.getTotalForEmployee(employeeId)

    override suspend fun getTotalForEmployeeByType(employeeId: Long, type: String): Double =
        salaryWithdrawalsDao.getTotalForEmployeeByType(employeeId, type)
}
