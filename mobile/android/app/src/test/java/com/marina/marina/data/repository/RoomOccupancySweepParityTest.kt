package com.marina.marina.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.entity.BookingEntity
import com.marina.marina.data.local.entity.RoomEntity
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.CloudflareWorkerApi
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.sync.SyncEpochs
import com.marina.marina.di.EncryptedSharedPreferencesManager
import java.lang.reflect.Proxy
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * تكافؤ **إشغال الغرف الشامل** مع Dart — `RoomsRepository.refreshAllRoomOccupancy`
 * (`mobile/lib/services/repositories/rooms_repository.dart` l.221-258 في فرع
 * `feat/cloudflare-sync-execution`)، وهو ما ينفّذه المرجع في موضعين فقط:
 * حفظ الحجز (`booking_edit.dart` l.1131) وإتمام المغادرة
 * (`booking_checkout_screen.dart` l.702-711).
 *
 * كان عندنا «تقريب موضعي» يحدّث غرفتين فقط؛ هذا الاختبار يقفل نقل الدالة
 * بحرفها — بما فيها سلوكها المحرج المعلن: **الغرفة تحت الصيانة تُعاد إلى
 * «شاغرة»** عند عدم وجود حجز نشط (لأنها ليست «مشغولة» ولا «متاحة»)، وهو سلوك
 * Dart نفسه، ونُقل بدل «تحسينه» حتى لا يفترق الطرفان.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RoomOccupancySweepParityTest {

    private lateinit var db: AppDatabase
    private lateinit var registry: SyncIngestorRegistry
    private lateinit var outbox: OutboxRepository
    private lateinit var rooms: RoomsRepositoryImpl

    @Before
    fun openInMemoryDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        registry = newRegistry()
        outbox = outboxRepository()
        rooms = RoomsRepositoryImpl(db.roomsDao(), db.bookingsDao(), outbox)
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

    private fun outboxRepository(): OutboxRepository {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val syncPreferences = SyncPreferences(EncryptedSharedPreferencesManager(context))
        val workerApi = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader,
            arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            throw AssertionError("Unexpected network call in occupancy sweep test: ${method.name}")
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

    private suspend fun seedRoom(number: String, status: String, uuid: String = "room-$number"): Long =
        db.roomsDao().insert(
            RoomEntity(
                roomNumber = number, type = "single", price = 100.0,
                status = status, cleaningStatus = "clean", localUuid = uuid
            )
        )

    private suspend fun seedBooking(number: String, status: String, uuid: String): Long {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        return db.bookingsDao().insert(
            BookingEntity(
                roomNumber = number, guestName = "ضيف $number", guestPhone = "700000000",
                guestNationality = "يمني", checkinDate = today, status = status,
                expectedNights = 1, localUuid = uuid
            )
        )
    }

    private fun isSeconds(value: Long): Boolean = value in 1_000_000_000L..SyncEpochs.MILLIS_THRESHOLD

    // ─── الحالات ─────────────────────────────────────────────────────────────

    @Test
    fun occupiedRoomWithoutActiveBookingIsFreedToAvailable() = runBlocking {
        seedRoom("S-1", "محجوزة")
        rooms.refreshAllRoomOccupancy()

        val room = requireNotNull(db.roomsDao().getByNumber("S-1"))
        assertEquals("شاغرة", room.status)
        assertEquals("version+1 (عقد updateByNumber)", 2, room.version)
        assertTrue("updated_at يجب أن يكون ثوانٍ: ${room.updatedAt}", isSeconds(room.updatedAt))
        assertTrue("last_modified يجب أن يكون ثوانٍ: ${room.lastModified}", isSeconds(room.lastModified))
        val pending = db.outboxDao().getPendingPrimary().first()
        assertEquals(1, pending.size)
        assertEquals("rooms", pending.first().entity)
        assertEquals("update", pending.first().op)
    }

    @Test
    fun availableRoomWithActiveBookingBecomesOccupied() = runBlocking {
        seedRoom("S-2", "شاغرة")
        seedBooking("S-2", "محجوزة", "booking-s2")

        rooms.refreshAllRoomOccupancy()

        val room = requireNotNull(db.roomsDao().getByNumber("S-2"))
        assertEquals("محجوزة", room.status)
        assertEquals(2, room.version)
    }

    @Test
    fun completedBookingDoesNotKeepRoomOccupied() = runBlocking {
        // حجز حالته «مكتمل» ليس في قائمة النشط في SQL (نظير activeBookingStatuses)
        // ولا «الغرفة» محجوزة بحجز مكتمل ⇒ تُحرَّر.
        seedRoom("S-3", "محجوزة")
        seedBooking("S-3", "مكتمل", "booking-s3")

        rooms.refreshAllRoomOccupancy()

        val room = requireNotNull(db.roomsDao().getByNumber("S-3"))
        assertEquals("شاغرة", room.status)
    }

    @Test
    fun maintenanceRoomIsResetToAvailableExactlyLikeDart() = runBlocking {
        // سلوك Dart الحرفي: «صيانة» ليست مشغولة ولا متاحة ⇒ تُعاد إلى «شاغرة».
        // هذا هو «الفرق المقصود» الذي كان يحتاج قراراً؛ نُقل كما هو (تكافؤ).
        seedRoom("S-4", "صيانة")

        rooms.refreshAllRoomOccupancy()

        val room = requireNotNull(db.roomsDao().getByNumber("S-4"))
        assertEquals("شاغرة", room.status)
    }

    @Test
    fun roomAlreadyInTargetStateIsNotRewritten() = runBlocking {
        seedRoom("S-5", "شاغرة")
        seedRoom("S-6", "محجوزة")
        seedBooking("S-6", "نشط", "booking-s6")

        rooms.refreshAllRoomOccupancy()

        // بلا كتابة: لا رفع نسخة ولا إدراج outbox (نفس شرطي `if` في Dart).
        assertEquals(1, requireNotNull(db.roomsDao().getByNumber("S-5")).version)
        assertEquals(1, requireNotNull(db.roomsDao().getByNumber("S-6")).version)
        assertEquals(0, db.outboxDao().getPendingPrimary().first().size)
    }

    @Test
    fun serverOriginSweepSkipsOutboxButStampsSeconds() = runBlocking {
        seedRoom("S-7", "محجوزة")

        rooms.refreshAllRoomOccupancy(originIsServer = true)

        val room = requireNotNull(db.roomsDao().getByNumber("S-7"))
        assertEquals("شاغرة", room.status)
        assertEquals(2, room.version)
        assertTrue(isSeconds(room.lastModified))
        assertEquals("originIsServer لا يُدرج outbox", 0, db.outboxDao().getPendingPrimary().first().size)
    }
}
