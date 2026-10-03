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
        require(withdrawal.amount.isFinite() && withdrawal.amount > 0 && withdrawal.reversalOfUuid == null) {
            "المبلغ يجب أن يكون موجباً؛ الإلغاء يتم بأمر مستقل"
        }
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
        check(salaryWithdrawalsDao.getByLocalUuid(prepared.localUuid) == null) {
            "السحب موجود أو محذوف سابقاً؛ لا يمكن إعادة إنشائه تحت الهوية نفسها"
        }
        val id = salaryWithdrawalsDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("salary_withdrawals", "insert", prepared.localUuid, prepared)
        id
    }

    override suspend fun softDelete(id: Long) {
        error("لا يمكن حذف سحب معتمد؛ استخدم الإلغاء بقيد عكسي مع السبب")
    }

    override suspend fun reverse(id: Long, reason: String) = db.withTransaction {
        val row = requireNotNull(salaryWithdrawalsDao.getAllOnce().find { it.id == id }) { "السحب غير موجود" }
        require(row.reversalOfUuid == null && row.amount > 0) { "لا يمكن عكس هذه الحركة" }
        val entity = if (row.expenseUuid.isNullOrBlank()) "salary_withdrawals" else "expenses"
        FinancialReversalQueue.enqueue(db, outboxRepository, entity, row.expenseUuid ?: row.localUuid, reason)
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
            check(candidates.isEmpty()) { "السحب معتمد؛ لا يمكن تعديله، استخدم قيداً عكسياً" }
            check(allowCreate) {
                "المصروف القديم بلا رابط UUID موثوق؛ يلزم مراجعته قبل التعديل، ولم تُحفظ تغييرات"
            }
            val now = System.currentTimeMillis()
            val prepared = SalaryWithdrawal(
                // Identical source UUID => identical mirror identity on every device/retry.
                localUuid = UUID.nameUUIDFromBytes(("salary-expense:" + expense.localUuid).toByteArray(Charsets.UTF_8)).toString()
            ).copy(
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
                version = 1
            )
            insert(prepared)
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
