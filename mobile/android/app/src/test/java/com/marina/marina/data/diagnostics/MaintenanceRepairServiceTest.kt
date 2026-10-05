package com.marina.marina.data.diagnostics

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.google.gson.JsonParser
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.entity.EmployeeEntity
import com.marina.marina.data.local.entity.OutboxEntity
import com.marina.marina.data.local.entity.SalaryCarryOverLogEntity
import com.marina.marina.data.local.entity.SalaryCycleEntity
import com.marina.marina.data.local.entity.SalaryPaymentEntity
import com.marina.marina.data.sync.SyncOperationRunner
import com.marina.marina.domain.model.AuthUser
import com.marina.marina.domain.session.UserSessionManager
import java.io.IOException
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSystemClock

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class MaintenanceRepairServiceTest {
    private lateinit var db: AppDatabase
    private lateinit var context: Context
    private lateinit var sessions: UserSessionManager
    private lateinit var scope: CoroutineScope
    private lateinit var runner: SyncOperationRunner
    private lateinit var store: MaintenanceBackupStore
    private lateinit var service: MaintenanceRepairService
    private var employeeId = 0L

    @Before fun setup() = runBlocking {
        context = ApplicationProvider.getApplicationContext()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java).allowMainThreadQueries().build()
        sessions = UserSessionManager()
        sessions.startSession(AuthUser(id = 1, username = "test-admin", fullName = "Test", userType = "admin"))
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        runner = SyncOperationRunner(scope, Dispatchers.Unconfined)
        store = MaintenanceBackupStore(context)
        service = MaintenanceRepairService(db, sessions, runner, store)
        employeeId = db.employeesDao().insert(EmployeeEntity(name = "Test", basicSalary = 100.0,
            status = "active", localUuid = "employee-uuid"))
    }
    @After fun close() {
        scope.cancel()
        sessions.endSession()
        db.close()
        java.io.File(context.filesDir, "maintenance_backups").deleteRecursively()
    }
    private suspend fun carry(uuid: String = "carry-uuid", cache: String? = null, parent: Long = employeeId): Long =
        db.salaryCarryOverLogsDao().insert(SalaryCarryOverLogEntity(employeeId = parent, employeeUuid = cache,
            amount = 37.5, previousCycleStart = "old", previousCycleEnd = "old", newCycleStart = "new",
            newCycleEnd = "new", reason = "reason", carriedAt = 99L, localUuid = uuid, version = 7, lastModified = 88L))

    @Test fun confirmedRepairChangesOnlyCachesAndHasDurableBackupAndAudit() = runBlocking {
        carry()
        val cycleId = db.salaryCyclesDao().insert(SalaryCycleEntity(employeeId = employeeId,
            employeeUuid = "employee-uuid", cycleKey = "test", localUuid = "cycle-uuid",
            expectedAmount = 100L, actualPaid = 10L, remainingAmount = 90L))
        db.salaryPaymentsDao().insert(SalaryPaymentEntity(cycleId = cycleId, employeeUuid = "employee-uuid",
            paymentDateIso = "2026-10-05", amount = 10L, localUuid = "payment-uuid"))
        val beforeCarry = db.salaryCarryOverLogsDao().getByLocalUuid("carry-uuid")!!
        val beforePayment = db.salaryPaymentsDao().getByLocalUuid("payment-uuid")!!
        val beforeCycle = db.salaryCyclesDao().getById(cycleId)
        val plan = service.preview()
        assertEquals(2, plan.entries.size)
        assertTrue(db.autoFixRunsDao().getAllOnce().isEmpty())
        assertEquals(beforeCarry, db.salaryCarryOverLogsDao().getByLocalUuid("carry-uuid"))
        service.execute(plan.token)
        assertEquals(beforeCarry.copy(employeeUuid = "employee-uuid"), db.salaryCarryOverLogsDao().getByLocalUuid("carry-uuid"))
        assertEquals(beforePayment.copy(cycleUuid = "cycle-uuid"), db.salaryPaymentsDao().getByLocalUuid("payment-uuid"))
        assertEquals(beforeCycle, db.salaryCyclesDao().getById(cycleId))
        val run = db.autoFixRunsDao().getAllOnce().single()
        assertEquals("completed", run.status)
        assertEquals(2L, run.fixesApplied)
        assertEquals(2, db.restoreFixLogDao().getAllOnce().size)
        assertEquals(64, JsonParser.parseString(run.metadata!!).asJsonObject["sha256"].asString.length)
        val backup = JsonParser.parseString(store.file(plan.token).readText()).asJsonObject
        assertEquals("uuid-cache-preimage-v1", backup["format"].asString)
        assertTrue(backup.getAsJsonObject("plan").getAsJsonArray("entries")[0].asJsonObject["oldValue"].isJsonNull)
        db.openHelper.readableDatabase.query("SELECT COUNT(*) FROM outbox").use {
            assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
        }
        assertTrue(runCatching { service.execute(plan.token) }.isFailure)
    }

    @Test fun failedBackupPreventsEveryCacheWrite() = runBlocking {
        carry()
        val failing = MaintenanceRepairService(db, sessions, runner, object : MaintenanceBackupWriter {
            override fun write(plan: MaintenanceRepairPlan): RepairBackupReceipt = throw IOException("Synthetic full disk")
        })
        val plan = failing.preview()
        assertTrue(runCatching { failing.execute(plan.token) }.isFailure)
        assertNull(db.salaryCarryOverLogsDao().getByLocalUuid("carry-uuid")!!.employeeUuid)
        assertEquals("failed", db.autoFixRunsDao().getAllOnce().single().status)
        assertTrue(db.restoreFixLogDao().getAllOnce().isEmpty())
    }

    @Test fun changedParentInvalidatesTheApprovedPlan() = runBlocking {
        carry()
        val plan = service.preview()
        db.openHelper.writableDatabase.execSQL("UPDATE employees SET local_uuid = 'changed-parent' WHERE id = ?", arrayOf(employeeId))
        assertTrue(runCatching { service.execute(plan.token) }.isFailure)
        assertNull(db.salaryCarryOverLogsDao().getByLocalUuid("carry-uuid")!!.employeeUuid)
        assertFalse(store.file(plan.token).exists())
    }

    @Test fun existingUuidMissingParentAndUndeliveredRowsAreNotEligible() = runBlocking {
        carry("existing", "authoritative-uuid")
        carry("missing", parent = 9999)
        carry("queued")
        db.outboxDao().insert(OutboxEntity(entity = "salary_carry_over_logs", op = "update",
            localUuid = "queued", payload = "{}", clientTs = 1L))
        assertTrue(service.preview().entries.isEmpty())
        assertEquals("authoritative-uuid", db.salaryCarryOverLogsDao().getByLocalUuid("existing")!!.employeeUuid)
    }

    @Test fun ambiguousCanonicalParentUuidsAreNeverGuessed() = runBlocking {
        carry()
        db.employeesDao().insert(EmployeeEntity(name = "Other", basicSalary = 200.0, status = "active",
            localUuid = "EMPLOYEEUUID"))
        assertTrue(service.preview().entries.isEmpty())
    }

    @Test fun serviceRejectsNonAdminAndSessionChanges() = runBlocking {
        carry()
        val plan = service.preview()
        sessions.endSession()
        assertTrue(runCatching { service.execute(plan.token) }.isFailure)
        sessions.startSession(AuthUser(id = 2, username = "employee", fullName = "Test", userType = "employee"))
        assertTrue(runCatching { service.preview() }.isFailure)
        assertTrue(db.autoFixRunsDao().getAllOnce().isEmpty())
        assertNull(db.salaryCarryOverLogsDao().getByLocalUuid("carry-uuid")!!.employeeUuid)
    }

    @Test fun inFlightSyncRejectsRepairWithoutConsumingConfirmation() = runBlocking {
        carry()
        val plan = service.preview()
        val started = CompletableDeferred<Unit>()
        val finish = CompletableDeferred<Unit>()
        val sync = async {
            runner.runIfIdle(onBusy = { error("Unexpected busy") }) { started.complete(Unit); finish.await() }
        }
        started.await()
        try { assertTrue(runCatching { service.execute(plan.token) }.isFailure) }
        finally { finish.complete(Unit); sync.await() }
        assertTrue(db.autoFixRunsDao().getAllOnce().isEmpty())
        service.execute(plan.token)
        assertEquals("employee-uuid", db.salaryCarryOverLogsDao().getByLocalUuid("carry-uuid")!!.employeeUuid)
    }

    @Test fun detailAuditFailureRollsBackAllPatches() = runBlocking {
        carry()
        val plan = service.preview()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_log BEFORE INSERT ON restore_fix_log " +
            "BEGIN SELECT RAISE(ABORT, 'Synthetic audit failure'); END")
        assertTrue(runCatching { service.execute(plan.token) }.isFailure)
        assertNull(db.salaryCarryOverLogsDao().getByLocalUuid("carry-uuid")!!.employeeUuid)
        assertTrue(db.restoreFixLogDao().getAllOnce().isEmpty())
        assertEquals("failed", db.autoFixRunsDao().getAllOnce().single().status)
        assertEquals(0L, db.autoFixRunsDao().getAllOnce().single().fixesApplied)
    }

    @Test fun previewIsBoundedAndExpires() = runBlocking {
        repeat(102) { carry("bounded-$it") }
        val plan = service.preview()
        assertEquals(100, plan.entries.size)
        assertTrue(plan.hasMore)
        ShadowSystemClock.advanceBy(Duration.ofMinutes(6))
        assertTrue(runCatching { service.execute(plan.token) }.isFailure)
        assertTrue(db.autoFixRunsDao().getAllOnce().isEmpty())
    }
}
