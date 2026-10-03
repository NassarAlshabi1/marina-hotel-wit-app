package com.marina.marina.data.repository

import androidx.room.withTransaction
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.domain.repository.SalaryWithdrawalsRepository
import com.marina.marina.data.local.dao.EmployeesDao
import com.marina.marina.data.local.dao.ExpensesDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.util.HotelTimeEngine
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class ExpensesRepositoryImpl @Inject constructor(
    private val db: AppDatabase,
    private val withdrawals: SalaryWithdrawalsRepository,
    private val expensesDao: ExpensesDao,
    private val employeesDao: EmployeesDao,
    private val outboxRepository: OutboxRepository
) : ExpensesRepository {

    override fun getAll(): Flow<List<Expense>> =
        expensesDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(expense: Expense): Long = db.withTransaction {
        require(expense.amount.isFinite() && expense.amount > 0 && expense.reversalOfUuid == null) {
            "المبلغ يجب أن يكون موجباً؛ الإلغاء يتم بأمر مستقل"
        }
        val now = System.currentTimeMillis()
        val linkedExpense = attachEmployeeUuid(expense)
        val prepared = linkedExpense.copy(
            localUuid = linkedExpense.localUuid.ifBlank { UUID.randomUUID().toString() },
            date = linkedExpense.date.ifBlank { HotelTimeEngine.formatIso(now) },
            hotelDayKey = linkedExpense.hotelDayKey ?: HotelTimeEngine.currentHotelDayKey(),
            createdAt = if (linkedExpense.createdAt == 0L) now else linkedExpense.createdAt,
            updatedAt = now
        )
        check(expensesDao.getByLocalUuid(prepared.localUuid) == null) { "المصروف موجود؛ استخدم الإلغاء بقيد عكسي عند التصحيح" }
        val id = expensesDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("expenses", "insert", prepared.localUuid, prepared)
        saveMirror(prepared.copy(id = id), allowCreate = true)
        id
    }

    override suspend fun update(expense: Expense) {
        error("المصروف معتمد؛ ألغِه بقيد عكسي ثم سجّل المصروف الصحيح")
    }

    override suspend fun softDelete(id: Long) {
        error("لا يمكن حذف مصروف معتمد؛ استخدم الإلغاء بقيد عكسي مع السبب")
    }

    override suspend fun reverse(id: Long, reason: String) = db.withTransaction {
        val expense = requireNotNull(expensesDao.getById(id)) { "المصروف غير موجود" }
        require(expense.deletedAt == null && expense.reversalOfUuid == null && expense.amount > 0) { "لا يمكن عكس هذه الحركة" }
        if (expense.expenseType.trim() in employeeExpenseTypes &&
            (expense.relatedId != null || !expense.employeeUuid.isNullOrBlank())) {
            val mirrors = db.salaryWithdrawalsDao().getByExpenseUuid(expense.localUuid)
            check(mirrors.size == 1) { "رابط السحب غير مؤكد؛ يلزم المزامنة أو المراجعة قبل الإلغاء" }
        }
        FinancialReversalQueue.enqueue(db, outboxRepository, "expenses", expense.localUuid, reason)
    }

    override fun watchReversalRequests(): Flow<Map<String, String>> =
        db.outboxDao().watchReversals().map { rows ->
            rows.filter { it.entity == "expenses" }.associate { row ->
                row.localUuid to when {
                    row.deliveredToPrimary -> "قُبل الطلب؛ بانتظار جلب القيد"
                    row.processingStatus == "completed" -> "رُفض الطلب: ${row.primaryLastError.orEmpty()}"
                    else -> "إلغاء بانتظار المزامنة"
                }
            }
        }

    private suspend fun saveMirror(expense: Expense, allowCreate: Boolean) {
        if (expense.expenseType.trim() !in employeeExpenseTypes || expense.relatedId == null) return
        withdrawals.saveFromExpense(
            expenseId = expense.id, employeeId = expense.relatedId,
            employeeUuid = expense.employeeUuid, employeeName = "",
            action = expense.expenseType, amount = expense.amount, date = expense.date,
            note = expense.description, hotelDayKey = expense.hotelDayKey ?: HotelTimeEngine.currentHotelDayKey(),
            allowCreate = allowCreate
        )
    }

    override suspend fun getAllOnce(): List<Expense> =
        expensesDao.getAllOnce().map { it.toDomain() }

    private val salaryTypes = setOf(
        "رواتب", "سحب راتب", "سحب من الراتب", "سلفة", "خصم راتب", "خصم من الراتب", "خصم", "غياب"
    )
    private val employeeExpenseTypes = EmployeeExpenseTypes.values

    /** Fill the stable employee key for every newly written employee expense. */
    private suspend fun attachEmployeeUuid(expense: Expense): Expense {
        if (expense.expenseType.trim().lowercase() !in employeeExpenseTypes) return expense
        val employeeId = expense.relatedId ?: run {
            require(expense.employeeUuid.isNullOrBlank()) { "علاقة الموظف لم تُحل محلياً بعد" }
            return expense
        }
        val employee = requireNotNull(employeesDao.getByIdIncludingDeleted(employeeId)) { "الموظف غير موجود" }
        val employeeUuid = employee.localUuid.trim()
        require(employeeUuid.isNotEmpty()) { "الموظف بلا UUID" }
        require(expense.employeeUuid.isNullOrBlank() ||
            expense.employeeUuid.trim().replace("-", "").lowercase() == employeeUuid.replace("-", "").lowercase()) {
            "employee_uuid does not match the selected employee"
        }
        return expense.copy(employeeUuid = employeeUuid)
    }

    override suspend fun listFilteredByHotelDay(
        fromHotelDay: String?,
        toHotelDay: String?,
        expenseType: String?,
        search: String?
    ): List<Expense> {
        // Dart SqlDateRange.forDay(toHotelDay).endExclusive — next calendar day.
        val toExclusive = toHotelDay?.let { key ->
            HotelTimeEngine.parseDate("$key 00:00:00")?.let { ms ->
                val cal = java.util.Calendar.getInstance()
                cal.timeInMillis = ms
                cal.add(java.util.Calendar.DAY_OF_YEAR, 1)
                HotelTimeEngine.formatIso(cal.timeInMillis).replace("T", " ").substring(0, 10)
            }
        }
        val isSalaryType = expenseType != null && salaryTypes.contains(expenseType)
        val trimmedSearch = search?.trim()?.takeIf { it.isNotEmpty() }
        return expensesDao.listFilteredByHotelDay(
            fromHotelDay = fromHotelDay,
            toHotelDay = toHotelDay,
            toHotelDayExclusive = toExclusive,
            expenseType = expenseType,
            isSalaryType = isSalaryType,
            search = trimmedSearch
        ).map { it.toDomain() }
    }

    override fun watchTotalByHotelDayKey(hotelDayKey: String): Flow<Double> =
        expensesDao.watchTotalByHotelDayKey(hotelDayKey, "${hotelDayKey}%")
}
