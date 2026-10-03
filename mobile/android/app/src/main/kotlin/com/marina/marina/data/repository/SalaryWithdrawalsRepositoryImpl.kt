package com.marina.marina.data.repository

import androidx.room.withTransaction
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.dao.ExpensesDao
import com.marina.marina.data.local.dao.EmployeesDao
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
    private val db: AppDatabase,
    private val expensesDao: ExpensesDao,
    private val salaryWithdrawalsDao: SalaryWithdrawalsDao,
    private val employeesDao: EmployeesDao,
    private val outboxRepository: OutboxRepository
) : SalaryWithdrawalsRepository {

    override fun getAll(): Flow<List<SalaryWithdrawal>> =
        salaryWithdrawalsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override fun getByEmployee(employeeId: Long): Flow<List<SalaryWithdrawal>> =
        salaryWithdrawalsDao.getByEmployee(employeeId).map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(withdrawal: SalaryWithdrawal): Long = db.withTransaction {
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
        id
    }

    override suspend fun softDelete(id: Long) {
      db.withTransaction {
        val now = System.currentTimeMillis()
        val entity = salaryWithdrawalsDao.getAllOnce().find { it.id == id } ?: return@withTransaction
        salaryWithdrawalsDao.softDelete(id, deletedAt = now, updatedAt = now)
        val deleted = entity.toDomain().copy(deletedAt = now, updatedAt = now)
        outboxRepository.enqueueObject("salary_withdrawals", "delete", deleted.localUuid, deleted)
      }
    }

    /** No exp_N fallback: numeric references cannot prove cross-device identity. */
    override suspend fun saveFromExpense(
        expenseId: Long,
        employeeId: Long,
        employeeUuid: String?,
        employeeName: String,
        action: String,
        amount: Double,
        date: String,
        note: String?,
        hotelDayKey: String,
        allowCreate: Boolean
    ) {
        db.withTransaction {
            val expense = requireNotNull(expensesDao.getById(expenseId)) { "المصروف غير موجود" }
            require(expense.localUuid.isNotBlank()) { "المصروف بلا UUID" }
            val employee = requireNotNull(employeesDao.getByIdIncludingDeleted(employeeId)) { "الموظف غير موجود" }
            require(employee.localUuid.isNotBlank()) { "الموظف بلا UUID" }
            require(employeeUuid.isNullOrBlank() || uuidComparable(employeeUuid) == uuidComparable(employee.localUuid)) {
                "employee_uuid does not match the selected employee"
            }
            val candidates = salaryWithdrawalsDao.getByExpenseUuid(expense.localUuid)
            check(candidates.size <= 1) { "توجد روابط مصروف مكررة؛ يلزم مراجعتها" }
            val matched = candidates.singleOrNull()
            check(matched != null || allowCreate) {
                "المصروف القديم بلا رابط UUID موثوق؛ يلزم مراجعته قبل التعديل، ولم تُحفظ تغييرات"
            }
            val now = System.currentTimeMillis()
            val prepared = (matched?.toDomain() ?: SalaryWithdrawal(
                // Identical source UUID => identical mirror identity on every device/retry.
                localUuid = UUID.nameUUIDFromBytes(("salary-expense:" + expense.localUuid).toByteArray(Charsets.UTF_8)).toString()
            )).copy(
                expenseUuid = expense.localUuid,
                employeeId = employee.id,
                employeeUuid = employee.localUuid,
                employeeName = employee.name,
                amount = amount,
                withdrawDate = HotelTimeEngine.parseDate(date) ?: now,
                hotelDayKey = hotelDayKey,
                withdrawalType = action,
                reason = "expense_uuid:" + expense.localUuid,
                description = note,
                updatedAt = now,
                version = if (matched == null) 1 else matched.version.coerceIn(0, 999_999) + 1
            )
            if (matched == null) {
                insert(prepared)
            } else {
                salaryWithdrawalsDao.update(prepared.toEntity())
                outboxRepository.enqueueObject("salary_withdrawals", "update", prepared.localUuid, prepared)
            }
        }
    }

    override suspend fun deleteByExpenseId(expenseId: Long, employeeId: Long?, employeeUuid: String?) {
        db.withTransaction {
            val expense = expensesDao.getById(expenseId) ?: return@withTransaction
            val matches = salaryWithdrawalsDao.getByExpenseUuid(expense.localUuid)
            check(matches.size <= 1) { "توجد روابط مصروف مكررة؛ لم يُرسل أي حذف" }
            check(matches.isNotEmpty() || expense.expenseType.trim() !in EmployeeExpenseTypes.values ||
                (expense.relatedId == null && expense.employeeUuid.isNullOrBlank())) {
                "المصروف القديم بلا رابط UUID موثوق؛ يلزم مراجعته قبل الحذف"
            }
            matches.singleOrNull()?.let { softDelete(it.id) }
        }
    }

    private fun uuidComparable(value: String): String = value.trim().replace("-", "").lowercase()

    override suspend fun getTotalForEmployee(employeeId: Long): Double =
        salaryWithdrawalsDao.getTotalForEmployee(employeeId)

    override suspend fun getTotalForEmployeeByType(employeeId: Long, type: String): Double =
        salaryWithdrawalsDao.getTotalForEmployeeByType(employeeId, type)
}
