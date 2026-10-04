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
import org.junit.After
import org.junit.Assert.assertEquals
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

    private fun expensesRepository(): ExpensesRepositoryImpl {
        val outbox = outboxRepository()
        val withdrawals = SalaryWithdrawalsRepositoryImpl(
            db, db.expensesDao(), db.salaryWithdrawalsDao(), db.employeesDao(), outbox
        )
        return ExpensesRepositoryImpl(db, withdrawals, db.expensesDao(), db.employeesDao(), outbox)
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
            service, prefs, registry, SyncOperationRunner(CoroutineScope(SupervisorJob() + Dispatchers.IO), Dispatchers.Unconfined))
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
        assertEquals(0, SyncManager(outbox, service, prefs, registry, SyncOperationRunner(CoroutineScope(SupervisorJob() + Dispatchers.IO), Dispatchers.Unconfined)).pullOnly())
        assertTrue(prefs.isFullReplayPending())
        assertEquals(100L, prefs.getLastPullCursor())
        assertEquals(999L to "device-A", requests.first())
        assertTrue(requests.drop(1).all { it.second == null })
        // New manager resumes from the saved non-zero cursor WITHOUT re-enabling echo filtering.
        assertEquals(0, SyncManager(outbox, service, prefs, newRegistry(), SyncOperationRunner(CoroutineScope(SupervisorJob() + Dispatchers.IO), Dispatchers.Unconfined)).pullOnly())
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

}
