package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Query

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
}
