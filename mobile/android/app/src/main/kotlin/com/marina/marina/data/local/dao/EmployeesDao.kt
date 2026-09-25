package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.EmployeeEntity
import kotlinx.coroutines.flow.Flow

/** Row of the Dart `financialHistoryCount` query (employees_repository.dart l.429-489). */
data class EmployeeFinancialHistoryCounts(
    val withdrawals: Int,
    val cycles: Int,
    val payments: Int,
    val carryOvers: Int,
    val expenses: Int
)

@Dao
interface EmployeesDao {
    @Query("SELECT * FROM employees WHERE deleted_at IS NULL ORDER BY name")
    fun getAll(): Flow<List<EmployeeEntity>>

    @Query("SELECT * FROM employees WHERE deleted_at IS NULL ORDER BY name")
    suspend fun getAllOnce(): List<EmployeeEntity>

    @Query("SELECT * FROM employees WHERE id = :id AND deleted_at IS NULL")
    suspend fun getById(id: Long): EmployeeEntity?

    @Query("SELECT * FROM employees WHERE name LIKE :search AND deleted_at IS NULL ORDER BY name")
    fun search(search: String): Flow<List<EmployeeEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(employee: EmployeeEntity): Long

    @Update
    suspend fun update(employee: EmployeeEntity)

    @Query("UPDATE employees SET status = :status, termination_date = :terminationDate, termination_reason = :terminationReason, updated_at = :updatedAt WHERE id = :id")
    suspend fun terminate(id: Long, status: String, terminationDate: String?, terminationReason: String?, updatedAt: Long): Int

    @Query("UPDATE employees SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
    @Query("SELECT * FROM employees WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): EmployeeEntity?

    /**
     * Dart `EmployeesRepository.reactivate` (employees_repository.dart
     * l.353-383): status -> `active`, termination date/reason cleared.
     */
    @Query(
        "UPDATE employees SET status = 'active', termination_date = NULL, " +
            "termination_reason = NULL, updated_at = :updatedAt WHERE id = :id"
    )
    suspend fun reactivate(id: Long, updatedAt: Long): Int

    /**
     * Dart `financialHistoryCount` (employees_repository.dart l.429-489) —
     * count the employee's financial history across the five linked tables
     * before a delete: employee_uuid (dash-insensitive) first, then the
     * numeric id fallback, exactly like the Flutter contract.
     */
    @Query(
        """
        SELECT
        (SELECT COUNT(*) FROM salary_withdrawals w WHERE
           (w.employee_uuid IS NOT NULL AND REPLACE(w.employee_uuid, '-', '') = :dashlessUuid)
         OR (w.employee_uuid IS NULL AND w.employee_id = :id)) AS withdrawals,
        (SELECT COUNT(*) FROM salary_cycles c WHERE
           (c.employee_uuid IS NOT NULL AND REPLACE(c.employee_uuid, '-', '') = :dashlessUuid)
         OR (c.employee_uuid IS NULL AND c.employee_id = :id)) AS cycles,
        (SELECT COUNT(*) FROM salary_payments p WHERE
           p.employee_uuid IS NOT NULL
           AND REPLACE(p.employee_uuid, '-', '') = :dashlessUuid) AS payments,
        (SELECT COUNT(*) FROM salary_carry_over_logs k WHERE
           k.employee_id = :id) AS carryOvers,
        (SELECT COUNT(*) FROM expenses x WHERE
           (x.employee_uuid IS NOT NULL AND REPLACE(x.employee_uuid, '-', '') = :dashlessUuid)
         OR (x.employee_uuid IS NULL AND x.related_id = :id
             AND TRIM(x.expense_type) IN ('سحب راتب','رواتب','سحب من الراتب','سلفة','خصم من الراتب','خصم راتب','خصم','غياب','employee'))) AS expenses
        FROM employees WHERE id = :id
        """
    )
    suspend fun financialHistoryCounts(id: Long, dashlessUuid: String): EmployeeFinancialHistoryCounts?

    /** البحث الشامل — كل الصفوف بما فيها المحذوفة ناعمياً (تدقيق المدير). */
    @Query("SELECT * FROM employees")
    suspend fun listAllIncludingDeleted(): List<EmployeeEntity>

    /**
     * ✅ (2026-09-25) ظلّ هوية الخادم — ترجمة FK عند السحب (تكافؤ
     * IdResolver.resolveEmployee رجل serverId في Dart): مؤشرات الأبناء
     * (employee_id من جهاز المصدر) قد تحمل id خادمياً؛ يشمل المحذوفة
     * ناعمياً وظبط الحسم عند الازدواج (النشط أولاً ثم الأصغر id).
     */
    @Query(
        """
        SELECT * FROM employees WHERE server_id = :serverId
        ORDER BY deleted_at ASC, id ASC LIMIT 1
        """
    )
    suspend fun getByServerIdIncludingDeleted(serverId: Long): EmployeeEntity?
}
