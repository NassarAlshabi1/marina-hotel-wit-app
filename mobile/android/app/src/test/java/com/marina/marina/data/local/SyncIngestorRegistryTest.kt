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
import com.marina.marina.data.repository.BookingNightsRepositoryImpl
import com.marina.marina.data.repository.OutboxRepository
import com.marina.marina.data.repository.SyncIngestorRegistry
import com.marina.marina.di.EncryptedSharedPreferencesManager
import com.marina.marina.domain.model.BookingNight
import com.marina.marina.domain.util.HotelTimeEngine
import java.lang.reflect.Proxy
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
        registry = SyncIngestorRegistry(
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
    }

    @After
    fun closeDatabase() {
        db.close()
    }

    private fun bookingNightsRepository(): BookingNightsRepositoryImpl {
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
        val outbox = OutboxRepository(
            outboxDao = db.outboxDao(),
            syncService = syncService,
            preferences = syncPreferences,
            syncIngestorRegistry = registry
        )
        return BookingNightsRepositoryImpl(
            db = db,
            bookingsDao = db.bookingsDao(),
            nightsDao = db.bookingNightsDao(),
            adjustmentsDao = db.bookingPriceAdjustmentsDao(),
            ledgerDao = db.hotelDayLedgerDao(),
            outboxRepository = outbox
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
}
