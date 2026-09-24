package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Employee
import kotlinx.coroutines.flow.Flow

/**
 * Dart `EmployeeFinancialHistory` (employees_repository.dart l.528-577) —
 * the delete-guard counters for an employee across the five linked tables.
 */
data class EmployeeFinancialHistory(
    val withdrawals: Int = 0,
    val cycles: Int = 0,
    val payments: Int = 0,
    val carryOvers: Int = 0,
    val expenses: Int = 0,
    /** false = تعذر الفحص (فشل الاستعلام أو غياب الموظف محلياً). */
    val isKnown: Boolean = true
) {
    val total: Int get() = withdrawals + cycles + payments + carryOvers + expenses

    /** هل يُمنع الحذف؟ — يوجد تاريخ مرتبط، أو تعذّر التحقق أصلاً. */
    val blocksDeletion: Boolean get() = !isKnown || total > 0
}

interface EmployeesRepository {
    fun getAll(): Flow<List<Employee>>
    suspend fun insert(employee: Employee): Long
    suspend fun update(employee: Employee)

    /**
     * Dart terminate contract: [terminationType] is فصل / استقالة / استغناء
     * (canonicalized into the status field), [terminationDate] is yyyy-MM-dd.
     */
    suspend fun terminate(id: Long, terminationType: String, terminationDate: String, reason: String? = null)

    /** Dart `reactivate` (employees_repository.dart l.353-383) — status `active`, termination fields cleared. */
    suspend fun reactivate(id: Long)

    /** Dart soft-delete flow (employees_list.dart l.567-650). */
    suspend fun softDelete(id: Long)

    /**
     * Dart `financialHistoryCount` (employees_repository.dart l.429-489) —
     * delete-guard counters; `isKnown = false` when the employee row is
     * missing locally (same `EmployeeFinancialHistory.unknown()` contract).
     */
    suspend fun financialHistoryCount(id: Long, localUuid: String): EmployeeFinancialHistory
}
