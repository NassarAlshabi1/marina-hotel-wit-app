package com.marina.marina.data.diagnostics

import android.content.Context
import android.os.SystemClock
import android.util.AtomicFile
import androidx.room.withTransaction
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.entity.AutoFixRunEntity
import com.marina.marina.data.local.entity.RestoreFixLogEntity
import com.marina.marina.data.sync.SyncOperationRunner
import com.marina.marina.domain.model.AuthUser
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.session.UserSessionManager
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

/** Only local UUID cache fields; no amount, numeric FK, timestamp, version or outbox changes. */
data class UuidCacheRepair(
    val table: String, val field: String, val rowId: Long, val localUuid: String,
    val parentId: Long, val oldValue: String?, val newValue: String,
    val version: Long, val updatedAt: Long, val lastModified: Long
)
data class MaintenanceRepairPlan(
    val token: String, val capturedAt: Long, val actorId: Int,
    val entries: List<UuidCacheRepair>, val hasMore: Boolean
)
data class RepairBackupReceipt(val name: String, val sha256: String)
interface MaintenanceBackupWriter { fun write(plan: MaintenanceRepairPlan): RepairBackupReceipt }

/** App-private, durable preimage of changed fields, NOT a full database backup. */
@Singleton
class MaintenanceBackupStore @Inject constructor(@ApplicationContext private val context: Context) : MaintenanceBackupWriter {
    override fun write(plan: MaintenanceRepairPlan): RepairBackupReceipt {
        val bytes = GsonBuilder().serializeNulls().create().toJson(mapOf("format" to "uuid-cache-preimage-v1", "schema" to AppDatabase.SCHEMA_VERSION,
            "scope" to "local UUID cache fields only; not a full database backup", "plan" to plan)).toByteArray(Charsets.UTF_8)
        check(bytes.size <= MAX_BACKUP_BYTES) { "نسخة الأمان أكبر من الحد المسموح" }
        val file = file(plan.token)
        check(file.parentFile!!.mkdirs() || file.parentFile!!.isDirectory)
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try {
            stream.write(bytes)
            stream.fd.sync()
            atomic.finishWrite(stream)
        } catch (error: Exception) {
            atomic.failWrite(stream)
            throw error
        }
        check(atomic.readFully().contentEquals(bytes)) { "تعذر التحقق من نسخة الأمان" }
        return RepairBackupReceipt(file.name, MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) })
    }

    fun file(token: String): File {
        require(UUID.fromString(token).toString() == token)
        return File(context.filesDir, "maintenance_backups/uuid-cache-$token.json")
    }
    companion object { const val MAX_BACKUP_BYTES = 512 * 1024 }
}

@Singleton
class MaintenanceRepairService internal constructor(
    private val db: AppDatabase,
    private val sessions: UserSessionManager,
    private val runner: SyncOperationRunner,
    private val backup: MaintenanceBackupWriter
) {
    @Inject constructor(db: AppDatabase, sessions: UserSessionManager, runner: SyncOperationRunner,
        backup: MaintenanceBackupStore) : this(db, sessions, runner, backup as MaintenanceBackupWriter)

    private data class Issued(val plan: MaintenanceRepairPlan, val actor: AuthUser, val session: Long?, val elapsed: Long)
    @Volatile private var issued: Issued? = null
    private val mutableBusy = MutableStateFlow(false)
    val busy = mutableBusy.asStateFlow()

    suspend fun preview(): MaintenanceRepairPlan = withContext(Dispatchers.IO) {
        val actor = requireAdmin()
        val session = sessions.sessionStartedAt
        val candidates = db.withTransaction { candidates() }
        checkSession(actor, session)
        val plan = MaintenanceRepairPlan(UUID.randomUUID().toString(), System.currentTimeMillis(), actor.id,
            candidates.take(MAX_REPAIRS), candidates.size > MAX_REPAIRS)
        issued = Issued(plan, actor, session, SystemClock.elapsedRealtime())
        plan
    }

    suspend fun execute(token: String): String {
        requireAdmin()
        val approved = requireNotNull(issued?.takeIf { it.plan.token == token }) { "انتهت المعاينة؛ أعد الفحص" }
        return runner.runIfIdle(
            onBusy = { error("توجد مزامنة أو صيانة جارية؛ أعد المحاولة بعد انتهائها") },
            onAccepted = { mutableBusy.value = true },
            onFinished = { mutableBusy.value = false }
        ) {
            checkSession(approved.actor, approved.session)
            check(SystemClock.elapsedRealtime() - approved.elapsed <= PLAN_TTL_MS) { "انتهت المعاينة؛ أعد الفحص" }
            check(issued === approved) { "استبدلت المعاينة؛ أعد الفحص" }
            issued = null // An admitted confirmation is single-use, even if it later fails.
            check(approved.plan.entries.isNotEmpty()) { "لا توجد روابط آمنة للإصلاح" }
            val structureOk = db.openHelper.readableDatabase.query("PRAGMA quick_check(1)").use { cursor ->
                cursor.moveToFirst() && cursor.getString(0) == "ok" && !cursor.moveToNext()
            }
            check(structureOk) { "تغيرت سلامة قاعدة البيانات؛ أوقف الإصلاح واطلب مراجعة متخصصة" }
            val start = System.currentTimeMillis()
            val run = AutoFixRunEntity(runUuid = token, source = SOURCE, status = "pending",
                startedAtEpoch = start, startedAtIso = HotelTimeEngine.formatIso(start),
                metadata = Gson().toJson(mapOf("actorId" to approved.actor.id, "requested" to approved.plan.entries.size)))
            val runId = db.autoFixRunsDao().insert(run)
            try {
                db.withTransaction {
                    checkSession(approved.actor, approved.session)
                    check(SystemClock.elapsedRealtime() - approved.elapsed <= PLAN_TTL_MS) { "انتهت المعاينة؛ أعد الفحص" }
                    val fresh = candidates()
                    check(fresh.take(MAX_REPAIRS) == approved.plan.entries &&
                        (fresh.size > MAX_REPAIRS) == approved.plan.hasMore) { "تغيرت البيانات منذ المعاينة؛ لم ينفذ أي إصلاح" }
                    // The write transaction excludes concurrent local writers; the shared
                    // runner gate also excludes sync through backup verification and commit.
                    val receipt = backup.write(approved.plan)
                    currentCoroutineContext().ensureActive()
                    checkSession(approved.actor, approved.session)
                    for (entry in approved.plan.entries) {
                        currentCoroutineContext().ensureActive()
                        val changed = db.openHelper.writableDatabase.compileStatement(
                            "UPDATE ${entry.table} SET ${entry.field} = ? WHERE id = ? AND local_uuid = ? " +
                                "AND (${entry.field} IS NULL OR TRIM(${entry.field}) = '')"
                        ).use { statement ->
                            statement.bindString(1, entry.newValue)
                            statement.bindLong(2, entry.rowId)
                            statement.bindString(3, entry.localUuid)
                            statement.executeUpdateDelete()
                        }
                        check(changed == 1) { "تغير سجل أثناء الإصلاح" }
                        db.restoreFixLogDao().insert(RestoreFixLogEntity(
                            fixId = token, executedAt = start, targetTable = entry.table, targetRecordId = entry.rowId,
                            fieldName = entry.field, oldValue = entry.oldValue, newValue = entry.newValue,
                            reason = "Confirmed local parent; admin ${approved.actor.id}; backup ${receipt.name}",
                            fixType = SOURCE
                        ))
                    }
                    checkSession(approved.actor, approved.session)
                    currentCoroutineContext().ensureActive()
                    db.autoFixRunsDao().insert(run.copy(id = runId, status = "completed",
                        completedAtEpoch = System.currentTimeMillis(), fixesApplied = approved.plan.entries.size.toLong(),
                        metadata = Gson().toJson(mapOf("actorId" to approved.actor.id, "backup" to receipt.name,
                            "sha256" to receipt.sha256, "scope" to "local_uuid_cache_only"))))
                }
                "اكتمل إصلاح ${approved.plan.entries.size} حقلاً محلياً. نسخة الأمان محفوظة؛ لم تتغير الأرصدة أو طابور الرفع."
            } catch (error: Exception) {
                withContext(NonCancellable + Dispatchers.IO) {
                    try {
                        // Cancellation can race with the return AFTER SQLite committed.
                        // Never overwrite the transaction's completed audit with "failed".
                        if (db.autoFixRunsDao().getById(runId)?.status != "completed") {
                            db.autoFixRunsDao().insert(run.copy(id = runId,
                                status = if (error is CancellationException) "interrupted" else "failed",
                                completedAtEpoch = System.currentTimeMillis(),
                                errorMessage = "لم يعتمد أي إصلاح: ${error.javaClass.simpleName}"))
                        }
                    } catch (auditError: Exception) {
                        error.addSuppressed(auditError)
                    }
                }
                throw error
            }
        }
    }

    private fun requireAdmin(): AuthUser = requireNotNull(sessions.currentUser.value?.takeIf { it.isAdmin }) {
        "الصيانة متاحة لمدير النظام فقط"
    }
    private fun checkSession(actor: AuthUser, session: Long?) {
        check(requireAdmin() === actor && sessions.sessionStartedAt == session) { "تغيرت جلسة المستخدم؛ أعد الفحص" }
    }

    private fun candidates(): List<UuidCacheRepair> {
        val result = mutableListOf<UuidCacheRepair>()
        // Table/field identifiers are fixed constants, never supplied by the caller.
        for ((table, field, parent, fk) in listOf(
            listOf("salary_carry_over_logs", "employee_uuid", "employees", "employee_id"),
            listOf("salary_payments", "cycle_uuid", "salary_cycles", "cycle_id")
        )) {
            val employeeGuard = if (table == "salary_payments") """
                AND (TRIM(COALESCE(c.employee_uuid,'')) = '' OR
                    LOWER(REPLACE(TRIM(c.employee_uuid),'-','')) = LOWER(REPLACE(TRIM(p.employee_uuid),'-','')))
            """ else ""
            db.openHelper.readableDatabase.query("""
                SELECT c.id, c.local_uuid, c.$fk, c.$field, p.local_uuid, c.version, c.updated_at, c.last_modified
                FROM $table c JOIN $parent p ON p.id = c.$fk
                WHERE c.deleted_at IS NULL AND p.deleted_at IS NULL
                    AND (c.$field IS NULL OR TRIM(c.$field) = '')
                    AND LENGTH(TRIM(c.local_uuid)) BETWEEN 1 AND 128
                    AND LENGTH(TRIM(p.local_uuid)) BETWEEN 1 AND 128
                    AND NOT EXISTS (SELECT 1 FROM $parent d WHERE d.id != p.id AND
                        LOWER(REPLACE(TRIM(d.local_uuid),'-','')) = LOWER(REPLACE(TRIM(p.local_uuid),'-','')))
                    AND NOT EXISTS (SELECT 1 FROM $table d WHERE d.id != c.id AND
                        LOWER(REPLACE(TRIM(d.local_uuid),'-','')) = LOWER(REPLACE(TRIM(c.local_uuid),'-','')))
                    AND NOT EXISTS (SELECT 1 FROM outbox o WHERE o.entity = '$table'
                        AND o.local_uuid = c.local_uuid AND o.delivered_to_primary = 0)
                    AND NOT EXISTS (SELECT 1 FROM pending_sync_links s WHERE s.entity = '$table' AND s.localUuid = c.local_uuid)
                    AND NOT EXISTS (SELECT 1 FROM sync_quarantine q WHERE q.entity = '$table' AND q.recordKey = 'uuid:' || c.local_uuid)
                    $employeeGuard
                ORDER BY c.id LIMIT ${MAX_REPAIRS + 1}
            """.trimIndent()).use { cursor ->
                while (cursor.moveToNext()) result += UuidCacheRepair(table, field, cursor.getLong(0),
                    cursor.getString(1), cursor.getLong(2), if (cursor.isNull(3)) null else cursor.getString(3),
                    cursor.getString(4), cursor.getLong(5), cursor.getLong(6), cursor.getLong(7))
            }
        }
        return result.take(MAX_REPAIRS + 1)
    }

    companion object {
        const val SOURCE = "maintenance_uuid_cache"
        const val MAX_REPAIRS = 100
        private const val PLAN_TTL_MS = 5 * 60_000L
    }
}
