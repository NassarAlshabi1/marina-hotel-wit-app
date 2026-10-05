package com.marina.marina.data.diagnostics

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.entity.PendingSyncLinkEntity
import com.marina.marina.data.local.entity.SalaryCarryOverLogEntity
import com.marina.marina.data.local.entity.SalaryCycleEntity
import com.marina.marina.data.local.entity.SalaryPaymentEntity
import com.marina.marina.data.local.entity.SyncQuarantineEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class MaintenanceRepositoryTest {
    private lateinit var db: AppDatabase
    private lateinit var repository: MaintenanceRepository

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java).allowMainThreadQueries().build()
        repository = MaintenanceRepository(db)
    }

    @After fun close() { db.close() }

    @Test
    fun literalSearchEntityFilterAndDetailsDoNotLoadPayload() = runBlocking {
        db.syncQuarantineDao().put(SyncQuarantineEntity("rooms", "uuid:a", "secret-payload", "Missing 100% value"))
        db.syncQuarantineDao().put(SyncQuarantineEntity("employees", "uuid:b", "other-secret", "Missing UUID"))
        assertEquals(1L, repository.read(search = "%").filteredCount)
        assertEquals(2L, repository.read(search = "missing").filteredCount)
        assertEquals(1L, repository.read(entity = "rooms").filteredCount)
        assertEquals(0L, repository.read(search = "' OR 1=1 --").filteredCount)
        val detail = repository.detail("rooms", "uuid:a")!!
        assertEquals("secret-payload".length.toLong(), detail.payloadCharacters)
        assertFalse(detail.toString().contains("secret-payload"))
        assertTrue(repository.quickCheck())
    }

    @Test
    fun historyIsBoundedPagedAndExcludesOtherRepairSources() = runBlocking {
        repeat(23) { i -> db.autoFixRunsDao().insert(com.marina.marina.data.local.entity.AutoFixRunEntity(
            runUuid = "run-$i", source = MaintenanceRepairService.SOURCE, status = "completed",
            startedAtEpoch = i.toLong(), startedAtIso = "test"
        )) }
        db.autoFixRunsDao().insert(com.marina.marina.data.local.entity.AutoFixRunEntity(
            runUuid = "not-maintenance", source = "restore", startedAtEpoch = 1L, startedAtIso = "test"
        ))
        val first = repository.read()
        val second = repository.read(requestedHistoryPage = 99)
        assertEquals(23L, first.historyCount)
        assertEquals(20, first.history.size)
        assertEquals(1L, second.historyPage)
        assertEquals(3, second.history.size)
        assertTrue(first.history.none { row -> second.history.any { it.id == row.id } })
    }

    @Test
    fun emptyDatabaseHasZeroCountsAndClampsPage() = runBlocking {
        val report = repository.read(Long.MAX_VALUE)
        assertEquals(AppDatabase.SCHEMA_VERSION, report.schemaVersion)
        assertEquals(0L, report.page)
        assertEquals(0L, report.counts.quarantined)
        assertEquals(0L, report.counts.pendingLinks)
        assertEquals(0L, report.counts.missingCarryEmployeeUuid)
        assertEquals(0L, report.counts.missingPaymentCycleUuid)
        assertEquals(0L, report.salary.cycles)
        assertEquals(0L, report.salary.expected)
        assertEquals(0L, report.salary.paid)
        assertEquals(0L, report.salary.remaining)
        assertTrue(report.rows.isEmpty())
        assertFalse(report.hasNext)
    }

    @Test
    fun salarySummaryUsesActualColumnsAndExcludesDeletedRowsWithoutWriting() = runBlocking {
        val cycle = SalaryCycleEntity(employeeId = 1, cycleKey = "active", localUuid = "cycle",
            expectedAmount = 300_000L, actualPaid = 200_000L, remainingAmount = 100_000L)
        val cycleId = db.salaryCyclesDao().insert(cycle)
        db.salaryCyclesDao().insert(cycle.copy(localUuid = "deleted-cycle", cycleKey = "deleted",
            deletedAt = 1L, expectedAmount = 999_999L))
        fun payment(key: String, uuid: String?, deleted: Long? = null) = SalaryPaymentEntity(
            cycleId = cycleId, cycleUuid = uuid, paymentDateIso = "2026-10-05", localUuid = key,
            deletedAt = deleted, amount = 10L
        )
        db.salaryPaymentsDao().insert(payment("null", null))
        db.salaryPaymentsDao().insert(payment("blank", "  "))
        db.salaryPaymentsDao().insert(payment("linked", "cycle"))
        db.salaryPaymentsDao().insert(payment("deleted", null, 1L))
        fun carry(key: String, uuid: String?, deleted: Long? = null) = SalaryCarryOverLogEntity(
            employeeId = 1, employeeUuid = uuid, amount = 15.0, previousCycleStart = "old",
            previousCycleEnd = "old", newCycleStart = "new", newCycleEnd = "new", reason = "test",
            carriedAt = 1L, localUuid = key, deletedAt = deleted
        )
        db.salaryCarryOverLogsDao().insert(carry("null", null))
        db.salaryCarryOverLogsDao().insert(carry("blank", " "))
        db.salaryCarryOverLogsDao().insert(carry("linked", "employee"))
        db.salaryCarryOverLogsDao().insert(carry("deleted", null, 1L))
        db.pendingSyncLinksDao().put(PendingSyncLinkEntity("salary_payments", "pending", "{}"))
        val before = db.salaryCyclesDao().getById(cycleId)
        val report = repository.read()
        assertEquals(1L, report.salary.cycles)
        assertEquals(300_000L, report.salary.expected)
        assertEquals(200_000L, report.salary.paid)
        assertEquals(100_000L, report.salary.remaining)
        assertEquals(2L, report.counts.missingPaymentCycleUuid)
        assertEquals(2L, report.counts.missingCarryEmployeeUuid)
        assertEquals(1L, report.counts.pendingLinks)
        assertEquals(before, db.salaryCyclesDao().getById(cycleId))
        assertEquals(1, db.pendingSyncLinksDao().getAll().size)
        assertTrue(db.outboxDao().getPendingPrimary().first().isEmpty())
    }

    @Test
    fun quarantineIsPagedWithoutPayloadsAndHandlesShrinkingData() = runBlocking {
        val payload = "private-payload".repeat(1_000)
        repeat(51) { index ->
            db.syncQuarantineDao().put(SyncQuarantineEntity("rooms", "key-${index.toString().padStart(3, '0')}",
                payload, "reason".repeat(200)))
        }
        val first = repository.read(-1)
        assertEquals(0L, first.page)
        assertEquals(51L, first.counts.quarantined)
        assertEquals(50, first.rows.size)
        assertTrue(first.rows.all { it.reason.length == 500 })
        assertTrue(first.hasNext)
        assertFalse(first.rows.toString().contains("private-payload"))
        val last = repository.read(999)
        assertEquals(1L, last.page)
        assertEquals(1, last.rows.size)
        assertFalse(last.hasNext)
        assertTrue(first.rows.none { it.recordKey == last.rows.single().recordKey })
        db.syncQuarantineDao().remove("rooms", last.rows.single().recordKey)
        val refreshed = repository.read(1)
        assertEquals(0L, refreshed.page)
        assertFalse(refreshed.hasNext)
        assertEquals(payload, db.syncQuarantineDao().getAll().first().payload)
    }
}
