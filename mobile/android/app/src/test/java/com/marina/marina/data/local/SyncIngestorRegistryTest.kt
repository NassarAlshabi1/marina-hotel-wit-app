package com.marina.marina.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.local.entity.BookingEntity
import com.marina.marina.data.local.entity.BookingNightEntity
import com.marina.marina.data.local.entity.EmployeeEntity
import com.marina.marina.data.local.entity.RoomEntity
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.CloudflareWorkerApi
import com.marina.marina.data.remote.PushWireContract
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.repository.ExpensesRepositoryImpl
import com.marina.marina.data.repository.SalaryWithdrawalsRepositoryImpl
import com.marina.marina.data.local.entity.ExpenseEntity
import com.marina.marina.data.local.entity.SalaryWithdrawalEntity
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.domain.model.Expense
import com.marina.marina.data.repository.BookingNightsRepositoryImpl
import com.marina.marina.data.repository.OutboxRepository
import com.marina.marina.data.remote.WorkerPullResponse
import com.marina.marina.data.repository.SyncManager
import com.marina.marina.data.sync.SyncOperationRunner
import retrofit2.Call
import retrofit2.Response
import com.marina.marina.data.repository.SyncIngestorRegistry
import com.marina.marina.di.EncryptedSharedPreferencesManager
import com.marina.marina.domain.model.BookingNight
import com.marina.marina.domain.util.HotelTimeEngine
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.test.resetMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * عقد استيعاب السحب الكامل — شبكة انحدار لعلّة «مزامنة السحب الكامل
 * cloudflare D1 لا تعمل» (2026-09-25):
 *
 * 1. **تعلم ظلّ هوية الخادم**: server_id المحلي := id الـ AUTOINCREMENT
 *    الخادمي (عمود server_id الواصل إرثي NULL — لم يكن يُتعلم إطلاقاً).
 * 2. **ترجمة FK**: booking_local_id الواصل بفضاء جهاز المصدر يُترجم
 *    عبر booking_uuid_cache — لا يُكتب خاماً (id=5 على جهاز A ≠ جهاز B).
 * 3. **الدمج بالمفتاح الطبيعي** لليالي (booking_local_id, hotel_day_key):
 *    نسخة بـ local_uuid جديد لنفس الليلة تُدمج LWW — لا صف ثانٍ.
 * 4. **التأجيل**: ابن بلا أب محلي يذهب للمؤجلين (لا فشل، لا إدراج خام).
 * 5. **nullable**: دفعة بحجز غير محلول تُطبَّق بمؤشر NULL (عقد _fkRules).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncIngestorRegistryTest {

    private lateinit var db: AppDatabase
    private lateinit var registry: SyncIngestorRegistry

    @Suppress("UNCHECKED_CAST")
    private fun wireRecord(vararg fields: Pair<String, Any?>): Map<String, Any> =
        fields.toMap() as Map<String, Any>

    @Before
    fun openInMemoryDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        registry = newRegistry()
    }

    private fun newRegistry() = SyncIngestorRegistry(
            db = db,
            roomsDao = db.roomsDao(),
            bookingsDao = db.bookingsDao(),
            paymentsDao = db.paymentsDao(),
            expensesDao = db.expensesDao(),
            employeesDao = db.employeesDao(),
            debtsDao = db.debtsDao(),
            bookingNotesDao = db.bookingNotesDao(),
            bookingNightsDao = db.bookingNightsDao(),
            bookingPriceAdjustmentsDao = db.bookingPriceAdjustmentsDao(),
            guestInfosDao = db.guestInfosDao(),
            shiftNotesDao = db.shiftNotesDao(),
            salaryCyclesDao = db.salaryCyclesDao(),
            salaryPaymentsDao = db.salaryPaymentsDao(),
            salaryWithdrawalsDao = db.salaryWithdrawalsDao(),
            salaryCarryOverLogsDao = db.salaryCarryOverLogsDao(),
            appUsersDao = db.appUsersDao(),
            devicesDao = db.devicesDao(),
            cashTransactionsDao = db.cashTransactionsDao(),
            auditLogsDao = db.auditLogsDao(),
            paymentVoidsDao = db.paymentVoidsDao(),
            priceAdjustmentsDao = db.priceAdjustmentsDao(),
            inventoryDao = db.inventoryDao(),
            blacklistEntriesDao = db.blacklistEntriesDao()
        )

    @After
    fun closeDatabase() {
        db.close()
    }

    private fun outboxRepository(): OutboxRepository {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val encryptedPrefs = EncryptedSharedPreferencesManager(context)
        val syncPreferences = SyncPreferences(encryptedPrefs)
        val workerApi = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader,
            arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            throw AssertionError("Unexpected network call in local repository test: ${method.name}")
        } as CloudflareWorkerApi
        val syncService = CloudflareSyncService(
            api = workerApi,
            config = CloudflareConfig(context),
            preferences = syncPreferences
        )
        return OutboxRepository(
            outboxDao = db.outboxDao(),
            syncService = syncService,
            preferences = syncPreferences,
            syncIngestorRegistry = registry
        )
    }

    private fun bookingNightsRepository(): BookingNightsRepositoryImpl {
        return BookingNightsRepositoryImpl(
            db = db,
            bookingsDao = db.bookingsDao(),
            nightsDao = db.bookingNightsDao(),
            adjustmentsDao = db.bookingPriceAdjustmentsDao(),
            ledgerDao = db.hotelDayLedgerDao(),
            outboxRepository = outboxRepository()
        )
    }

    // ─── 1) تعلم ظلّ server_id من id الخادمي ───

    private fun quarantineTestRoom(uuid: String): Map<String, Any> = mapOf(
        "_entity" to "rooms", "local_uuid" to uuid, "room_number" to uuid,
        "type" to "single", "price" to 100.0, "status" to "available", "cleaning_status" to "clean"
    )

    @Test
    fun nonFinitePayloadsAreQuarantinedWithoutRollingBackHealthyRows() = runBlocking {
        val bad = quarantineTestRoom("infinite-price") + ("price" to Double.POSITIVE_INFINITY)
        val anonymous = (quarantineTestRoom("anonymous") - "local_uuid") +
            ("evidence" to listOf(Double.NaN, Float.NEGATIVE_INFINITY))
        val report = registry.ingestPage(listOf(
            quarantineTestRoom("healthy-before"), bad, anonymous, quarantineTestRoom("healthy-after")
        ))
        assertEquals(2, report.applied)
        assertEquals(2, report.failed)
        assertEquals(0, report.skipped)
        assertTrue(db.roomsDao().getByLocalUuid("healthy-before") != null)
        assertTrue(db.roomsDao().getByLocalUuid("healthy-after") != null)
        assertNull(db.roomsDao().getByLocalUuid("infinite-price"))
        val rows = db.syncQuarantineDao().getAll()
        val withUuid = rows.single { it.recordKey == "uuid:infinite-price" }
        val json = com.google.gson.JsonParser.parseString(withUuid.payload).asJsonObject
        assertEquals("Infinity", json.getAsJsonObject("price")["__sync_non_finite_number"].asString)
        val withoutUuid = rows.single { it.recordKey.startsWith("sha256:") }
        val evidence = com.google.gson.JsonParser.parseString(withoutUuid.payload).asJsonObject
            .getAsJsonArray("evidence")
        assertEquals("NaN", evidence[0].asJsonObject["__sync_non_finite_number"].asString)
        assertEquals("-Infinity", evidence[1].asJsonObject["__sync_non_finite_number"].asString)
        newRegistry().ingestPage(listOf(bad, anonymous))
        val after = db.syncQuarantineDao().getAll()
        assertEquals(rows.size, after.size)
        assertEquals(rows.map { it.recordKey }.toSet(), after.map { it.recordKey }.toSet())
        assertEquals(rows.map { it.reason }.toSet(), after.map { it.reason }.toSet())
        assertTrue(after.all { it.attempts == 2 })
    }

    @Test
    fun deferredPayloadSerializationFailureAlsoReachesQuarantine() = runBlocking {
        val report = registry.ingestPage(listOf(mapOf(
            "_entity" to "salary_withdrawals", "local_uuid" to "deferred-infinite",
            "employee_uuid" to "missing-parent", "amount" to Double.NaN,
            "withdraw_date" to "2026-10-04"
        )))
        assertEquals(1, report.failed)
        assertTrue(report.deferred.isEmpty())
        assertTrue(db.pendingSyncLinksDao().getAll().isEmpty())
        assertEquals("uuid:deferred-infinite", db.syncQuarantineDao().getAll().single().recordKey)
    }

    @Test
    fun failedQuarantineStorageFailsClosedInsteadOfSkippingEvidence() = runBlocking {
        db.openHelper.writableDatabase.execSQL(
            "CREATE TRIGGER reject_quarantine BEFORE INSERT ON sync_quarantine " +
                "BEGIN SELECT RAISE(ABORT, 'Synthetic storage failure'); END"
        )
        val result = runCatching {
            registry.ingestPage(listOf(
                quarantineTestRoom("rolled-back"),
                quarantineTestRoom("bad-price") + ("price" to Double.POSITIVE_INFINITY)
            ))
        }
        assertEquals("Unable to persist pull quarantine", result.exceptionOrNull()?.message)
        assertNull(db.roomsDao().getByLocalUuid("rolled-back"))
        assertTrue(db.syncQuarantineDao().getAll().isEmpty())
    }

    @Test
    fun malformedPullRowsAreQuarantinedInsteadOfSilentlySkipped() = runBlocking {
        val rows = listOf(
            mapOf("local_uuid" to "no-entity", "amount" to 12),
            mapOf("_entity" to "future_table", "local_uuid" to "unsupported"),
            mapOf("_entity" to "rooms", "local_uuid" to "  "),
            mapOf("_entity" to "rooms", "room_number" to "404")
        )
        val report = registry.ingestPage(rows)
        assertEquals(4, report.failed)
        assertEquals(0, report.skipped)
        assertEquals(0, report.applied)
        assertTrue(report.firstError != null)
        val quarantine = db.syncQuarantineDao().getAll()
        assertEquals(4, quarantine.size)
        assertTrue(quarantine.all { it.reason.isNotBlank() && it.payload.isNotBlank() })
        // Repeated download must not create an unbounded pile of identical evidence.
        // ✅ (2026-10-06) الأدلة تبقى صفاً واحداً لكل هوية (نفس المفتاح/الحمولة/السبب)،
        // لكن العدّاد يتصاعد مع كل دورة يفشل فيها الصف (نظير عدّاد الدورات في
        // `pull_quarantine.dart`) — وهو ما يقود الشفاء الدوري وإخلاء الأقدم.
        newRegistry().ingestPage(rows)
        val again = db.syncQuarantineDao().getAll()
        assertEquals(quarantine.size, again.size)
        assertEquals(quarantine.map { it.entity to it.recordKey }.toSet(),
            again.map { it.entity to it.recordKey }.toSet())
        assertEquals(quarantine.map { it.payload to it.reason }.toSet(),
            again.map { it.payload to it.reason }.toSet())
        assertTrue(again.all { it.attempts == 2 })
        assertEquals(quarantine.map { it.firstSeen }.toSet(), again.map { it.firstSeen }.toSet())
        assertTrue(db.pendingSyncLinksDao().getAll().isEmpty())
    }

    // ─── استنتاج الكيان بلا وسم `_entity` (نظير `_detectEntity` في Dart) ───

    /**
     * جدول بصمات الأعمدة منقول حرفياً من `_detectEntity`
     * (`cloudflare_sync_manager.dart:3798`@`ac283c6c`) — كل كيان مزامَن
     * (24) له بصمة، والترتيب داخل الدالة يمنع التعارض بين البصمات.
     */
    @Test
    fun everySyncEntityHasAnInferenceSignatureIdenticalToDart() {
        val signatures: Map<String, Map<String, Any>> = mapOf(
            "rooms" to mapOf("room_number" to "1", "price" to 1.0),
            "bookings" to mapOf("guest_name" to "g", "checkin_date" to 1L),
            "payments" to mapOf("amount" to 1.0, "payment_method" to "cash"),
            "expenses" to mapOf("expense_type" to "x", "description" to "d"),
            "employees" to mapOf("basic_salary" to 1.0, "position" to "موظف"),
            "debts" to mapOf("debt_reason" to "r", "remaining_amount" to 1.0),
            "booking_nights" to mapOf("final_rate" to 1.0, "hotel_day_key" to "k"),
            "booking_price_adjustments" to mapOf("adjustment_type" to "t", "effective_hotel_day" to "k"),
            "booking_notes" to mapOf("note_text" to "n", "alert_type" to "a"),
            "guest_infos" to mapOf("guest_name" to "g", "id_number" to "1"),
            "shift_notes" to mapOf("shift_date" to "d", "is_read" to 0),
            "cash_transactions" to mapOf("transaction_type" to "t", "transaction_time" to 1L),
            "salary_cycles" to mapOf("cycle_key" to "k", "expected_amount" to 1.0),
            "salary_payments" to mapOf("payment_date_iso" to "d", "cycle_id" to 1L),
            "salary_withdrawals" to mapOf("withdrawal_type" to "w", "amount" to 1.0),
            "salary_carry_over_logs" to mapOf("previous_cycle_start" to "a", "new_cycle_start" to "b"),
            "price_adjustments" to mapOf("target_type" to "t", "target_uuid" to "u"),
            "audit_logs" to mapOf("operation_type" to "o", "entity_type" to "e"),
            "payment_voids" to mapOf("void_reason" to "r", "voided_by" to "u"),
            "inventory_items" to mapOf("minimum_quantity" to 1.0),
            "inventory_transactions" to mapOf("movement_type" to "adjustment", "balance_after" to 1.0),
            "devices" to mapOf("device_name" to "d"),
            "blacklist" to mapOf("reported_by" to "police"),
            "app_users" to mapOf("username" to "u", "credentials_version" to 1)
        )
        // تغطية كاملة: لا كيان مزامَن بلا بصمة (وإلا سقط سجله القديم في العزل).
        assertEquals(SyncIngestorRegistry.SYNC_ENTITY_TABLES.keys, signatures.keys)
        for ((expected, marker) in signatures) {
            assertEquals(
                "استنتاج خاطئ لبصمة $expected",
                expected, SyncIngestorRegistry.inferEntityFromRecord(marker)
            )
        }
        // سجل بلا وسم وبلا بصمة معروفة يُرجع null (لا تخمين).
        assertNull(SyncIngestorRegistry.inferEntityFromRecord(mapOf<String, Any>("future_column" to 1)))
    }

    /** الوسم الصريح يسبق البصمة دائماً — حتى لو تعارضا (نفس ترتيب Dart). */
    @Test
    fun explicitEntityTagWinsOverColumnSignature() {
        val conflicting: Map<String, Any> = mapOf(
            "_entity" to "rooms", "amount" to 5.0, "payment_method" to "cash"
        )
        assertEquals("rooms", SyncIngestorRegistry.resolveEntity(conflicting))
        assertEquals("payments", SyncIngestorRegistry.inferEntityFromRecord(conflicting))

        // وسم فارغ/مسافات = غياب → البصمة.
        val blankTag: Map<String, Any> = mapOf(
            "_entity" to "   ", "amount" to 5.0, "payment_method" to "cash"
        )
        assertEquals("payments", SyncIngestorRegistry.resolveEntity(blankTag))
    }

    /**
     * سجل بلا `_entity` (نشر Worker أقدم) لكن ببصمة سليمة يُطبَّق فعلاً —
     * قبل هذا كان يُعزل `missing_entity` فيبقى صفٌّ سليم خارج القاعدة.
     */
    @Test
    fun recordWithoutEntityTagIsRoutedByItsColumnSignature() = runBlocking {
        val untagged = mapOf<String, Any>(
            "local_uuid" to "untagged-room",
            "room_number" to "UT-1",
            "type" to "single",
            "price" to 175.0,
            "status" to "available",
            "cleaning_status" to "clean",
            "last_modified" to 400L
        )
        val report = registry.ingestPage(listOf(untagged))
        assertEquals(1, report.applied)
        assertEquals(0, report.failed)
        assertTrue(db.syncQuarantineDao().getAll().isEmpty())
        assertEquals("UT-1", db.roomsDao().getByLocalUuid("untagged-room")!!.roomNumber)
    }

    /**
     * فرق مقصود عن Dart: هو يُسقط السجل مجهول الهوية صامتاً، ونحن نُعزله
     * بحمولته (`missing_entity`) فيبقى قابلاً للاسترجاع بعد تحديث التطبيق.
     */
    @Test
    fun untaggedRecordWithUnknownSignatureStaysQuarantinedAsMissingEntity() = runBlocking {
        val orphan = mapOf<String, Any>("local_uuid" to "orphan-row", "future_column" to 1)
        val report = registry.ingestPage(listOf(orphan))
        assertEquals(1, report.failed)
        val row = db.syncQuarantineDao().getAll().single()
        assertEquals("unknown", row.entity)
        assertEquals("uuid:orphan-row", row.recordKey)
        assertEquals("missing_entity", row.reason)
        assertTrue(row.payload.contains("orphan-row"))
    }

    @Test
    fun repairedRecordLeavesQuarantineAndOlderLocalWinnerIsNotQuarantined() = runBlocking {
        val valid = mapOf<String, Any>(
            "_entity" to "rooms", "local_uuid" to "quarantined-room", "room_number" to "Q1",
            "type" to "single", "price" to 100.0, "status" to "available", "cleaning_status" to "clean",
            "last_modified" to 200L
        )
        assertEquals(1, registry.ingestPage(listOf(valid + ("price" to "not-a-number"))).failed)
        assertEquals(1, db.syncQuarantineDao().getAll().size)
        assertEquals(1, registry.ingestPage(listOf(valid)).applied)
        assertTrue(db.syncQuarantineDao().getAll().isEmpty())
        assertEquals(1, registry.ingestPage(listOf(valid + ("last_modified" to 100L))).skipped)
        assertTrue(db.syncQuarantineDao().getAll().isEmpty())
        assertEquals(100.0, db.roomsDao().getByLocalUuid("quarantined-room")!!.price, 0.0)
    }

    @Test
    fun quarantineSurvivesDatabaseCloseAndReopen() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "pull-quarantine-restart.db"
        context.deleteDatabase(name)
        db.close()
        fun open() = Room.databaseBuilder(context, AppDatabase::class.java, name)
            .allowMainThreadQueries().build()
        db = open()
        try {
            newRegistry().ingestPage(listOf(mapOf("_entity" to "unknown_table", "local_uuid" to "kept")))
            val saved = db.syncQuarantineDao().getAll().single()
            db.close()
            db = open()
            assertEquals(saved, db.syncQuarantineDao().getAll().single())
        } finally {
            db.close()
            context.deleteDatabase(name)
        }
    }

    @Test
    fun legacySalaryUuidCachesUseStoredLocalLinksNotIncomingNumericIds() = runBlocking {
        val employeeId = db.employeesDao().insert(EmployeeEntity(
            name = "cache-parent", basicSalary = 100.0, status = "active", localUuid = "cache-employee"
        ))
        val cycleId = db.salaryCyclesDao().insert(com.marina.marina.data.local.entity.SalaryCycleEntity(
            employeeId = employeeId, employeeUuid = "cache-employee", cycleKey = "cache-cycle",
            localUuid = "cache-cycle"
        ))
        db.salaryPaymentsDao().insert(com.marina.marina.data.local.entity.SalaryPaymentEntity(
            cycleId = cycleId, cycleUuid = null, paymentDateIso = "2026-10-04", localUuid = "legacy-payment"
        ))
        db.salaryCarryOverLogsDao().insert(com.marina.marina.data.local.entity.SalaryCarryOverLogEntity(
            employeeId = employeeId, employeeUuid = null, amount = 15.0,
            previousCycleStart = "old", previousCycleEnd = "old", newCycleStart = "new", newCycleEnd = "new",
            reason = "carry", carriedAt = 1L, localUuid = "legacy-carry"
        ))
        val report = registry.ingestPage(listOf(
            mapOf("_entity" to "salary_payments", "local_uuid" to "legacy-payment", "cycle_id" to 999999L,
                "amount" to 25L, "payment_date_iso" to "2026-10-04", "last_modified" to 2L),
            mapOf("_entity" to "salary_carry_over_logs", "local_uuid" to "legacy-carry", "employee_id" to 999999L,
                "amount" to 15.0, "previous_cycle_start" to "old", "previous_cycle_end" to "old",
                "new_cycle_start" to "new", "new_cycle_end" to "new", "reason" to "carry",
                "carried_at" to 1L, "last_modified" to 2L)
        ))
        assertEquals(2, report.applied)
        val payment = db.salaryPaymentsDao().getByLocalUuid("legacy-payment")!!
        assertEquals(cycleId, payment.cycleId)
        assertEquals("cache-cycle", payment.cycleUuid)
        assertEquals(25L, payment.amount)
        val carry = db.salaryCarryOverLogsDao().getByLocalUuid("legacy-carry")!!
        assertEquals(employeeId, carry.employeeId)
        assertEquals("cache-employee", carry.employeeUuid)
        assertEquals(15.0, carry.amount, 0.0)
    }

    private fun auditPage(
        cursor: String = "123", more: Boolean = false, repair: Boolean? = null,
        normalization: com.marina.marina.data.remote.WorkerNormalization? = null
    ) = WorkerPullResponse(
        changes = emptyList(), cursor = cursor, epoch = "audit", hasMore = more,
        remaining = null, errors = emptyList(), serverTime = null,
        repairPending = repair, normalization = normalization
    )

    private suspend fun assertAuditPull(
        pages: List<WorkerPullResponse>, expectedCalls: Int, expectedCursor: Long,
        success: Boolean, fullReplay: Boolean = false, normalized: Boolean = false
    ) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = SyncPreferences(EncryptedSharedPreferencesManager(context))
        prefs.saveAuthToken("test-worker-token")
        prefs.saveLastPullCursor(123L)
        prefs.saveLastPullTs(0L)
        prefs.saveSyncEpoch("audit")
        prefs.setTombstoneSweepDone(true) // مسح الحذفيات له اختبار مخصص؛ لا يغيّر عدّ نداءات هذه الحالات.
        prefs.setFullReplayPending(fullReplay)
        prefs.setTimestampNormalizationDone(false)
        var calls = 0
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            check(method.name == "pull")
            val response = pages[minOf(calls++, pages.lastIndex)]
            check(calls <= 5) { "Unbounded repair retries" }
            Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, call, _ ->
                check(call.name == "execute")
                Response.success(response)
            } as Call<*>
        } as CloudflareWorkerApi
        val service = CloudflareSyncService(api, CloudflareConfig(context), prefs)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val manager = SyncManager(OutboxRepository(db.outboxDao(), service, prefs, registry),
                service, prefs, registry, SyncOperationRunner(scope, Dispatchers.Unconfined), derivedRefresh())
            assertEquals(if (success) 0 else -1, manager.pullOnly())
            assertEquals(expectedCalls, calls)
            assertEquals(expectedCursor, prefs.getLastPullCursor())
            assertEquals(normalized, prefs.isTimestampNormalizationDone())
            assertEquals(success, prefs.getLastPullTs() > 0L)
        } finally {
            scope.coroutineContext[kotlinx.coroutines.Job]!!.cancelAndJoin()
        }
    }

    @Test
    fun deltaRetriesAcknowledgedRepairWithoutAdvancingCheckpointPrematurely() = runBlocking {
        assertAuditPull(listOf(auditPage(more = true, repair = true), auditPage(cursor = "456")),
            expectedCalls = 2, expectedCursor = 456L, success = true)
    }

    @Test
    fun deltaStillRejectsUnacknowledgedPaginationStall() = runBlocking {
        assertAuditPull(listOf(auditPage(more = true)),
            expectedCalls = 1, expectedCursor = 123L, success = false)
    }

    @Test
    fun deltaRepairRetriesAreBoundedAndDoNotStampSuccess() = runBlocking {
        assertAuditPull(listOf(auditPage(more = true, repair = true)),
            expectedCalls = 4, expectedCursor = 123L, success = false)
    }

    @Test
    fun fullReplayDoesNotMarkUnacknowledgedNormalizationDone() = runBlocking {
        assertAuditPull(listOf(auditPage()), expectedCalls = 1, expectedCursor = 123L,
            success = true, fullReplay = true, normalized = false)
    }

    @Test
    fun fullReplayMarksExplicitlyCompletedNormalizationDone() = runBlocking {
        assertAuditPull(listOf(auditPage(normalization =
            com.marina.marina.data.remote.WorkerNormalization(complete = true, remaining = 0.0))),
            expectedCalls = 1, expectedCursor = 123L, success = true, fullReplay = true, normalized = true)
    }

    @Test
    fun fullReplayDoesNotMarkPartialNormalizationDone() = runBlocking {
        assertAuditPull(listOf(auditPage(normalization =
            com.marina.marina.data.remote.WorkerNormalization(complete = false, remaining = 10.0))),
            expectedCalls = 1, expectedCursor = 123L, success = true, fullReplay = true, normalized = false)
    }

    @Test
    fun dashboardPullUsesSavedDeltaCursorAcrossPagesAndRepeatedClicksWithoutPush() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = SyncPreferences(EncryptedSharedPreferencesManager(context))
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("delta-test-device")
        prefs.saveLastPullCursor(123L)
        prefs.saveSyncEpoch("stable-delta")
        prefs.setFullReplayPending(false)
        prefs.setTombstoneSweepDone(true) // مسح الحذفيات له اختبار مخصص؛ لا يغيّر عدّ نداءات هذه الحالات.
        val requests = mutableListOf<List<Any?>>()
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, args ->
            check(method.name == "pull") { "Dashboard must not call ${method.name}" }
            requests.add(args!!.toList())
            val index = requests.size
            check(index <= 3) { "Unexpected extra pull" }
            val response = WorkerPullResponse(
                changes = if (index <= 2) listOf(mapOf(
                    "_entity" to "rooms", "local_uuid" to "delta-room", "room_number" to "DELTA-101",
                    "type" to "single", "price" to if (index == 1) 100.0 else 150.0,
                    "status" to "available", "cleaning_status" to "clean",
                    "last_modified" to if (index == 1) 456L else 789L
                )) else emptyList(),
                cursor = if (index == 1) "456" else "789", epoch = "stable-delta",
                hasMore = index == 1, remaining = null, errors = emptyList(), serverTime = null
            )
            Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, call, _ ->
                check(call.name == "execute")
                Response.success(response)
            } as Call<*>
        } as CloudflareWorkerApi
        val service = CloudflareSyncService(api, CloudflareConfig(context), prefs)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val manager = SyncManager(OutboxRepository(db.outboxDao(), service, prefs, registry),
                service, prefs, registry, SyncOperationRunner(scope, Dispatchers.Unconfined), derivedRefresh())
            val first = com.marina.marina.presentation.dashboard.runDashboardDirectionalSync(manager, false)
            assertEquals(com.marina.marina.presentation.dashboard.DashboardEvent.SyncCompleted(0, 2), first)
            assertEquals(789L, prefs.getLastPullCursor())
            val second = com.marina.marina.presentation.dashboard.runDashboardDirectionalSync(manager, false)
            assertEquals(com.marina.marina.presentation.dashboard.DashboardEvent.SyncCompleted(0, 0), second)
            assertEquals(listOf(123L, 456L, 789L), requests.map { it[0] })
            requests.forEach { request ->
                assertEquals(CloudflareConfig.DELTA_PULL_BATCH_SIZE, request[1])
                assertEquals("delta-test-device", request[2])
                assertNull(request[3]) // no full-pull remaining scan
                assertNull(request[4]) // no timestamp normalization
            }
            assertEquals(0, manager.pullAutomaticallyIfDue())
            assertEquals(3, requests.size) // Shared manual success also suppresses an automatic pull.
            assertEquals(789L, prefs.getLastPullCursor())
            assertTrue(!prefs.isFullReplayPending())
            assertEquals(1, db.roomsDao().getAllOnce().size)
            assertEquals(150.0, db.roomsDao().getByLocalUuid("delta-room")!!.price, 0.0)
            assertTrue(db.outboxDao().getPendingPrimary().first().isEmpty())
        } finally {
            scope.coroutineContext[kotlinx.coroutines.Job]!!.cancelAndJoin()
        }
    }

    /**
     * ✅ (2026-10-06) **العقد المصحَّح** (كان `quarantinedPullDoesNotAdvanceSavedCursor`):
     * الصفحة نفسها سليمة (شبكة/HTTP/JSON)، والصف غير القابل للتطبيق يُعزل
     * بحمولته — **والمؤشر يتقدم**. تجميد المؤشر كان يعطي «جهازاً متوقفاً
     * نهائياً» لخطأ صفٍّ واحد، وهو العطل المُبلَّغ («الدلتا لا تسحب الجداول ولا
     * الحقول»)؛ ونصّ `pull_quarantine.dart` (٢٠٢٦-٠٩-١٥) يصف القاعدة:
     * «المؤشر يتقدم في نفس الدورة طالما الصفحات نفسها سليمة».
     */
    @Test
    fun quarantinedPullAdvancesSavedCursorAndStaysRecoverable() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = SyncPreferences(EncryptedSharedPreferencesManager(context))
        prefs.saveAuthToken("test-worker-token")
        prefs.saveLastPullCursor(123L)
        prefs.saveSyncEpoch("stable")
        prefs.setFullReplayPending(false)
        prefs.setTombstoneSweepDone(true) // مسح الحذفيات له اختبار مخصص؛ لا يغيّر عدّ نداءات هذه الحالات.
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            check(method.name == "pull")
            Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, callMethod, _ ->
                check(callMethod.name == "execute")
                Response.success(WorkerPullResponse(
                    changes = listOf(mapOf("_entity" to "unsupported", "local_uuid" to "preserved")),
                    cursor = "456", epoch = "stable", hasMore = false,
                    remaining = null, errors = emptyList(), serverTime = null
                ))
            } as Call<*>
        } as CloudflareWorkerApi
        val service = CloudflareSyncService(api, CloudflareConfig(context), prefs)
        val manager = SyncManager(OutboxRepository(db.outboxDao(), service, prefs, registry),
            service, prefs, registry,
            SyncOperationRunner(CoroutineScope(SupervisorJob() + Dispatchers.IO), Dispatchers.Unconfined), derivedRefresh())
        // لا فشل دورة: الصف عُزل وحده، والمؤشر تقدّم إلى نهاية النافذة.
        assertTrue(manager.pullOnly() >= 0)
        assertFalse(manager.syncState.value.isError)
        assertEquals(456L, prefs.getLastPullCursor())
        val row = db.syncQuarantineDao().getAll().single()
        assertEquals("unsupported", row.entity)
        assertEquals("uuid:preserved", row.recordKey)
        assertTrue(row.firstSeen > 0L && row.attempts >= 1)
    }

    @Test
    fun ingestLearnsServerIdShadowFromD1AutoincrementId() = runBlocking {
        val applied = registry.ingest(
            mapOf(
                "_entity" to "rooms",
                "id" to 55,
                "local_uuid" to "room-uuid-1",
                "room_number" to "101",
                "type" to "single",
                "price" to 100.0,
                "status" to "available",
                "cleaning_status" to "clean",
                "requires_maintenance" to false,
                "last_modified" to 100L
            )
        )
        assertTrue(applied)
        val room = db.roomsDao().getByLocalUuid("room-uuid-1")!!
        // serverId عمود Int — القيمة 55 هي جوهر العقد (ظلّ id الخادمي).
        assertEquals(55L, room.serverId?.toLong())
    }

    @Test
    fun integerBooleanColumnsFromD1AreNormalizedBeforeDeserialization() = runBlocking {
        val report = registry.ingestPage(
            listOf(
                mapOf(
                    "_entity" to "rooms",
                    "id" to 56,
                    "local_uuid" to "room-integer-boolean",
                    "room_number" to "102",
                    "type" to "single",
                    "price" to 100.0,
                    "status" to "available",
                    "cleaning_status" to "clean",
                    "requires_maintenance" to 1,
                    "last_modified" to 101L
                )
            )
        )

        assertEquals(1, report.applied)
        assertTrue(db.roomsDao().getByLocalUuid("room-integer-boolean")!!.requiresMaintenance)
    }

    @Test
    fun pollutedScientificVersionValuesAreSanitizedBeforeDeserialization() = runBlocking {
        fun roomRecord(id: Int, uuid: String, version: Any): Map<String, Any> = mapOf(
            "_entity" to "rooms",
            "id" to id,
            "local_uuid" to uuid,
            "room_number" to id.toString(),
            "type" to "single",
            "price" to 100.0,
            "status" to "available",
            "cleaning_status" to "clean",
            "version" to version,
            "last_modified" to id.toLong()
        )

        val report = registry.ingestPage(
            listOf(
                roomRecord(57, "room-polluted-double", 1_000_000_000_003.0),
                roomRecord(58, "room-polluted-exponent-string", "1.000000000003E12"),
                roomRecord(59, "room-valid-version", 37.0)
            )
        )

        assertEquals(3, report.applied)
        assertEquals(1, db.roomsDao().getByLocalUuid("room-polluted-double")!!.version)
        assertEquals(1, db.roomsDao().getByLocalUuid("room-polluted-exponent-string")!!.version)
        assertEquals(37, db.roomsDao().getByLocalUuid("room-valid-version")!!.version)
    }

    @Test
    fun salaryWithdrawalPullNormalizesIsoDateAndMissingEmployeeSnapshot() = runBlocking {
        val employeeUuid = "employee-withdrawal-date"
        val employeeId = db.employeesDao().insert(
            EmployeeEntity(
                name = "موظف اختبار",
                basicSalary = 300_000.0,
                status = "active",
                localUuid = employeeUuid
            )
        )

        val report = registry.ingestPage(
            listOf(
                mapOf(
                    "_entity" to "salary_withdrawals",
                    "id" to 561,
                    "local_uuid" to "withdrawal-iso-date",
                    "employee_id" to employeeId,
                    "employee_uuid" to employeeUuid,
                    "amount" to 2500.0,
                    "withdraw_date" to "2026-05-04",
                    "withdrawal_type" to "سلفة",
                    "last_modified" to 200L
                )
            )
        )

        assertEquals(1, report.applied)
        val withdrawal = db.salaryWithdrawalsDao().getByLocalUuid("withdrawal-iso-date")!!
        assertEquals(HotelTimeEngine.parseDate("2026-05-04"), withdrawal.withdrawDate)
        assertEquals("موظف اختبار", withdrawal.employeeName)
    }

    @Test
    fun salaryRelationsResolveStableUuidsInsteadOfRemoteNumericIds() = runBlocking {
        val employeeUuid = "employee-parent-uuid"
        val employeeId = db.employeesDao().insert(
            EmployeeEntity(
                name = "موظف الرواتب",
                basicSalary = 300_000.0,
                status = "active",
                localUuid = employeeUuid
            )
        )
        val cycleUuid = "salary-cycle-parent-uuid"
        val report = registry.ingestPage(
            listOf(
                mapOf(
                    "_entity" to "salary_cycles",
                    "id" to 801,
                    "local_uuid" to cycleUuid,
                    "employee_id" to 777,
                    "employee_uuid" to employeeUuid,
                    "cycle_key" to "2026-10",
                    "expected_amount" to 300_000L,
                    "actual_paid" to 0L,
                    "remaining_amount" to 300_000L,
                    "status" to "draft",
                    "last_modified" to 801L
                ),
                mapOf(
                    "_entity" to "salary_payments",
                    "id" to 802,
                    "local_uuid" to "salary-payment-parent-uuid",
                    "cycle_id" to 999,
                    "cycle_uuid" to cycleUuid,
                    "employee_uuid" to employeeUuid,
                    "amount" to 25_000L,
                    "payment_date_iso" to "2026-10-03",
                    "hotel_day_key" to "2026-10-03",
                    "last_modified" to 802L
                ),
                mapOf(
                    "_entity" to "salary_carry_over_logs",
                    "id" to 803,
                    "local_uuid" to "salary-carry-over-parent-uuid",
                    "employee_id" to 888,
                    "employee_uuid" to employeeUuid,
                    "amount" to 12_500.0,
                    "previous_cycle_start" to "2026-09-01",
                    "previous_cycle_end" to "2026-09-30",
                    "new_cycle_start" to "2026-10-01",
                    "new_cycle_end" to "2026-10-31",
                    "reason" to "unpaid balance",
                    "carried_at" to 1_791_000_000L,
                    "last_modified" to 803L
                )
            )
        )

        assertEquals(3, report.applied)
        val cycle = db.salaryCyclesDao().getByLocalUuid(cycleUuid)!!
        assertEquals(employeeId, cycle.employeeId)
        assertEquals(employeeUuid, cycle.employeeUuid)
        val payment = db.salaryPaymentsDao().getByLocalUuid("salary-payment-parent-uuid")!!
        assertEquals(cycle.id, payment.cycleId)
        assertEquals(cycleUuid, payment.cycleUuid)
        assertEquals(employeeUuid, payment.employeeUuid)
        val carryOver = db.salaryCarryOverLogsDao().getByLocalUuid("salary-carry-over-parent-uuid")!!
        assertEquals(employeeId, carryOver.employeeId)
        assertEquals(employeeUuid, carryOver.employeeUuid)
    }

    @Test
    fun unresolvedUuidNeverFallsBackToServerIdAndAmbiguousLegacyIdsAreDeferred() = runBlocking {
        db.employeesDao().insert(
            EmployeeEntity(
                name = "موظف ظل",
                basicSalary = 100_000.0,
                status = "active",
                localUuid = "employee-server-shadow-one",
                serverId = 77
            )
        )
        db.employeesDao().insert(
            EmployeeEntity(
                name = "موظف ظل آخر",
                basicSalary = 100_000.0,
                status = "active",
                localUuid = "employee-server-shadow-two",
                serverId = 88
            )
        )
        db.employeesDao().insert(
            EmployeeEntity(
                name = "موظف ظل مكرر",
                basicSalary = 100_000.0,
                status = "active",
                localUuid = "employee-server-shadow-three",
                serverId = 88
            )
        )

        val report = registry.ingestPage(
            listOf(
                mapOf(
                    "_entity" to "salary_withdrawals",
                    "id" to 811,
                    "local_uuid" to "withdrawal-unresolved-uuid",
                    "employee_id" to 77,
                    "employee_uuid" to "not-installed-employee-uuid",
                    "employee_name" to "Remote",
                    "amount" to 100.0,
                    "withdraw_date" to "2026-10-03",
                    "withdrawal_type" to "سحب راتب",
                    "last_modified" to 811L
                ),
                mapOf(
                    "_entity" to "salary_withdrawals",
                    "id" to 812,
                    "local_uuid" to "withdrawal-ambiguous-server-id",
                    "employee_id" to 88,
                    "employee_name" to "Remote",
                    "amount" to 100.0,
                    "withdraw_date" to "2026-10-03",
                    "withdrawal_type" to "سحب راتب",
                    "last_modified" to 812L
                )
            )
        )

        assertEquals(0, report.applied)
        assertEquals(2, report.deferred.size)
        assertNull(db.salaryWithdrawalsDao().getByLocalUuid("withdrawal-unresolved-uuid"))
        assertNull(db.salaryWithdrawalsDao().getByLocalUuid("withdrawal-ambiguous-server-id"))
    }

    @Test
    fun expenseNullLinkPreservesExistingRelationUnlessClearFlagIsPersisted() = runBlocking {
        val employeeUuid = "expense-linked-employee-uuid"
        val employeeId = db.employeesDao().insert(
            EmployeeEntity(
                name = "موظف المصروف",
                basicSalary = 200_000.0,
                status = "active",
                localUuid = employeeUuid
            )
        )
        val expenseUuid = "salary-expense-link-uuid"
        assertTrue(
            registry.ingest(
                mapOf(
                    "_entity" to "expenses",
                    "id" to 821,
                    "local_uuid" to expenseUuid,
                    "expense_type" to "سلفة",
                    "related_id" to 987,
                    "employee_uuid" to employeeUuid,
                    "description" to "سلفة شهرية",
                    "amount" to 5_000.0,
                    "date" to "2026-10-03",
                    "last_modified" to 821L
                )
            )
        )
        assertEquals(employeeId, db.expensesDao().getByLocalUuid(expenseUuid)!!.relatedId)

        val ordinaryNullSnapshot = registry.ingestPage(
            listOf(
                wireRecord(
                    "_entity" to "expenses",
                    "id" to 821,
                    "local_uuid" to expenseUuid,
                    "expense_type" to "سلفة",
                    "related_id" to null,
                    "employee_uuid" to null,
                    "employee_link_cleared" to 0,
                    "description" to "سلفة معدلة",
                    "amount" to 5_500.0,
                    "date" to "2026-10-03",
                    "last_modified" to 822L
                )
            )
        )
        assertEquals(1, ordinaryNullSnapshot.applied)
        val retained = db.expensesDao().getByLocalUuid(expenseUuid)!!
        assertEquals(employeeId, retained.relatedId)
        assertEquals(employeeUuid, retained.employeeUuid)

        val explicitClear = registry.ingestPage(
            listOf(
                wireRecord(
                    "_entity" to "expenses",
                    "id" to 821,
                    "local_uuid" to expenseUuid,
                    "expense_type" to "سلفة",
                    "related_id" to null,
                    "employee_uuid" to null,
                    "employee_link_cleared" to 1,
                    "description" to "رُفع الارتباط صراحة",
                    "amount" to 5_500.0,
                    "date" to "2026-10-03",
                    "last_modified" to 823L
                )
            )
        )
        assertEquals(1, explicitClear.applied)
        val unlinked = db.expensesDao().getByLocalUuid(expenseUuid)!!
        assertNull(unlinked.relatedId)
        assertNull(unlinked.employeeUuid)
    }

    // ─── 2) ترجمة FK عبر uuid-cache — لا id خام من جهاز بعيد ───

    @Test
    fun bookingNightForeignPointerTranslatesViaUuidCache() = runBlocking {
        val bookingId = db.bookingsDao().insert(
            BookingEntity(
                roomNumber = "101",
                guestName = "ضاحر اختبار",
                guestPhone = "777",
                guestNationality = "يمني",
                checkinDate = "2026-09-25",
                status = "مؤكد",
                localUuid = "booking-uuid-101"
            )
        )
        val report = registry.ingestPage(
            listOf(
                mapOf(
                    "_entity" to "booking_nights",
                    "id" to 900,
                    "local_uuid" to "night-remote-1",
                    // فضاء جهاز المصدر — يجب ألا يُكتب خاماً أبداً.
                    "booking_local_id" to 999,
                    "booking_uuid_cache" to "booking-uuid-101",
                    "hotel_day_key" to "2026-09-25",
                    "night_start" to "2026-09-25 14:00",
                    "night_end" to "2026-09-26 12:00",
                    "nightly_rate" to 120.0,
                    "last_modified" to 200L
                )
            )
        )
        assertEquals(1, report.applied)
        assertTrue(report.deferred.isEmpty())
        val night = db.bookingNightsDao().getByLocalUuid("night-remote-1")!!
        assertEquals(bookingId, night.bookingLocalId)
    }

    @Test
    fun bookingNightPullUsesLegacyServerBookingIdOnlyWhenUuidIsMissing() = runBlocking {
        val bookingId = db.bookingsDao().insert(
            BookingEntity(
                serverBookingId = 77,
                roomNumber = "N-102",
                guestName = "ضيف قديم",
                guestPhone = "701",
                guestNationality = "يمني",
                checkinDate = "2026-10-02",
                status = "مؤكد",
                localUuid = "booking-night-legacy-parent"
            )
        )

        val report = registry.ingestPage(
            listOf(
                mapOf(
                    "_entity" to "booking_nights",
                    "id" to 904,
                    "local_uuid" to "night-legacy-parent-id",
                    "booking_local_id" to 999,
                    "server_booking_id" to 77,
                    "hotel_day_key" to "2026-10-02",
                    "night_start" to "2026-10-02 14:00",
                    "night_end" to "2026-10-03 12:00",
                    "last_modified" to 150L
                )
            )
        )

        assertEquals(1, report.applied)
        assertTrue(report.deferred.isEmpty())
        assertEquals(
            bookingId,
            db.bookingNightsDao().getByLocalUuid("night-legacy-parent-id")!!.bookingLocalId
        )
    }

    @Test
    fun bookingNightWritesIncludeParentUuidAndReplaceWithOutboxUpdatesAndTombstones() = runBlocking {
        val bookingUuid = "booking-night-parent-uuid"
        val bookingId = db.bookingsDao().insert(
            BookingEntity(
                roomNumber = "N-101",
                guestName = "ضيف ليالي",
                guestPhone = "700",
                guestNationality = "يمني",
                checkinDate = "2026-10-01",
                status = "مؤكد",
                localUuid = bookingUuid
            )
        )
        val repository = bookingNightsRepository()

        repository.replaceNights(
            bookingId,
            listOf(
                BookingNight(
                    hotelDayKey = "2026-10-01",
                    nightStart = "2026-10-01 14:00",
                    nightEnd = "2026-10-02 12:00",
                    nightlyRate = 120.0
                ),
                BookingNight(
                    hotelDayKey = "2026-10-02",
                    nightStart = "2026-10-02 14:00",
                    nightEnd = "2026-10-03 12:00",
                    nightlyRate = 125.0
                )
            )
        )

        val initialNights = db.bookingNightsDao().getByBooking(bookingId)
        assertEquals(2, initialNights.size)
        assertTrue(initialNights.all { it.bookingUuidCache == bookingUuid })
        val stableNightUuid = initialNights.single { it.hotelDayKey == "2026-10-01" }.localUuid
        val firstPush = db.outboxDao().getPendingPrimary().first()
            .map { PushWireContract.buildOperation(it, "test-device") }
            .first { it.operation == "create" }
        assertEquals("booking_nights", firstPush.entity)
        assertEquals(bookingUuid, firstPush.data["booking_uuid_cache"])

        // Replacing a night with the same natural key updates the same UUID;
        // omitting another day emits a delete instead of removing it locally.
        repository.replaceNights(
            bookingId,
            listOf(
                BookingNight(
                    hotelDayKey = "2026-10-01",
                    nightStart = "2026-10-01 14:00",
                    nightEnd = "2026-10-02 12:00",
                    nightlyRate = 175.0
                )
            )
        )
        val activeNight = db.bookingNightsDao().getByBooking(bookingId).single()
        assertEquals(stableNightUuid, activeNight.localUuid)
        assertEquals(175.0, activeNight.nightlyRate, 0.001)
        val queuedOperations = db.outboxDao().getPendingPrimary().first()
            .map { PushWireContract.buildOperation(it, "test-device") }
        assertTrue(queuedOperations.any { it.operation == "update" && it.data["local_uuid"] == stableNightUuid })
        assertTrue(queuedOperations.any { it.operation == "delete" })

        repository.replaceNights(bookingId, emptyList())
        val deletedNight = db.bookingNightsDao().getByLocalUuid(stableNightUuid)!!
        assertTrue(deletedNight.deletedAt != null)
        val afterDelete = db.outboxDao().getPendingPrimary().first()
            .map { PushWireContract.buildOperation(it, "test-device") }
        assertTrue(afterDelete.any { it.operation == "delete" && it.data["local_uuid"] == stableNightUuid })
    }

    // ─── 3) المفتاح الطبيعي: نسخة مكررة تُدمج لا تُكرر ───

    @Test
    fun bookingNightDuplicateNaturalKeyMergesInsteadOfInserting() = runBlocking {
        val bookingId = db.bookingsDao().insert(
            BookingEntity(
                roomNumber = "102",
                guestName = "ضاحر اختبار",
                guestPhone = "778",
                guestNationality = "يمني",
                checkinDate = "2026-09-26",
                status = "مؤكد",
                localUuid = "booking-uuid-102"
            )
        )
        val first = mapOf(
            "_entity" to "booking_nights",
            "id" to 901,
            "local_uuid" to "night-local-copy",
            "booking_local_id" to 888,
            "booking_uuid_cache" to "booking-uuid-102",
            "hotel_day_key" to "2026-09-26",
            "night_start" to "2026-09-26 14:00",
            "night_end" to "2026-09-27 12:00",
            "nightly_rate" to 120.0,
            "last_modified" to 300L
        )
        registry.ingestPage(listOf(first))

        // نفس الليلة من مصدر آخر (local_uuid مختلف، أحدث بيانات).
        val second = mapOf(
            "_entity" to "booking_nights",
            "id" to 902,
            "local_uuid" to "night-server-copy",
            "booking_local_id" to 777,
            "booking_uuid_cache" to "booking-uuid-102",
            "hotel_day_key" to "2026-09-26",
            "night_start" to "2026-09-26 14:00",
            "night_end" to "2026-09-27 12:00",
            "nightly_rate" to 150.0,
            "last_modified" to 400L
        )
        val report = registry.ingestPage(listOf(second))

        assertEquals(1, report.applied)
        val nights = db.bookingNightsDao().getByBooking(bookingId)
        assertEquals(1, nights.size)
        assertEquals(150.0, nights.first().nightlyRate, 0.001)
    }

    // ─── 4) ابن بلا أب يُؤجَّل (لا فشل ولا إدراج خام) ───

    @Test
    fun unresolvableBookingNightIsDeferred() = runBlocking {
        val report = registry.ingestPage(
            listOf(
                mapOf(
                    "_entity" to "booking_nights",
                    "id" to 903,
                    "local_uuid" to "night-orphan",
                    "booking_local_id" to 424242,
                    "booking_uuid_cache" to "no-such-booking",
                    "hotel_day_key" to "2026-09-27",
                    "last_modified" to 500L
                )
            )
        )
        assertEquals(0, report.applied)
        assertEquals(1, report.deferred.size)
        assertEquals("booking_nights", report.deferred.first().entity)
        // لا صف يتيم بكتابة مؤشر خام.
        assertEquals(0, db.bookingNightsDao().getByBooking(424242).size)
    }

    // ─── 5) دفعة بحجز غير محلول تُطبَّق بمؤشر NULL (nullable=true) ───

    @Test
    fun paymentWithUnresolvableBookingAppliesWithNullPointer() = runBlocking {
        val report = registry.ingestPage(
            listOf(
                mapOf(
                    "_entity" to "payments",
                    "id" to 904,
                    "local_uuid" to "payment-remote-1",
                    "booking_local_id" to 31337,
                    "booking_uuid_cache" to "no-such-booking",
                    "amount" to 250.0,
                    "payment_date" to "2026-09-25",
                    "payment_method" to "cash",
                    "revenue_type" to "room",
                    "last_modified" to 600L
                )
            )
        )
        assertEquals(1, report.applied)
        val payment = db.paymentsDao().getByLocalUuid("payment-remote-1")!!
        assertNull(payment.bookingLocalId)
    }

    // ─── 6) الحذف البعيد يفوز على تعديل محلي أحدث ويحفظ بيانات الصف ───

    @Test
    fun remoteTombstoneWinsWithoutReplacingNewerLocalBusinessFields() = runBlocking {
        val localId = db.roomsDao().insert(
            RoomEntity(
                roomNumber = "T-101",
                type = "single",
                price = 250.0,
                status = "occupied",
                requiresMaintenance = true,
                localUuid = "room-delete-wins",
                updatedAt = 2_000L,
                lastModified = 2_000L
            )
        )

        val report = registry.ingestPage(
            listOf(
                mapOf(
                    "_entity" to "rooms",
                    "id" to 451,
                    "local_uuid" to "room-delete-wins",
                    "room_number" to "T-101",
                    "type" to "single",
                    "price" to 100.0,
                    "status" to "available",
                    "cleaning_status" to "clean",
                    "requires_maintenance" to 0,
                    "created_at" to 500L,
                    "updated_at" to 1_000L,
                    "deleted_at" to 900L,
                    "last_modified" to 1_000L,
                    "version" to 2
                )
            )
        )

        assertEquals(1, report.applied)
        val saved = db.roomsDao().getByLocalUuid("room-delete-wins")!!
        assertEquals(localId, saved.id)
        assertEquals(250.0, saved.price, 0.001)
        assertEquals("occupied", saved.status)
        assertTrue(saved.requiresMaintenance)
        assertEquals(900L, saved.deletedAt)
        assertEquals(1_000L, saved.updatedAt)
        assertEquals(1_000L, saved.lastModified)
    }

    // ─── 7) رد Worker opStatus=deleted يُختم محلياً حتى في push-only ───

    @Test
    fun serverDeleteDispositionTombstonesLocalRowIdempotently() = runBlocking {
        db.roomsDao().insert(
            RoomEntity(
                roomNumber = "T-102",
                type = "double",
                price = 180.0,
                status = "available",
                localUuid = "room-local-server-delete"
            )
        )

        assertTrue(registry.tombstoneLocalRecord("rooms", "room-local-server-delete"))
        val firstStamp = db.roomsDao().getByLocalUuid("room-local-server-delete")!!.deletedAt
        assertTrue(firstStamp != null)
        assertTrue(registry.tombstoneLocalRecord("rooms", "room-local-server-delete"))
        val saved = db.roomsDao().getByLocalUuid("room-local-server-delete")!!
        assertEquals(firstStamp, saved.deletedAt)
        assertEquals(180.0, saved.price, 0.001)
    }

    private fun derivedRefresh() = com.marina.marina.data.repository.BookingDerivedRefreshService(
        db, db.bookingsDao(), db.roomsDao(), db.paymentsDao(), db.bookingNightsDao()
    )

    private fun editTestBookingsRepository() = com.marina.marina.data.repository.BookingsRepositoryImpl(
        db, db.bookingsDao(), outboxRepository(), derivedRefresh()
    )

    private fun editTestPaymentsRepository() = com.marina.marina.data.repository.PaymentsRepositoryImpl(
        db.paymentsDao(), db.paymentVoidsDao(), outboxRepository(), db, editTestBookingsRepository()
    )

    private suspend fun editTestBooking(room: String = "EDIT-101"): Long {
        db.roomsDao().insert(RoomEntity(roomNumber = room, type = "single", price = 1000.0,
            status = "شاغرة", localUuid = "room-$room"))
        return editTestBookingsRepository().insert(com.marina.marina.domain.model.Booking(
            roomNumber = room, guestName = "نفس النزيل", guestPhone = "", guestNationality = "يمني",
            checkinDate = "2026-10-02T14:01:00", actualCheckout = "2026-10-03T14:00:00",
            status = "مكتمل", calculatedNights = 1, expectedNights = 1
        ))
    }

    private suspend fun assertEditOutbox(entity: String, uuid: String, updates: Int) {
        val operations = db.outboxDao().getPendingPrimary().first().filter { it.entity == entity && it.localUuid == uuid }
        assertEquals(1, operations.count { it.op == "insert" })
        assertEquals(updates, operations.count { it.op == "update" })
        assertEquals(operations.size, operations.map { it.idempotencyKey }.toSet().size)
    }

    @Test
    fun threeIndependentEmployeeExpensesSurviveRepeatedEditsInReports() = runBlocking {
        val employeeId = db.employeesDao().insert(EmployeeEntity(name = "موظف", basicSalary = 1000.0,
            status = "active", localUuid = "three-expenses-employee"))
        assertThreeExpenseEdits("سلفة", employeeId)
    }

    @Test
    fun threeIndependentOperationalExpensesSurviveRepeatedEditsInReports() = runBlocking {
        assertThreeExpenseEdits("تشغيلية", null)
    }

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    private suspend fun assertThreeExpenseEdits(type: String, employeeId: Long?) {
        Dispatchers.setMain(kotlinx.coroutines.test.UnconfinedTestDispatcher())
        val store = androidx.lifecycle.ViewModelStore()
        try {
            val repository = expensesRepository()
            val ids = listOf(100.0, 100.0, 200.0).map { amount ->
                repository.insert(Expense(expenseType = type, relatedId = employeeId, amount = amount,
                    description = "نفس البيان", date = HotelTimeEngine.formatIso(System.currentTimeMillis()),
                    hotelDayKey = HotelTimeEngine.currentHotelDayKey()))
            }
            val originals = ids.map { db.expensesDao().getById(it)!! }
            assertEquals(3, originals.map { it.localUuid }.toSet().size)
            val outbox = outboxRepository()
            val report = com.marina.marina.presentation.reports.ExpensesReportViewModel(
                repository, SalaryWithdrawalsRepositoryImpl(db, db.expensesDao(), db.salaryWithdrawalsDao(), db.employeesDao(), outbox),
                com.marina.marina.data.repository.EmployeesRepositoryImpl(db.employeesDao(), outbox)
            )
            store.put("expenses", report)
            suspend fun check(amount: Double) {
                // نفس سبب awaitSettledReport: سباق قراءة حالة دورة سابقة.
                val state = awaitSettledReport(report.state) { !it.isLoading && it.totalAmount == amount + 300.0 }
                val expected = listOf(amount, 100.0, 200.0).sorted()
                assertEquals(expected, state.groups.flatMap { it.rows }.map { it.amount }.sorted())
                assertEquals(amount + 300.0, state.totalAmount, 0.0)
                assertEquals(0, state.unresolvedMirrorCount)
                val pdf = com.marina.marina.presentation.reports.expensesPdfTable(state)
                assertEquals(3, pdf.rows.size)
                assertEquals(com.marina.marina.domain.util.CurrencyFormatter.formatAmount(amount + 300.0), pdf.totalRow!![1])
                assertEquals(originals[1], db.expensesDao().getById(ids[1]))
                assertEquals(originals[2], db.expensesDao().getById(ids[2]))
                assertEquals(originals[0].localUuid, db.expensesDao().getById(ids[0])!!.localUuid)
                val mirrors = db.salaryWithdrawalsDao().getAll().first()
                assertEquals(if (employeeId == null) 0 else 3, mirrors.size)
                if (employeeId != null) assertEquals(expected, mirrors.map { it.amount }.sorted())
            }
            check(100.0)
            for (amount in listOf(175.0, 150.0, 150.0)) {
                repository.update(db.expensesDao().getById(ids[0])!!.toDomain().copy(amount = amount))
                report.fetch()
                check(amount)
            }
            assertEditOutbox("expenses", originals[0].localUuid, 3)
        } finally {
            store.clear()
            Dispatchers.resetMain()
        }
    }

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    @Test
    fun threeIndependentPaymentsSurviveRepeatedEditsInPaymentAndIncomeReports() = runBlocking {
        Dispatchers.setMain(kotlinx.coroutines.test.UnconfinedTestDispatcher())
        val store = androidx.lifecycle.ViewModelStore()
        try {
            val bookingId = editTestBooking()
            val repository = editTestPaymentsRepository()
            val ids = listOf(100.0, 100.0, 200.0).map { amount ->
                repository.insert(com.marina.marina.domain.model.Payment(bookingLocalId = bookingId,
                    roomNumber = "EDIT-101", amount = amount, paymentMethod = "cash", revenueType = "room"))
            }
            val originals = ids.map { db.paymentsDao().getById(it)!! }
            assertEquals(3, originals.map { it.localUuid }.toSet().size)
            val bookings = editTestBookingsRepository()
            val report = com.marina.marina.presentation.reports.PaymentsReportViewModel(repository, bookings)
            store.put("payments", report)
            val outbox = outboxRepository()
            val income = com.marina.marina.presentation.reports.IncomeExpenseReportViewModel(
                repository, expensesRepository(), bookings,
                com.marina.marina.data.repository.DebtsRepositoryImpl(db.debtsDao(), outbox),
                com.marina.marina.data.repository.EmployeesRepositoryImpl(db.employeesDao(), outbox)
            )
            store.put("income", income)
            suspend fun check(amount: Double) {
                // انتظار تقارب لا «أول حالة غير حاملة»: fetch() غير متزامنة، وقد
                // تُقرأ حالة دورة سابقة قبل أن يبدأ التحديث (سباق رُصد في CI:
                // expected:<475.0> but was:<400.0>). الانتظار على القيمة
                // المتوقعة نفسها يُبقي الاختبار يفشل إن لم يُعكس التعديل أبداً.
                val state = awaitSettledReport(report.state) { !it.isLoading && it.totalAll == amount + 300.0 }
                assertEquals(listOf(amount, 100.0, 200.0).sorted(), state.rows.map { it.payment.amount }.sorted())
                assertEquals(amount + 300.0, state.totalAll, 0.0)
                assertEquals(originals.map { it.localUuid }.toSet(), state.rows.map { it.payment.localUuid }.toSet())
                val incomeState = awaitSettledReport(income.state) { !it.isLoading && it.incomeTotal == amount + 300.0 }
                assertEquals(3, incomeState.entries.size)
                assertEquals(amount + 300.0, incomeState.incomeTotal, 0.0)
                assertEquals(amount + 300.0, incomeState.net, 0.0)
                assertEquals(originals[1], db.paymentsDao().getById(ids[1]))
                assertEquals(originals[2], db.paymentsDao().getById(ids[2]))
            }
            check(100.0)
            for (amount in listOf(175.0, 150.0, 150.0)) {
                repository.update(db.paymentsDao().getById(ids[0])!!.toDomain().copy(amount = amount))
                report.fetch()
                income.fetch()
                check(amount)
            }
            assertEditOutbox("payments", originals[0].localUuid, 3)
        } finally {
            store.clear()
            Dispatchers.resetMain()
        }
    }

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    @Test
    fun paymentEditRefreshesRemainingInReportWithoutReopeningBooking() = runBlocking {
        Dispatchers.setMain(kotlinx.coroutines.test.UnconfinedTestDispatcher())
        val store = androidx.lifecycle.ViewModelStore()
        try {
            val bookingId = editTestBooking()
            val bookings = editTestBookingsRepository()
            val payments = editTestPaymentsRepository()
            val first = payments.insert(com.marina.marina.domain.model.Payment(bookingLocalId = bookingId,
                roomNumber = "EDIT-101", amount = 100.0, paymentMethod = "cash", revenueType = "room"))
            payments.insert(com.marina.marina.domain.model.Payment(bookingLocalId = bookingId,
                roomNumber = "EDIT-101", amount = 200.0, paymentMethod = "cash", revenueType = "room"))
            // Establish a correct initial cache, then edit only the payment.
            bookings.update(bookings.getById(bookingId)!!)
            val report = com.marina.marina.presentation.reports.PaymentsReportViewModel(payments, bookings)
            store.put("payments", report)
            val before = awaitSettledReport(report.state) { !it.isLoading && it.totalDue == 1000.0 }
            assertEquals(1000.0, before.totalDue, 0.0)
            assertEquals(300.0, before.totalAll, 0.0)
            assertEquals(700.0, before.totalRemaining, 0.0)
            payments.update(db.paymentsDao().getById(first)!!.toDomain().copy(amount = 150.0))
            report.fetch()
            val after = awaitSettledReport(report.state) { !it.isLoading && it.totalAll == 350.0 }
            assertEquals(2, after.rows.size)
            assertEquals(350.0, after.totalAll, 0.0)
            assertEquals("Remaining must reflect the edited payment, not stale booking cache", 650.0, after.totalRemaining, 0.0)
        } finally {
            store.clear()
            Dispatchers.resetMain()
        }
    }

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    @Test
    fun bookingEditsKeepIndependentBookingsAndLatestTotalsInGuestReport() = runBlocking {
        Dispatchers.setMain(kotlinx.coroutines.test.UnconfinedTestDispatcher())
        val store = androidx.lifecycle.ViewModelStore()
        try {
            val first = editTestBooking("EDIT-101")
            val second = editTestBooking("EDIT-102")
            val bookings = editTestBookingsRepository()
            val original = bookings.getById(first)!!
            val independent = bookings.getById(second)!!
            val report = com.marina.marina.presentation.reports.GuestDetailReportViewModel(
                bookings, editTestPaymentsRepository(), com.marina.marina.data.repository.RoomsRepositoryImpl(
                    db.roomsDao(), db.bookingsDao(), outboxRepository())
            )
            store.put("guests", report)
            report.setShowOnlyActive(false)
            withTimeout(10_000) { report.state.first { !it.isLoading && it.rows.size == 2 } }
            for (discount in listOf(100.0, 150.0, 150.0)) {
                bookings.update(bookings.getById(first)!!.copy(guestName = "اسم معدل", notes = "تعديل",
                    discount = discount, discountType = "total"))
                val state = withTimeout(10_000) { report.state.first {
                    !it.isLoading && it.rows.any { row -> row.booking.id == first && row.booking.discount == discount }
                } }
                assertEquals(2, state.rows.size)
                assertEquals(original.localUuid, state.rows.single { it.booking.id == first }.booking.localUuid)
                assertEquals(independent, state.rows.single { it.booking.id == second }.booking)
                report.recalcTotals(state.rows)
                assertEquals(2000.0 - discount, report.state.value.totalDue, 0.0)
                assertEquals(2000.0 - discount, report.state.value.totalRemaining, 0.0)
            }
            assertEditOutbox("bookings", original.localUuid, 3)
        } finally {
            store.clear()
            Dispatchers.resetMain()
        }
    }

    @Test
    fun bookingDateEditRecomputesDueOnFirstSaveWithoutDuplicateBooking() = runBlocking {
        val id = editTestBooking()
        val bookings = editTestBookingsRepository()
        val original = bookings.getById(id)!!
        assertEquals(1000.0, original.totalDueCached, 0.0)
        bookings.update(original.copy(actualCheckout = "2026-10-04T14:00:00", expectedNights = 2))
        val updated = bookings.getById(id)!!
        assertEquals(1, bookings.getAll().first().size)
        assertEquals(original.localUuid, updated.localUuid)
        assertEquals(2, updated.calculatedNights)
        assertEquals("Two nights must be reflected on the first edit, not only a later save", 2000.0, updated.totalDueCached, 0.0)
        assertEquals(2000.0, updated.remainingBalanceCached, 0.0)
    }

    @Test
    fun paymentEditRollsBackPaymentCacheAndOutboxWhenCacheWriteFails() = runBlocking {
        val bookingId = editTestBooking()
        val payments = editTestPaymentsRepository()
        val id = payments.insert(com.marina.marina.domain.model.Payment(bookingLocalId = bookingId,
            amount = 100.0, paymentMethod = "cash", revenueType = "room"))
        val bookings = editTestBookingsRepository()
        bookings.update(bookings.getById(bookingId)!!)
        val beforePayment = db.paymentsDao().getById(id)!!
        val beforeBooking = db.bookingsDao().getById(bookingId)!!
        val beforeOutbox = db.outboxDao().getPendingPrimary().first()
        db.openHelper.writableDatabase.execSQL(
            "CREATE TRIGGER reject_cache BEFORE UPDATE OF total_paid_cached ON bookings " +
                "BEGIN SELECT RAISE(ABORT, 'cache write failure'); END"
        )
        try {
            val result = runCatching { payments.update(beforePayment.toDomain().copy(amount = 150.0)) }
            assertTrue(result.isFailure)
            assertEquals(beforePayment, db.paymentsDao().getById(id))
            assertEquals(beforeBooking, db.bookingsDao().getById(bookingId))
            assertEquals(beforeOutbox, db.outboxDao().getPendingPrimary().first())
        } finally {
            db.openHelper.writableDatabase.execSQL("DROP TRIGGER reject_cache")
        }
    }

    @Test
    fun movedPaymentRefreshesBothBookingsPreservingIdentityAndSyncMetadata() = runBlocking {
        val firstBooking = editTestBooking("MOVE-101")
        val secondBooking = editTestBooking("MOVE-102")
        val payments = editTestPaymentsRepository()
        val id = payments.insert(com.marina.marina.domain.model.Payment(bookingLocalId = firstBooking,
            roomNumber = "MOVE-101", amount = 100.0, paymentMethod = "cash", revenueType = "room"))
        payments.insert(com.marina.marina.domain.model.Payment(bookingLocalId = secondBooking,
            roomNumber = "MOVE-102", amount = 200.0, paymentMethod = "cash", revenueType = "room"))
        val bookings = editTestBookingsRepository()
        for (bookingId in listOf(firstBooking, secondBooking)) bookings.update(bookings.getById(bookingId)!!)
        val beforeFirst = db.bookingsDao().getById(firstBooking)!!
        val beforeSecond = db.bookingsDao().getById(secondBooking)!!
        val before = db.paymentsDao().getById(id)!!.copy(
            bookingUuidCache = beforeFirst.localUuid, serverPaymentId = 123,
            vectorClock = "{\"device-a\":7}", origin = "remote", deviceId = "device-a",
            linkedDebtUuid = "retained-debt-reference", syncTimestamp = 1234L
        )
        db.paymentsDao().update(before)
        val bookingOutbox = db.outboxDao().getPendingPrimary().first().filter { it.entity == "bookings" }
        payments.update(before.toDomain().copy(bookingLocalId = secondBooking, roomNumber = "MOVE-102",
            amount = 150.0, localUuid = "must-not-create-new-identity"))
        val after = db.paymentsDao().getById(id)!!
        assertEquals(before.localUuid, after.localUuid)
        assertEquals(beforeSecond.localUuid, after.bookingUuidCache)
        assertEquals(before.serverPaymentId, after.serverPaymentId)
        assertEquals(before.vectorClock, after.vectorClock)
        assertEquals(before.deviceId, after.deviceId)
        assertEquals(before.origin, after.origin)
        assertEquals(before.linkedDebtUuid, after.linkedDebtUuid)
        assertEquals(before.syncTimestamp, after.syncTimestamp)
        assertEquals(2, db.paymentsDao().getAllOnce().size)
        assertEquals(beforeFirst.copy(totalPaidCached = 0.0, remainingBalanceCached = 1000.0), db.bookingsDao().getById(firstBooking))
        assertEquals(beforeSecond.copy(totalPaidCached = 350.0, remainingBalanceCached = 650.0), db.bookingsDao().getById(secondBooking))
        assertEquals(bookingOutbox, db.outboxDao().getPendingPrimary().first().filter { it.entity == "bookings" })
        assertEditOutbox("payments", before.localUuid, 1)
    }

    @Test
    fun installmentDescriptionEditPreservesKindTotalsMirrorAndWirePayload() = runBlocking {
        val employeeId = db.employeesDao().insert(EmployeeEntity(
            name = "Fixture", basicSalary = 1000.0, status = "active", localUuid = "kind-employee"))
        val repository = expensesRepository()
        val id = repository.insert(Expense(expenseType = "خصم من الراتب", relatedId = employeeId,
            amount = 100.0, description = "قسط سلفة أكتوبر", isAutoGenerated = true))
        val before = db.expensesDao().getById(id)!!.toDomain()
        assertEquals("salary_installment", before.expenseKind)
        repository.update(before.copy(description = "تصحيح الوصف بلا كلمات مالية"))
        val after = db.expensesDao().getById(id)!!.toDomain()
        assertEquals("salary_installment", after.expenseKind)
        val employee = db.employeesDao().getByIdIncludingDeleted(employeeId)!!.toDomain()
        val totals = com.marina.marina.domain.util.SalaryEntitlementCalculator.calculateEmployeeEntitlement(employee, listOf(after))
        assertEquals(100.0, totals.installmentsPaid, 0.0)
        assertEquals(0.0, totals.totalDeductions, 0.0)
        assertEquals(1, db.salaryWithdrawalsDao().getByExpenseUuid(after.localUuid).size)
        val rows = db.outboxDao().getPendingPrimary().first().filter { it.entity == "expenses" }
        assertTrue(rows.isNotEmpty())
        rows.forEach { assertEquals("salary_installment", PushWireContract.buildOperation(it, "device-A").data["expense_kind"]) }
    }

    @Test
    fun pullPreservesKindAcrossDevicesAndRejectsUnknownKinds() = runBlocking {
        val localId = db.employeesDao().insert(EmployeeEntity(id = 81,
            name = "Local", basicSalary = 1000.0, status = "active", localUuid = "same-employee"))
        val record = mapOf<String, Any>("_entity" to "expenses", "local_uuid" to "remote-kind",
            "employee_uuid" to "same-employee", "related_id" to 7,
            "expense_type" to "خصم من الراتب", "expense_kind" to "salary_installment",
            "description" to "edited remote note", "is_auto_generated" to 1,
            "amount" to 50.0, "date" to "2026-10-01", "last_modified" to 100L)
        assertEquals(1, registry.ingestPage(listOf(record)).applied)
        val row = db.expensesDao().getByLocalUuid("remote-kind")!!
        assertEquals(localId, row.relatedId)
        assertEquals("salary_installment", row.expenseKind)
        assertTrue(row.isAutoGenerated)
        val report = registry.ingestPage(listOf(record + mapOf("local_uuid" to "invalid-kind", "expense_kind" to "arbitrary")))
        assertTrue(report.hasFailures)
        assertNull(db.expensesDao().getByLocalUuid("invalid-kind"))
        assertTrue(db.syncQuarantineDao().getAll().any { it.entity == "expenses" && it.recordKey == "uuid:invalid-kind" })
    }

    @Test
    fun oldWorkerPayloadCannotEraseAnAlreadyStoredKind() = runBlocking {
        db.expensesDao().insert(ExpenseEntity(expenseType = "خصم من الراتب", expenseKind = "salary_installment",
            description = "original", amount = 50.0, date = "2026-10-01", localUuid = "known-kind"))
        val report = registry.ingestPage(listOf(mapOf("_entity" to "expenses", "local_uuid" to "known-kind",
            "expense_type" to "خصم من الراتب", "description" to "edited", "amount" to 50.0,
            "date" to "2026-10-01", "last_modified" to 200L)))
        assertEquals(1, report.applied)
        assertEquals("salary_installment", db.expensesDao().getByLocalUuid("known-kind")!!.expenseKind)
    }

    @Test
    fun invalidKindLocalInsertDoesNotWriteExpenseMirrorOrOutbox() = runBlocking {
        try { expensesRepository().insert(Expense(expenseType = "مشتريات", expenseKind = "invalid")); error("must reject") }
        catch (_: IllegalArgumentException) { }
        assertTrue(db.expensesDao().getAllOnce().isEmpty())
        assertTrue(db.outboxDao().getPendingPrimary().first().isEmpty())
    }

    private fun expensesRepository(): ExpensesRepositoryImpl {
        val outbox = outboxRepository()
        val withdrawals = SalaryWithdrawalsRepositoryImpl(
            db, db.expensesDao(), db.salaryWithdrawalsDao(), db.employeesDao(), outbox
        )
        return ExpensesRepositoryImpl(db, withdrawals, db.expensesDao(), db.employeesDao(), outbox)
    }

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    @Test
    fun editingEmployeeExpenseRepeatedlyCountsUpdatedAmountOnceInReportAndPdf() = runBlocking {
        kotlinx.coroutines.Dispatchers.setMain(kotlinx.coroutines.test.UnconfinedTestDispatcher())
        val store = androidx.lifecycle.ViewModelStore()
        try {
            val employeeId = db.employeesDao().insert(EmployeeEntity(
                name = "موظف الاختبار", basicSalary = 1000.0, status = "active", localUuid = "report-employee"
            ))
            val repository = expensesRepository()
            val id = repository.insert(Expense(expenseType = "سلفة", relatedId = employeeId, amount = 100.0))
            val original = db.expensesDao().getById(id)!!.toDomain()
            val mirrorUuid = db.salaryWithdrawalsDao().getByExpenseUuid(original.localUuid).single().localUuid
            val outbox = outboxRepository()
            val withdrawals = SalaryWithdrawalsRepositoryImpl(
                db, db.expensesDao(), db.salaryWithdrawalsDao(), db.employeesDao(), outbox
            )
            val report = com.marina.marina.presentation.reports.ExpensesReportViewModel(
                repository, withdrawals,
                com.marina.marina.data.repository.EmployeesRepositoryImpl(db.employeesDao(), outbox)
            )
            store.put("report", report)
            suspend fun assertReport(amount: Double, independent: Double = 0.0) {
                // نفس سبب awaitSettledReport: سباق قراءة حالة دورة سابقة.
                val state = awaitSettledReport(report.state) { !it.isLoading && it.totalAmount == amount + independent }
                val rows = state.groups.flatMap { it.rows }
                assertEquals(if (independent == 0.0) 1 else 2, rows.size)
                assertEquals(amount, rows.single { !it.isSalaryWithdrawal }.amount, 0.0)
                assertEquals(amount + independent, state.totalAmount, 0.0)
                assertEquals(amount + independent, state.salaryTotal, 0.0)
                assertEquals(0, state.unresolvedMirrorCount)
                val pdf = com.marina.marina.presentation.reports.expensesPdfTable(state)
                assertEquals(rows.size, pdf.rows.size)
                assertEquals(com.marina.marina.domain.util.CurrencyFormatter.formatAmount(amount), pdf.rows.first { it[2] == "سلفة" }[1])
                assertEquals(com.marina.marina.domain.util.CurrencyFormatter.formatAmount(amount + independent), pdf.totalRow!![1])
            }
            assertReport(100.0)
            for (amount in listOf(175.0, 250.0, 250.0)) {
                repository.update(db.expensesDao().getById(id)!!.toDomain().copy(amount = amount, description = "تعديل $amount"))
                val mirrors = db.salaryWithdrawalsDao().getByExpenseUuid(original.localUuid)
                assertEquals(1, mirrors.size)
                assertEquals(mirrorUuid, mirrors.single().localUuid)
                assertEquals(amount, mirrors.single().amount, 0.0)
                report.fetch()
                assertReport(amount)
            }
            // Equal amount/day/employee is not proof of a duplicate: keep a real independent withdrawal.
            db.salaryWithdrawalsDao().insert(SalaryWithdrawalEntity(
                employeeId = employeeId, employeeUuid = "report-employee", amount = 250.0,
                withdrawDate = System.currentTimeMillis(), hotelDayKey = original.hotelDayKey,
                localUuid = "independent-report-withdrawal", reason = "direct_withdrawal_test"
            ))
            report.fetch()
            assertReport(250.0, 250.0)
        } finally {
            store.clear()
            kotlinx.coroutines.Dispatchers.resetMain()
        }
    }

    @Test
    fun salaryExpenseWritesAndUnlinksExactlyOneUuidMirrorAtomically() = runBlocking {
        val employeeId = db.employeesDao().insert(EmployeeEntity(name = "A", basicSalary = 1000.0, status = "active", localUuid = "employee-a"))
        val employeeB = db.employeesDao().insert(EmployeeEntity(name = "B", basicSalary = 1000.0, status = "active", localUuid = "employee-b"))
        // An unrelated remote legacy reference must never be mistaken for the new local expense.
        db.salaryWithdrawalsDao().insert(SalaryWithdrawalEntity(
            employeeId = employeeId, employeeUuid = "employee-a", amount = 999.0,
            withdrawDate = 1L, localUuid = "unrelated", reason = "exp_1"
        ))
        val repository = expensesRepository()
        val id = repository.insert(Expense(
            expenseType = "سلفة", relatedId = employeeId, amount = 100.0,
            date = "2026-10-03", hotelDayKey = "2026-10-03"
        ))
        val expense = db.expensesDao().getById(id)!!.toDomain()
        val mirror = db.salaryWithdrawalsDao().getByExpenseUuid(expense.localUuid).single()
        assertEquals("employee-a", mirror.employeeUuid)
        assertEquals(2, db.outboxDao().getPendingPrimary().first().size)
        val wire = db.outboxDao().getPendingPrimary().first().map { PushWireContract.buildOperation(it, "device") }
        assertEquals(expense.localUuid, wire.single { it.entity == "salary_withdrawals" }.data["expense_uuid"])

        repository.update(expense.copy(relatedId = employeeB, employeeUuid = "employee-b", amount = 150.0))
        val updated = db.salaryWithdrawalsDao().getByExpenseUuid(expense.localUuid).single()
        assertEquals(mirror.localUuid, updated.localUuid)
        assertEquals("employee-b", updated.employeeUuid)
        assertEquals(150.0, updated.amount, 0.0)
        repository.update(db.expensesDao().getById(id)!!.toDomain().copy(expenseType = "تشغيلية"))
        assertTrue(db.salaryWithdrawalsDao().getByLocalUuid(mirror.localUuid)!!.deletedAt != null)
        assertNull(db.salaryWithdrawalsDao().getByLocalUuid("unrelated")!!.deletedAt)
        assertNull(db.expensesDao().getById(id)!!.relatedId)
        val beforeRetryCount = db.outboxDao().getPendingPrimary().first().size
        assertTrue(runCatching {
            repository.update(db.expensesDao().getById(id)!!.toDomain().copy(
                expenseType = "سلفة", relatedId = employeeB, employeeUuid = "employee-b"
            ))
        }.isFailure) // A terminal tombstone must not be resurrected via INSERT OR REPLACE.
        assertEquals("تشغيلية", db.expensesDao().getById(id)!!.expenseType)
        assertEquals(beforeRetryCount, db.outboxDao().getPendingPrimary().first().size)
        val keys = db.outboxDao().getPendingPrimary().first().map { it.idempotencyKey }
        assertEquals(keys.size, keys.toSet().size) // distinct edits must not replay the first edit's receipt
    }

    @Test
    fun legacyMirrorWithoutUuidBlocksEditAndRollsBackExpenseAndOutbox() = runBlocking {
        val employeeId = db.employeesDao().insert(EmployeeEntity(name = "A", basicSalary = 1000.0, status = "active", localUuid = "employee-a"))
        val expenseId = db.expensesDao().insert(ExpenseEntity(
            expenseType = "سلفة", relatedId = employeeId, employeeUuid = "employee-a",
            amount = 100.0, description = "old", date = "2026-10-03", localUuid = "old-expense"
        ))
        db.salaryWithdrawalsDao().insert(SalaryWithdrawalEntity(
            employeeId = employeeId, amount = 100.0, withdrawDate = 1L,
            reason = "exp_$expenseId", localUuid = "legacy-mirror", employeeUuid = null
        ))
        val repository = expensesRepository()
        val failure = runCatching { repository.update(db.expensesDao().getById(expenseId)!!.toDomain().copy(amount = 900.0)) }
        assertTrue(failure.isFailure)
        assertEquals(100.0, db.expensesDao().getById(expenseId)!!.amount, 0.0)
        assertEquals(1, db.salaryWithdrawalsDao().getAllOnce().size)
        assertTrue(db.outboxDao().getPendingPrimary().first().isEmpty())
        assertTrue(runCatching { repository.softDelete(expenseId) }.isFailure)
        assertTrue(db.expensesDao().getById(expenseId) != null)
    }

    @Test
    fun failingMirrorInsertRollsBackNewExpenseAndItsOutbox() = runBlocking {
        val employeeId = db.employeesDao().insert(EmployeeEntity(name = "A", basicSalary = 1000.0, status = "active", localUuid = "employee-a"))
        db.openHelper.writableDatabase.execSQL(
            "CREATE TRIGGER fail_mirror BEFORE INSERT ON salary_withdrawals BEGIN SELECT RAISE(ABORT, 'injected failure'); END"
        )
        val result = runCatching {
            expensesRepository().insert(Expense(expenseType = "سلفة", relatedId = employeeId, amount = 100.0))
        }
        assertTrue(result.isFailure)
        assertTrue(db.expensesDao().getAllOnce().isEmpty())
        assertTrue(db.outboxDao().getPendingPrimary().first().isEmpty())
    }

    @Test
    fun pendingEmployeeReassignmentSurvivesDatabaseReopen() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "pending-links-regression.db"
        db.close()
        context.deleteDatabase(name)
        db = Room.databaseBuilder(context, AppDatabase::class.java, name).allowMainThreadQueries().build()
        registry = newRegistry()
        try {
            val employeeId = db.employeesDao().insert(EmployeeEntity(name = "A", basicSalary = 1000.0, status = "active", localUuid = "employee-a"))
            db.expensesDao().insert(ExpenseEntity(
                expenseType = "سلفة", relatedId = employeeId, employeeUuid = "employee-a",
                amount = 100.0, description = "old", date = "2026-10-03", localUuid = "expense-move"
            ))
            val incoming = mapOf<String, Any>(
                "_entity" to "expenses", "local_uuid" to "expense-move", "employee_uuid" to "employee-b",
                "related_id" to 987L, "expense_type" to "سلفة", "amount" to 200.0,
                "description" to "new", "date" to "2026-10-03", "last_modified" to 500L
            )
            assertEquals(1, registry.ingestPage(listOf(incoming)).deferred.size)
            assertEquals(1, db.pendingSyncLinksDao().getAll().size)
            assertEquals(100.0, db.expensesDao().getByLocalUuid("expense-move")!!.amount, 0.0)
            db.close()
            db = Room.databaseBuilder(context, AppDatabase::class.java, name).allowMainThreadQueries().build()
            registry = newRegistry()
            val newId = db.employeesDao().insert(EmployeeEntity(name = "B", basicSalary = 1000.0, status = "active", localUuid = "employee-b"))
            assertEquals(1, registry.retryPendingLinks().applied)
            val saved = db.expensesDao().getByLocalUuid("expense-move")!!
            assertEquals("employee-b", saved.employeeUuid)
            assertEquals(newId, saved.relatedId)
            assertEquals(200.0, saved.amount, 0.0)
            assertTrue(db.pendingSyncLinksDao().getAll().isEmpty())
        } finally {
            db.close()
            context.deleteDatabase(name)
        }
    }

    @Test
    fun foregroundStartRejectionReturnsFailureWithoutNetworkOrCursorReset() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = SyncPreferences(EncryptedSharedPreferencesManager(context))
        prefs.saveLastPullCursor(321L)
        var networkCalls = 0
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, _, _ -> networkCalls++; error("No network after denied foreground start") } as CloudflareWorkerApi
        val service = CloudflareSyncService(api, CloudflareConfig(context), prefs)
        val runner = SyncOperationRunner(CoroutineScope(SupervisorJob() + Dispatchers.IO), Dispatchers.Unconfined) {
            throw IllegalStateException("Synthetic Android background restriction")
        }
        val manager = SyncManager(OutboxRepository(db.outboxDao(), service, prefs, registry),
            service, prefs, registry, runner, derivedRefresh())
        assertEquals(-1, manager.pullOnly())
        assertEquals(-1, manager.pushOnly())
        assertEquals(-1, manager.fullPull())
        assertTrue(manager.syncNow().isError)
        assertTrue(!manager.syncState.value.isSyncing)
        assertEquals(321L, prefs.getLastPullCursor())
        assertEquals(0, networkCalls)
    }

    @Test
    fun acceptedPullFinishesAfterScreenCancellationWithoutAllowingOverlap() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = SyncPreferences(EncryptedSharedPreferencesManager(context))
        prefs.saveAuthToken("test-worker-token")
        prefs.saveLastPullCursor(0L)
        prefs.saveSyncEpoch("stable")
        prefs.setFullReplayPending(false)
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            check(method.name == "pull") { "Pull-only must not push: ${method.name}" }
            Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, callMethod, _ ->
                check(callMethod.name == "execute")
                started.countDown()
                check(release.await(15, TimeUnit.SECONDS)) { "Test did not release pull" }
                Response.success(WorkerPullResponse(
                    changes = emptyList(), cursor = "123", epoch = "stable", hasMore = false,
                    remaining = null, errors = emptyList(), serverTime = null
                ))
            } as Call<*>
        } as CloudflareWorkerApi
        val service = CloudflareSyncService(api, CloudflareConfig(context), prefs)
        val manager = SyncManager(OutboxRepository(db.outboxDao(), service, prefs, registry),
            service, prefs, registry, SyncOperationRunner(CoroutineScope(SupervisorJob() + Dispatchers.IO), Dispatchers.Unconfined), derivedRefresh())
        val screen = launch(start = CoroutineStart.UNDISPATCHED) { manager.pullOnly() }
        try {
            assertTrue("Pull reached network", started.await(15, TimeUnit.SECONDS))
            screen.cancelAndJoin()
            assertTrue(manager.syncState.value.isSyncing)
            assertEquals(-1, manager.pushOnly())
            assertEquals(-1, manager.fullPull())
            assertTrue(manager.syncState.value.isSyncing)
        } finally {
            release.countDown()
            screen.cancelAndJoin()
            withTimeout(15_000) { manager.syncState.first { !it.isSyncing } }
        }
        assertTrue(!manager.syncState.value.isError)
        assertEquals(123L, prefs.getLastPullCursor())
    }

    @Test
    fun epochReplayIncludesOwnRowsAcrossPageLimitAndManagerRestart() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = SyncPreferences(EncryptedSharedPreferencesManager(context))
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("device-A")
        prefs.saveLastPullCursor(999L)
        prefs.saveSyncEpoch("old")
        prefs.setFullReplayPending(false)
        prefs.setTombstoneSweepDone(true) // مسح الحذفيات له اختبار مخصص؛ لا يغيّر عدّ نداءات هذه الحالات.
        val requests = mutableListOf<Pair<Long, String?>>()
        var calls = 0
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, args ->
            check(method.name == "pull") { "Unexpected call: ${method.name}" }
            val cursor = args!![0] as Long
            val excluded = args[2] as String?
            requests.add(cursor to excluded)
            calls++
            val body = WorkerPullResponse(
                changes = emptyList(), cursor = (if (calls == 1) 999L else cursor + 1).toString(),
                epoch = "new", hasMore = calls <= 101, remaining = null, errors = emptyList(), serverTime = null
            )
            Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, callMethod, _ ->
                check(callMethod.name == "execute")
                Response.success(body)
            } as Call<*>
        } as CloudflareWorkerApi
        val service = CloudflareSyncService(api, CloudflareConfig(context), prefs)
        val outbox = OutboxRepository(db.outboxDao(), service, prefs, registry)
        assertEquals(0, SyncManager(outbox, service, prefs, registry, SyncOperationRunner(CoroutineScope(SupervisorJob() + Dispatchers.IO), Dispatchers.Unconfined), derivedRefresh()).pullOnly())
        assertTrue(prefs.isFullReplayPending())
        assertEquals(100L, prefs.getLastPullCursor())
        assertEquals(999L to "device-A", requests.first())
        assertTrue(requests.drop(1).all { it.second == null })
        // New manager resumes from the saved non-zero cursor WITHOUT re-enabling echo filtering.
        assertEquals(0, SyncManager(outbox, service, prefs, newRegistry(), SyncOperationRunner(CoroutineScope(SupervisorJob() + Dispatchers.IO), Dispatchers.Unconfined), derivedRefresh()).pullOnly())
        assertNull(requests.last().second)
        assertTrue(!prefs.isFullReplayPending())
        assertEquals("new", prefs.getSyncEpoch())
    }

    @Test
    fun remoteSalaryTombstoneDoesNotWaitForMissingEmployee() = runBlocking {
        db.salaryWithdrawalsDao().insert(SalaryWithdrawalEntity(
            employeeId = 777, employeeUuid = "missing-parent", amount = 100.0,
            withdrawDate = 1L, localUuid = "deleted-orphan"
        ))
        val report = registry.ingestPage(listOf(mapOf(
            "_entity" to "salary_withdrawals", "local_uuid" to "deleted-orphan",
            "employee_uuid" to "missing-parent", "deleted_at" to 500L, "updated_at" to 501L
        )))
        assertEquals(1, report.applied)
        assertEquals(500L, db.salaryWithdrawalsDao().getByLocalUuid("deleted-orphan")!!.deletedAt)
        assertTrue(db.pendingSyncLinksDao().getAll().isEmpty())
    }
    @Test
    fun wrongEmployeeMirrorBlocksBothExpenseEditAndDeleteAtomically() = runBlocking {
        val employeeA = db.employeesDao().insert(EmployeeEntity(name = "A", basicSalary = 1000.0, status = "active", localUuid = "owner-a"))
        val employeeB = db.employeesDao().insert(EmployeeEntity(name = "B", basicSalary = 1000.0, status = "active", localUuid = "owner-b"))
        val id = db.expensesDao().insert(ExpenseEntity(expenseType = "سلفة", relatedId = employeeA,
            employeeUuid = "owner-a", description = "original", amount = 100.0, date = "2026-10-03", localUuid = "expense-owner"))
        db.salaryWithdrawalsDao().insert(SalaryWithdrawalEntity(employeeId = employeeB, employeeUuid = "owner-b",
            expenseUuid = "expense-owner", amount = 100.0, withdrawDate = 1L, localUuid = "wrong-owner-mirror"))
        val repository = expensesRepository()
        assertTrue(runCatching { repository.softDelete(id) }.isFailure)
        assertTrue(runCatching { repository.update(db.expensesDao().getById(id)!!.toDomain().copy(amount = 300.0)) }.isFailure)
        assertEquals(100.0, db.expensesDao().getById(id)!!.amount, 0.0)
        assertNull(db.expensesDao().getById(id)!!.deletedAt)
        assertNull(db.salaryWithdrawalsDao().getByLocalUuid("wrong-owner-mirror")!!.deletedAt)
        assertTrue(db.outboxDao().getPendingPrimary().first().isEmpty())
    }

    @Test
    fun importedRawEmployeeIdNeverAuthorizesMirrorDeletion() = runBlocking {
        val employee = db.employeesDao().insert(EmployeeEntity(name = "A", basicSalary = 1000.0, status = "active", localUuid = "owner-a"))
        val id = db.expensesDao().insert(ExpenseEntity(expenseType = "سلفة", relatedId = employee,
            employeeUuid = null, description = "imported", amount = 100.0, date = "2026-10-03",
            localUuid = "imported-expense", origin = "cloud", serverId = 600))
        db.salaryWithdrawalsDao().insert(SalaryWithdrawalEntity(employeeId = employee, employeeUuid = "owner-a",
            expenseUuid = "imported-expense", amount = 100.0, withdrawDate = 1L, localUuid = "legacy-mirror-owner"))
        assertTrue(runCatching { expensesRepository().softDelete(id) }.isFailure)
        assertNull(db.salaryWithdrawalsDao().getByLocalUuid("legacy-mirror-owner")!!.deletedAt)
        assertTrue(db.outboxDao().getPendingPrimary().first().isEmpty())
    }

    @Test
    fun orphanSalaryWritesRemainRetryableBeyondNormalQueueLimit() {
        for (attempts in listOf(0, 5, 10, 1000)) {
            assertTrue(!OutboxRepository.retryLimitReached("salary_withdrawals", attempts))
        }
        assertTrue(OutboxRepository.retryLimitReached("rooms", 5))
        assertTrue(!OutboxRepository.retryLimitReached("rooms", 4))
    }

    @Test
    fun localBackupManifestIncludesBothSalaryHistoryTables() {
        val keys = com.marina.marina.data.backup.LocalBackupService.BACKUP_TABLE_KEYS
        assertTrue("salary_withdrawals" in keys)
        assertTrue("salary_carry_over_logs" in keys)
        assertEquals(keys.size, keys.distinct().size)
    }

    @Test
    fun missingSalaryParentDoesNotMatchCoincidentLocalId() = runBlocking {
        val localId = db.employeesDao().insert(EmployeeEntity(name = "Unrelated", basicSalary = 1000.0,
            status = "active", localUuid = "unrelated-local-employee"))
        val result = registry.ingestPage(listOf(wireRecord("_entity" to "salary_withdrawals",
            "local_uuid" to "orphan-numeric", "employee_id" to localId, "amount" to 100,
            "withdraw_date" to "2026-10-03", "withdrawal_type" to "سلفة")))
        assertEquals(1, result.deferred.size)
        assertNull(db.salaryWithdrawalsDao().getByLocalUuid("orphan-numeric"))
        assertEquals(1, db.pendingSyncLinksDao().getAll().size)
    }


    /**
     * انتظار **تقارب** حالة تقرير على القيمة المتوقعة بعد `fetch()`.
     *
     * السبب: `fetch()` تُحدّث الحالة على `viewModelScope` بينما الاختبار
     * يقرأ `state.first { !it.isLoading }` — وقد يقرأ حالة *دورة سابقة*
     * (isLoading=false) قبل أن يبدأ التحديث الجديد أصلاً، أو قبل أن
     * يُطبَّق نتيجته، فيسقط الاختبار عشوائياً حسب جدولة الخيوط. رُصد فعلاً
     * في CI على `threeIndependentPaymentsSurviveRepeatedEditsInPaymentAndIncomeReports`:
     * `expected:<475.0> but was:<400.0>` — أي أن تقرير الدخل قُرئ قبل
     * تطبيق تعديل الدفعة (400 = المجموع القديم).
     *
     * الانتظار هنا على القيمة نفسها لا على العلم: إن لم يُعكس التعديل
     * إطلاقاً (الانحدار الحقيقي الذي يحرسه الاختبار) ينتهي المهلة ويفشل
     * الاختبار — فلا يتحول الإصلاح إلى تخفيف للفحص.
     */
    private suspend fun <T> awaitSettledReport(
        flow: kotlinx.coroutines.flow.StateFlow<T>,
        expected: (T) -> Boolean
    ): T = withTimeout(10_000) { flow.first(expected) }
}
