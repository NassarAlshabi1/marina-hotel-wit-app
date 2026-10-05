package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import com.marina.marina.data.local.entity.AutoFixRunEntity

data class MaintenanceCounts(
    val quarantined: Long,
    val pendingLinks: Long,
    val missingCarryEmployeeUuid: Long,
    val missingPaymentCycleUuid: Long
)

data class MaintenanceSalaryTotals(
    val cycles: Long,
    val expected: Long,
    val paid: Long,
    val remaining: Long
)

/** Intentionally excludes payload: even one quarantined payload can be very large. */
data class MaintenanceQuarantineRow(val entity: String, val recordKey: String, val reason: String)

data class MaintenanceIntegrity(
    val missingEmployees: Long, val missingCycles: Long,
    val mismatchedEmployees: Long, val mismatchedCycles: Long,
    val duplicateEmployeeUuids: Long, val duplicateCycleUuids: Long
)
data class QuarantineDetail(val entity: String, val recordKey: String, val reason: String, val payloadCharacters: Long)

@Dao
interface MaintenanceDao {
    @Query("""
        SELECT
        (SELECT COUNT(*) FROM sync_quarantine) AS quarantined,
        (SELECT COUNT(*) FROM pending_sync_links) AS pendingLinks,
        (SELECT COUNT(*) FROM salary_carry_over_logs WHERE deleted_at IS NULL
            AND (employee_uuid IS NULL OR TRIM(employee_uuid) = '')) AS missingCarryEmployeeUuid,
        (SELECT COUNT(*) FROM salary_payments WHERE deleted_at IS NULL
            AND (cycle_uuid IS NULL OR TRIM(cycle_uuid) = '')) AS missingPaymentCycleUuid
    """)
    suspend fun counts(): MaintenanceCounts

    @Query("""
        SELECT COUNT(*) AS cycles, COALESCE(SUM(expected_amount), 0) AS expected,
            COALESCE(SUM(actual_paid), 0) AS paid, COALESCE(SUM(remaining_amount), 0) AS remaining
        FROM salary_cycles WHERE deleted_at IS NULL
    """)
    suspend fun salaryTotals(): MaintenanceSalaryTotals

    @Query("""
        SELECT entity, recordKey, SUBSTR(reason, 1, 500) AS reason FROM sync_quarantine
        ORDER BY entity, recordKey LIMIT :limit OFFSET :offset
    """)
    suspend fun quarantinePage(limit: Int, offset: Long): List<MaintenanceQuarantineRow>

    @Query("""SELECT COUNT(*) FROM sync_quarantine
        WHERE (:entity IS NULL OR entity = :entity) AND
        (:search = '' OR INSTR(LOWER(entity || ' ' || recordKey || ' ' || reason), LOWER(:search)) > 0)""")
    suspend fun filteredCount(search: String, entity: String?): Long

    @Query("""SELECT entity, recordKey, SUBSTR(reason, 1, 500) AS reason FROM sync_quarantine
        WHERE (:entity IS NULL OR entity = :entity) AND
        (:search = '' OR INSTR(LOWER(entity || ' ' || recordKey || ' ' || reason), LOWER(:search)) > 0)
        ORDER BY entity, recordKey LIMIT :limit OFFSET :offset""")
    suspend fun filteredPage(search: String, entity: String?, limit: Int, offset: Long): List<MaintenanceQuarantineRow>

    @Query("SELECT DISTINCT entity FROM sync_quarantine ORDER BY entity LIMIT 40")
    suspend fun quarantineEntities(): List<String>

    @Query("""SELECT entity, recordKey, SUBSTR(reason, 1, 2000) AS reason,
        LENGTH(payload) AS payloadCharacters FROM sync_quarantine
        WHERE entity = :entity AND recordKey = :key LIMIT 1""")
    suspend fun quarantineDetail(entity: String, key: String): QuarantineDetail?

    @Query("SELECT * FROM auto_fix_runs WHERE source = 'maintenance_uuid_cache' ORDER BY id DESC LIMIT :limit OFFSET :offset")
    suspend fun repairHistory(limit: Int = 20, offset: Long = 0): List<AutoFixRunEntity>

    @Query("SELECT COUNT(*) FROM auto_fix_runs WHERE source = 'maintenance_uuid_cache'")
    suspend fun repairHistoryCount(): Long

    @Query("""SELECT
        (SELECT COUNT(*) FROM salary_carry_over_logs c LEFT JOIN employees p ON p.id = c.employee_id
            WHERE c.deleted_at IS NULL AND (p.id IS NULL OR p.deleted_at IS NOT NULL)) AS missingEmployees,
        (SELECT COUNT(*) FROM salary_payments c LEFT JOIN salary_cycles p ON p.id = c.cycle_id
            WHERE c.deleted_at IS NULL AND (p.id IS NULL OR p.deleted_at IS NOT NULL)) AS missingCycles,
        (SELECT COUNT(*) FROM salary_carry_over_logs c JOIN employees p ON p.id = c.employee_id
            WHERE c.deleted_at IS NULL AND TRIM(COALESCE(c.employee_uuid,'')) != ''
            AND LOWER(REPLACE(TRIM(c.employee_uuid),'-','')) != LOWER(REPLACE(TRIM(p.local_uuid),'-','')))
            AS mismatchedEmployees,
        (SELECT COUNT(*) FROM salary_payments c JOIN salary_cycles p ON p.id = c.cycle_id
            WHERE c.deleted_at IS NULL AND TRIM(COALESCE(c.cycle_uuid,'')) != ''
            AND LOWER(REPLACE(TRIM(c.cycle_uuid),'-','')) != LOWER(REPLACE(TRIM(p.local_uuid),'-','')))
            AS mismatchedCycles,
        (SELECT COUNT(*) FROM (SELECT local_uuid FROM employees WHERE TRIM(local_uuid) != ''
            GROUP BY LOWER(REPLACE(TRIM(local_uuid),'-','')) HAVING COUNT(*) > 1)) AS duplicateEmployeeUuids,
        (SELECT COUNT(*) FROM (SELECT local_uuid FROM salary_cycles WHERE TRIM(local_uuid) != ''
            GROUP BY LOWER(REPLACE(TRIM(local_uuid),'-','')) HAVING COUNT(*) > 1)) AS duplicateCycleUuids
    """)
    suspend fun integrity(): MaintenanceIntegrity
}
