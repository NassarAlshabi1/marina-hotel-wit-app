package com.marina.marina.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.entity.BookingEntity
import com.marina.marina.data.local.entity.PaymentEntity
import com.marina.marina.data.local.entity.RoomEntity
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.CloudflareWorkerApi
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.remote.WorkerPullResponse
import com.marina.marina.data.sync.SyncOperationRunner
import com.marina.marina.di.EncryptedSharedPreferencesManager
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
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
import retrofit2.Call
import retrofit2.Response

/**
 * تكافؤ إعادة بناء الحقول المشتقة للحجوزات بعد السحب — العقد الغائب الذي
 * كشفه تدقيق `cloudflare_sync_manager.dart` (l.2591 `_refreshDerivedAfterPull`
 * و l.3780 `_derivedRefreshEntities` في فرع `feat/cloudflare-sync-execution`).
 *
 * المشكلة التي يحرسها هذا الملف: الإجماليات المخزَّنة في الحجز
 * (`total_due_cached` / `total_paid_cached` / `remaining_balance_cached` /
 * `is_fully_paid` / `calculated_nights`) تُحسب **محلياً على كل جهاز**. فجهاز
 * يسحب دفعة أو ليلة حجز أنشأها جهاز آخر كان يبقى بأرقامه القديمة حتى يفتح
 * المستخدم شاشة الدفع — بينما Flutter يعيد البناء تلقائياً في كل دورة سحب
 * تطبّق صفاً من `bookings`/`booking_nights`/`payments`/… .
 *
 * الشبكة مصطنعة عبر Proxy (لا خادم ولا D1)، وقاعدة البيانات في الذاكرة.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class BookingDerivedRefreshParityTest {

    private lateinit var db: AppDatabase
    private lateinit var registry: SyncIngestorRegistry

    @Before
    fun openInMemoryDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        // حالة SharedPreferences حقيقية تعيش في نفس الـJVM — تُمسح بين الحالات
        // (علم full sync / مسح الحذفيات / المؤشر كان يتسرب ويغيّر المسار).
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        registry = newRegistry()
    }

    @After
    fun closeDatabase() {
        db.close()
    }

    private fun newRegistry() = SyncIngestorRegistry(
        db = db, roomsDao = db.roomsDao(), bookingsDao = db.bookingsDao(),
        paymentsDao = db.paymentsDao(), expensesDao = db.expensesDao(), employeesDao = db.employeesDao(),
        debtsDao = db.debtsDao(), bookingNotesDao = db.bookingNotesDao(), bookingNightsDao = db.bookingNightsDao(),
        bookingPriceAdjustmentsDao = db.bookingPriceAdjustmentsDao(), guestInfosDao = db.guestInfosDao(),
        shiftNotesDao = db.shiftNotesDao(), salaryCyclesDao = db.salaryCyclesDao(),
        salaryPaymentsDao = db.salaryPaymentsDao(), salaryWithdrawalsDao = db.salaryWithdrawalsDao(),
        salaryCarryOverLogsDao = db.salaryCarryOverLogsDao(), appUsersDao = db.appUsersDao(),
        devicesDao = db.devicesDao(), cashTransactionsDao = db.cashTransactionsDao(),
        auditLogsDao = db.auditLogsDao(), paymentVoidsDao = db.paymentVoidsDao(),
        priceAdjustmentsDao = db.priceAdjustmentsDao(), inventoryDao = db.inventoryDao(),
        blacklistEntriesDao = db.blacklistEntriesDao()
    )

    private fun derivedRefresh() = BookingDerivedRefreshService(
        db, db.bookingsDao(), db.roomsDao(), db.paymentsDao(), db.bookingNightsDao()
    )

    private fun preferences(): SyncPreferences {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return SyncPreferences(EncryptedSharedPreferencesManager(context))
    }

    private fun callOf(response: Response<*>): Call<*> =
        java.lang.reflect.Proxy.newProxyInstance(
            Call::class.java.classLoader, arrayOf(Call::class.java)
        ) { _, method, _ ->
            check(method.name == "execute")
            response
        } as Call<*>

    private fun todayIso(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    /** اسمح للمحرك بأن ينهي دورته غير المتزامنة داخل runBlocking (Dispatchers.Unconfined). */
    private suspend fun pullOnce(prefs: SyncPreferences, api: CloudflareWorkerApi): Int {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val service = CloudflareSyncService(
            api, CloudflareConfig(ApplicationProvider.getApplicationContext()), prefs
        )
        return try {
            SyncManager(
                OutboxRepository(db.outboxDao(), service, prefs, registry),
                service, prefs, registry,
                SyncOperationRunner(scope, Dispatchers.Unconfined), derivedRefresh()
            ).pullOnly()
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    private fun readyPrefs(): SyncPreferences = preferences().apply {
        saveAuthToken("test-worker-token")
        saveDeviceId("derived-device")
        saveLastPullCursor(500L)
        saveSyncEpoch("derived-parity")
        setFullReplayPending(false)
        // مسار المسح له اختباراته؛ هنا دورة دلتا نقية.
        setTombstoneSweepDone(true)
    }

    private suspend fun seedRoomAndBooking(bookingUuid: String): Long {
        db.roomsDao().insert(RoomEntity(
            roomNumber = "DR-1", type = "single", price = 100.0,
            status = "شاغرة", cleaningStatus = "clean", localUuid = "room-dr-1"
        ))
        return db.bookingsDao().insert(BookingEntity(
            roomNumber = "DR-1", guestName = "ضيف المشتقات", guestPhone = "700",
            guestNationality = "يمني", checkinDate = todayIso(), status = "محجوزة",
            expectedNights = 1, localUuid = bookingUuid
        ))
    }

    private fun apiReturning(changes: List<Map<String, Any>>): CloudflareWorkerApi =
        java.lang.reflect.Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, args ->
            check(method.name == "pull") { "مسار السحب لا يرفع: ${method.name}" }
            check(args!![5] == null) { "لا مسح حذفيات في هذه الحالات" }
            callOf(Response.success(WorkerPullResponse(
                changes = changes, cursor = "600", epoch = "derived-parity",
                hasMore = false, remaining = null, errors = emptyList(), serverTime = null
            )))
        } as CloudflareWorkerApi

    private fun remotePayment(uuid: String, bookingUuid: String, amount: Double): Map<String, Any> = mapOf(
        "_entity" to "payments", "id" to 42, "local_uuid" to uuid,
        "booking_uuid_cache" to bookingUuid, "amount" to amount,
        "payment_date" to todayIso(), "payment_method" to "نقدي",
        "revenue_type" to "room", "hotel_day_key" to todayIso(),
        "updated_at" to 1_000L, "last_modified" to 1_000L
    )

    private fun remoteNight(uuid: String, bookingUuid: String, rate: Double): Map<String, Any> = mapOf(
        "_entity" to "booking_nights", "id" to 77, "local_uuid" to uuid,
        "booking_uuid_cache" to bookingUuid, "hotel_day_key" to todayIso(),
        "night_start" to "${todayIso()} 14:00", "night_end" to "${todayIso()} 12:00",
        "nightly_rate" to rate, "final_rate" to rate, "base_rate" to rate,
        "updated_at" to 1_000L, "last_modified" to 1_000L
    )

    // ─── 1) دورة سحب تطبّق دفعة بعيدة ⇒ تُعاد الإجماليات المخزَّنة فوراً ───

    @Test
    fun pullingRemotePaymentRebuildsBookingCachedTotals() = runBlocking {
        val bookingUuid = "parity-booking-payment"
        val bookingId = seedRoomAndBooking(bookingUuid)
        val before = db.bookingsDao().getById(bookingId)!!
        assertEquals(0.0, before.totalPaidCached, 0.001)
        assertEquals(0.0, before.totalDueCached, 0.001)

        val prefs = readyPrefs()
        assertEquals(1, pullOnce(prefs, apiReturning(listOf(remotePayment("pay-remote-1", bookingUuid, 100.0)))))

        // الدفعة رُبطت بالحجز المحلي عبر UUID (لا id جهاز آخر).
        val payment = db.paymentsDao().getByLocalUuid("pay-remote-1")!!
        assertEquals(bookingId, payment.bookingLocalId)

        // الإجماليات المخزَّنة أُعيد بناؤها فعلاً — لا صفراً ولا نسخة قديمة.
        // عدد الليالي يتبع ساعة التنفيذ (حدّ 14:01 في محرّك أيام الفندق)، لذلك
        // تُتحقَّق العلاقة الحتمية: المستحق = الليالي المحسوبة × سعر الغرفة (100)
        // والمدفوع = الدفعة المسحوبة (100) والمتبقي = الفرق.
        val after = db.bookingsDao().getById(bookingId)!!
        assertTrue(after.calculatedNights >= 1)
        val expectedDue = after.calculatedNights * 100.0
        assertEquals(expectedDue, after.totalDueCached, 0.001)
        assertTrue(after.totalDueCached > 0.0)
        assertEquals(100.0, after.totalPaidCached, 0.001)
        assertEquals(expectedDue - 100.0, after.remainingBalanceCached, 0.001)
        assertEquals(after.remainingBalanceCached <= 0.0, after.isFullyPaid)

        // المشتق محلي بحت: لا يمس بيانات المزامنة ولا يُدرج في outbox.
        assertEquals(before.updatedAt, after.updatedAt)
        assertEquals(before.lastModified, after.lastModified)
        assertEquals(0, db.outboxDao().pendingCount().first())
    }

    // ─── 2) ليلة حجز بعيدة ⇒ الحساب من سجل الليالي (ledger) لا الصيغة ───

    @Test
    fun pullingRemoteNightRebuildsCachedTotalsFromLedger() = runBlocking {
        val bookingUuid = "parity-booking-night"
        val bookingId = seedRoomAndBooking(bookingUuid)

        val prefs = readyPrefs()
        assertEquals(1, pullOnce(prefs, apiReturning(listOf(remoteNight("night-remote-1", bookingUuid, 150.0)))))

        val night = db.bookingNightsDao().getByLocalUuid("night-remote-1")
        assertEquals(bookingId, night!!.bookingLocalId)
        val after = db.bookingsDao().getById(bookingId)!!
        assertTrue(after.calculatedNights >= 1)
        // السجل الليلي الموجود يسبق الصيغة: 150 لا 100 (سعر الغرفة).
        assertEquals(150.0, after.totalDueCached, 0.001)
        assertEquals(0.0, after.totalPaidCached, 0.001)
        assertEquals(150.0, after.remainingBalanceCached, 0.001)
        assertFalse(after.isFullyPaid)
    }

    // ─── 3) البوابة: لا إعادة بناء لكيان لا يؤثر (نظير _derivedRefreshEntities) ───

    @Test
    fun unrelatedPulledEntityDoesNotRebuildDerivedTotals() = runBlocking {
        val bookingUuid = "parity-booking-rooms-only"
        val bookingId = seedRoomAndBooking(bookingUuid)

        val prefs = readyPrefs()
        val roomRow = mapOf<String, Any>(
            "_entity" to "rooms", "id" to 11, "local_uuid" to "room-remote-9",
            "room_number" to "DR-9", "type" to "single", "price" to 999.0,
            "status" to "شاغرة", "cleaning_status" to "clean",
            "updated_at" to 1_000L, "last_modified" to 1_000L
        )
        val before = db.bookingsDao().getById(bookingId)!!
        assertEquals(1, pullOnce(prefs, apiReturning(listOf(roomRow))))

        // لا إعادة بناء إطلاقاً: كل الحقول المخزَّنة كما كانت قبل الدورة
        // (كتلة الغرف ليست في _derivedRefreshEntities الدارتي).
        val after = db.bookingsDao().getById(bookingId)!!
        assertEquals(before.calculatedNights, after.calculatedNights)
        assertEquals(before.totalDueCached, after.totalDueCached, 0.001)
        assertEquals(before.totalPaidCached, after.totalPaidCached, 0.001)
        assertEquals(before.remainingBalanceCached, after.remainingBalanceCached, 0.001)
        assertEquals(before.isFullyPaid, after.isFullyPaid)
    }

    // ─── 4) الخدمة نفسها: النطاق (النشط فقط) وحارس إعادة الدخول ───

    @Test
    fun refreshAllActiveBookingsTouchesOnlyActiveRows() = runBlocking {
        val activeId = seedRoomAndBooking("derived-active")
        val checkedOutId = db.bookingsDao().insert(BookingEntity(
            roomNumber = "DR-1", guestName = "مغادر", guestPhone = "701", guestNationality = "يمني",
            checkinDate = todayIso(), status = "محجوزة", actualCheckout = todayIso(),
            localUuid = "derived-checked-out"
        ))
        val deletedId = db.bookingsDao().insert(BookingEntity(
            roomNumber = "DR-1", guestName = "محذوف", guestPhone = "702", guestNationality = "يمني",
            checkinDate = todayIso(), status = "محجوزة",
            localUuid = "derived-deleted"
        ))
        db.bookingsDao().softDelete(deletedId, deletedAt = 5L, updatedAt = 5L, lastModified = 5L)

        // قيم حرس لا يجوز أن تُلمس.
        db.bookingsDao().updateFinancialCache(checkedOutId, 9, 42.0, 42.0, 42.0, true)
        db.bookingsDao().updateFinancialCache(deletedId, 9, 43.0, 43.0, 43.0, true)
        db.paymentsDao().insert(PaymentEntity(
            bookingLocalId = activeId, amount = 40.0, paymentDate = todayIso(),
            paymentMethod = "نقدي", revenueType = "room", localUuid = "pay-derived-local"
        ))

        val refreshed = derivedRefresh().refreshAllActiveBookings()
        assertEquals(1, refreshed)
        val active = db.bookingsDao().getById(activeId)!!
        assertEquals(40.0, active.totalPaidCached, 0.001)
        assertTrue(active.calculatedNights >= 1)
        assertEquals(active.calculatedNights * 100.0, active.totalDueCached, 0.001)

        val checkedOut = db.bookingsDao().getById(checkedOutId)!!
        assertEquals(42.0, checkedOut.totalDueCached, 0.001)
        val deleted = db.bookingsDao().listAllIncludingDeleted().single { it.id == deletedId }
        assertEquals(43.0, deleted.totalDueCached, 0.001)
    }

    @Test
    fun refreshForBookingIdIsNoOpForMissingRowAndSkipsDeleted() = runBlocking {
        val service = derivedRefresh()
        assertFalse(service.refreshForBookingId(4_242L))

        val deletedId = db.bookingsDao().insert(BookingEntity(
            roomNumber = "DR-1", guestName = "محذوف", guestPhone = "703", guestNationality = "يمني",
            checkinDate = todayIso(), status = "محجوزة", localUuid = "derived-deleted-2"
        ))
        db.bookingsDao().softDelete(deletedId, deletedAt = 5L, updatedAt = 5L, lastModified = 5L)
        // getById يستثني المحذوف ناعمياً ⇒ لا إعادة بناء بلا صف.
        assertFalse(service.refreshForBookingId(deletedId))
    }

    // ─── 5) تقرير الاستيعاب يحمل الكيانات المطبَّقة (touched) ───

    @Test
    fun ingestReportCarriesOnlyAppliedEntities() = runBlocking {
        val roomRow = mapOf<String, Any>(
            "_entity" to "rooms", "local_uuid" to "touched-room", "room_number" to "T-1",
            "type" to "single", "price" to 50.0, "status" to "شاغرة",
            "cleaning_status" to "clean", "updated_at" to 500L, "last_modified" to 500L
        )
        val applied = registry.ingestPage(listOf(
            roomRow,
            mapOf("_entity" to "payments", "local_uuid" to "touched-bad-payment", "amount" to "not-a-number")
        ))
        assertEquals(setOf("rooms"), applied.touched)
        assertEquals(1, applied.applied)
        assertEquals(1, applied.failed)

        // الصف المتخطّى (المحلي أحدث) لا يُحتسب مطبَّقاً — نظير touchedEntities الدارتي.
        val skipped = registry.ingestPage(listOf(
            roomRow + ("last_modified" to 100L) + ("updated_at" to 100L)
        ))
        assertEquals(1, skipped.skipped)
        assertTrue(skipped.touched.isEmpty())
    }
}
