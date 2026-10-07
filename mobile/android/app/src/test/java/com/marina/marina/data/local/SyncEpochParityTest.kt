package com.marina.marina.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.local.entity.OutboxEntity
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.local.entity.RoomEntity
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.CloudflareWorkerApi
import com.marina.marina.data.remote.PushWireContract
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.repository.BookingDerivedRefreshService
import com.marina.marina.data.repository.BookingsRepositoryImpl
import com.marina.marina.data.repository.OutboxRepository
import com.marina.marina.data.repository.RoomsRepositoryImpl
import com.marina.marina.data.repository.SyncIngestorRegistry
import com.marina.marina.data.sync.SyncEpochs
import com.marina.marina.di.EncryptedSharedPreferencesManager
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Room as DomainRoom
import java.lang.reflect.Proxy
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
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
 * عقد **وحدة الطوابع الزمنية** بين السلك (D1/Worker/Flutter) والكتابة المحلية —
 * المرجع: `Time.nowEpoch()` = ثوانٍ (`mobile/lib/utils/time.dart:8`)، ختم الـ
 * Worker `Math.floor(Date.now()/1000)`، وعتبتاه `MS_TIMESTAMP_THRESHOLD = 1e11`
 * و`FUTURE_TIMESTAMP_THRESHOLD = 2e9` (`worker/src/database.ts:603/614`).
 *
 * العطل المقيس (2026-10-06) — «سحب دلتا الغرف لا يعمل»:
 *  1. `RoomsRepositoryImpl.updateStatus/softDelete` كانت تختم
 *     `last_modified` بـ`System.currentTimeMillis()` (ميلي، ~1.77e12) بينما
 *     الخادم يختم بالثواني (~1.76e9) ⇒ `remote >= existing` يفشل دائماً ⇒
 *     ذلك الصف **لا يستقبل أي تحديث من السحابة بعد أول نقرة محلية**.
 *  2. `update()`/`insert()` كانت تكتب `last_modified = 0` (نموذج المجال لا
 *     يحمل الحقل) ⇒ العكس: صف الخادم — ولو أقدم — يفوز على تعديلنا.
 *  3. حمولة الرفع كانت تحمل `last_modified` بالميلي، والـ Worker ينسخه حرفياً
 *     (`createRecord`) فيُلوَّث D1 ويقارَن على الأجهزة الأخرى بثوانيها.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncEpochParityTest {

    private lateinit var db: AppDatabase
    private lateinit var registry: SyncIngestorRegistry
    private lateinit var roomsRepository: RoomsRepositoryImpl
    private lateinit var bookingsRepository: BookingsRepositoryImpl

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        registry = newRegistry()
        roomsRepository = RoomsRepositoryImpl(db.roomsDao(), db.bookingsDao(), outboxRepository())
        bookingsRepository = BookingsRepositoryImpl(db, db.bookingsDao(), outboxRepository(), derivedRefresh())
    }

    @After
    fun tearDown() {
        db.close()
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

    private fun derivedRefresh() = BookingDerivedRefreshService(
        db, db.bookingsDao(), db.roomsDao(), db.paymentsDao(), db.bookingNightsDao()
    )

    private fun outboxRepository(): OutboxRepository {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val syncPreferences = SyncPreferences(EncryptedSharedPreferencesManager(context))
        val workerApi = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader,
            arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            throw AssertionError("Unexpected network call in epoch parity test: ${method.name}")
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

    /** سجل سلكي كما يرسله الـ Worker: أسماء أعمدة D1 + `_entity`. */
    private fun wire(entity: String, vararg fields: Pair<String, Any?>): Map<String, Any> {
        val base = mutableMapOf<String, Any>("_entity" to entity)
        for ((key, value) in fields) if (value != null) base[key] = value
        return base
    }

    private fun isSeconds(value: Long): Boolean =
        value in 1_000_000_000L..SyncEpochs.MILLIS_THRESHOLD

    // ─── 1) الكتابة المحلية: ثوانٍ لا ميلي ───────────────────────

    @Test
    fun roomLocalWritesStampSecondsNotMillis() = runBlocking {
        val id = roomsRepository.insert(
            DomainRoom(roomNumber = "E-101", type = "single", price = 500.0, status = "شاغرة")
        )
        val inserted = db.roomsDao().getById(id)!!
        assertTrue("insert.last_modified يجب أن يكون ثوانٍ: ${inserted.lastModified}",
            isSeconds(inserted.lastModified))
        assertTrue("insert.updated_at يجب أن يكون ثوانٍ: ${inserted.updatedAt}",
            isSeconds(inserted.updatedAt))

        // نقرة «تعيين كمحجوزة» من شاشة الغرف — الموضع الذي كان يسمّم الصف.
        roomsRepository.updateStatus(id, "محجوزة")
        val toggled = db.roomsDao().getById(id)!!
        assertTrue("updateStatus.last_modified يجب أن يكون ثوانٍ: ${toggled.lastModified}",
            isSeconds(toggled.lastModified))
        assertTrue("updateStatus.updated_at يجب أن يكون ثوانٍ: ${toggled.updatedAt}",
            isSeconds(toggled.updatedAt))
        // نظير `version = existing.version + 1` في rooms_dao.dart.
        assertEquals(inserted.version + 1, toggled.version)
        assertEquals("محجوزة", toggled.status)

        // تعديل كامل عبر update(): يجب أن يضبط last_modified (كان صفراً) ويرفع النسخة.
        roomsRepository.update(toggled.toDomain().copy(price = 650.0))
        val updated = db.roomsDao().getById(id)!!
        assertTrue("update.last_modified يجب أن يكون ثوانٍ: ${updated.lastModified}",
            isSeconds(updated.lastModified))
        assertEquals(toggled.version + 1, updated.version)

        // الحذف الناعم: ثوانٍ + عملية outbox (كان لا يُرفع إطلاقاً).
        roomsRepository.softDelete(id)
        val deleted = db.roomsDao().getById(id)!!
        assertTrue("softDelete.deleted_at يجب أن يكون ثوانٍ: ${deleted.deletedAt}",
            isSeconds(deleted.deletedAt!!))
        assertTrue(isSeconds(deleted.lastModified))
        val pendingOps = db.outboxDao().getPendingPrimary().first()
        assertEquals(4, pendingOps.size)
        assertTrue(pendingOps.all { it.entity == "rooms" })
        assertEquals(1, pendingOps.count { it.op == "insert" })
        assertEquals(3, pendingOps.count { it.op == "update" })
        // الحذف الناعم يجب أن يُرفع بحمولة تحمل عمود القبورة (عقد Dart:
        // op='update' مع deleted_at/updated_at في الحمولة).
        val deletedOps = pendingOps.filter { it.payload.contains("deleted_at") }
        assertEquals(1, deletedOps.size)
    }

    // ─── 2) صف محلي «مسموم» بالميلي لا يحجب تحديث الخادم ──────────

    @Test
    fun millisStampedLocalRoomStillAcceptsNewerServerRow() = runBlocking {
        val localSeconds = 1_760_000_000L
        db.roomsDao().insert(
            RoomEntity(
                roomNumber = "E-202", type = "double", price = 800.0, status = "محجوزة",
                localUuid = "room-epoch-202",
                updatedAt = localSeconds * 1_000L,
                lastModified = localSeconds * 1_000L // نتاج بناء سابق (ميلي ثانية)
            )
        )
        // الخادم يخبرنا أن الغرفة صارت شاغرة بعد 10 دقائق (طابع بالثواني).
        val report = registry.ingestPage(
            listOf(
                wire(
                    "rooms", "local_uuid" to "room-epoch-202", "room_number" to "E-202",
                    "type" to "double", "price" to 800.0, "status" to "شاغرة",
                    "cleaning_status" to "clean",
                    "updated_at" to (localSeconds + 600L), "last_modified" to (localSeconds + 600L)
                )
            )
        )
        assertEquals("تحديث خادمي أحدث زمنياً يجب أن يُطبَّق", 1, report.applied)
        val stored = db.roomsDao().getByLocalUuid("room-epoch-202")!!
        assertEquals("شاغرة", stored.status)
        // والقيمة المخزَّنة عادت موحّدة بالثواني (شفاء الصف المسموم).
        assertEquals(localSeconds + 600L, stored.lastModified)
        assertTrue(isSeconds(stored.lastModified))
    }

    // ─── 3) صف خادمي مسموم بالميلي يُشطب إلى ثوانٍ عند السحب ──────

    @Test
    fun poisonedServerRoomRowIsNormalizedToSecondsOnIngest() = runBlocking {
        val serverSeconds = 1_765_000_000L
        val report = registry.ingestPage(
            listOf(
                wire(
                    "rooms", "local_uuid" to "room-poisoned", "room_number" to "E-303",
                    "type" to "suite", "price" to 1200.0, "status" to "مكتمل",
                    // نسخة D1 المسمومة: طوابع بالميلي (كما كان يرسلها هذا التطبيق).
                    "updated_at" to serverSeconds * 1_000L,
                    "last_modified" to serverSeconds * 1_000L,
                    "created_at" to serverSeconds * 1_000L
                )
            )
        )
        assertEquals(1, report.applied)
        val stored = db.roomsDao().getByLocalUuid("room-poisoned")!!
        assertEquals(serverSeconds, stored.lastModified)
        assertEquals(serverSeconds, stored.updatedAt)
        assertEquals(serverSeconds, stored.createdAt)

        // والأهم: الصف المخزَّن صار قابلاً للتحديث لاحقاً (لا يقفل نفسه بالميلي).
        val second = registry.ingestPage(
            listOf(
                wire(
                    "rooms", "local_uuid" to "room-poisoned", "room_number" to "E-303",
                    "type" to "suite", "price" to 1300.0, "status" to "شاغرة",
                    "updated_at" to (serverSeconds + 60L), "last_modified" to (serverSeconds + 60L)
                )
            )
        )
        assertEquals(1, second.applied)
        assertEquals(1300.0, db.roomsDao().getByLocalUuid("room-poisoned")!!.price, 0.0)
    }

    // ─── 4) إنهاء الحجز (مكتمل) — طابع ثوانٍ ونسخة مرتفعة ─────────

    @Test
    fun bookingCompletionStampsSecondsAndBumpsVersion() = runBlocking {
        roomsRepository.insert(
            DomainRoom(roomNumber = "E-404", type = "single", price = 400.0, status = "شاغرة")
        )
        val bookingId = bookingsRepository.insert(
            Booking(
                roomNumber = "E-404", guestName = "ضيف الاختبار", status = "محجوزة",
                checkinDate = "2026-10-01T14:01:00"
            )
        )
        val inserted = db.bookingsDao().getById(bookingId)!!
        assertTrue("insert.last_modified ثوانٍ: ${inserted.lastModified}", isSeconds(inserted.lastModified))

        // مسار «إنهاء الحجز» في التطبيق يمرّ من update (BookingCheckoutViewModel).
        bookingsRepository.update(inserted.toDomain().copy(status = "مكتمل"))
        val completed = db.bookingsDao().getById(bookingId)!!
        assertEquals("مكتمل", completed.status)
        assertTrue("update.last_modified ثوانٍ: ${completed.lastModified}", isSeconds(completed.lastModified))
        assertEquals(inserted.version + 1, completed.version)

        // والصف المحلي صار يقبل تحديثاً خادمياً أحدث (لا يقفل نفسه).
        val pull = registry.ingestPage(
            listOf(
                wire(
                    "bookings", "local_uuid" to completed.localUuid, "room_number" to "E-404",
                    "guest_name" to "ضيف السحابة", "guest_phone" to "", "guest_nationality" to "يمني",
                    "status" to "مكتمل", "checkin_date" to "2026-10-01T14:01:00",
                    "updated_at" to (completed.lastModified + 5L),
                    "last_modified" to (completed.lastModified + 5L)
                )
            )
        )
        assertEquals(1, pull.applied)
        assertEquals("ضيف السحابة", db.bookingsDao().getById(bookingId)!!.guestName)
    }

    // ─── 5) حمولة الرفع: الميلي يُشطب قبل مغادرة الجهاز ──────────

    @Test
    fun pushPayloadNormalizesEpochColumnsAndKeepsBusinessTimestamps() {
        val millis = 1_770_000_000_000L
        val payload = """
            {
              "roomNumber": "E-505",
              "updatedAt": $millis,
              "createdAt": $millis,
              "lastModified": $millis,
              "businessMs": $millis,
              "status": "شاغرة"
            }
        """.trimIndent()
        val row = OutboxEntity(
            entity = "rooms", op = "update", localUuid = "room-push-505",
            payload = payload, clientTs = millis,
            idempotencyKey = "rooms_update_room-push-505_test"
        )
        val op = PushWireContract.buildOperation(row, deviceId = "cf_dev_test")
        val data = op.data
        assertEquals(1_770_000_000L, (data["updated_at"] as Number).toLong())
        assertEquals(1_770_000_000L, (data["created_at"] as Number).toLong())
        assertEquals(1_770_000_000L, (data["last_modified"] as Number).toLong())
        // حقل أعمال (ليس من أعمدة الطوابع) لا يُلمس — نفس وحدته القديمة.
        assertEquals(millis, (data["business_ms"] as Number).toLong())
        // مظروف العملية يبقى بالثواني كما كان (clientTs ميلي ÷ 1000).
        assertEquals(1_770_000_000L, op.updatedAt)
        assertEquals("rooms", op.entity)
        assertEquals("update", op.operation)
    }

    @Test
    fun secondsAreNeverDividedTwice() {
        // قيمة ثوانٍ شرعية (حتى سنة 5138) تمر كما هي — لا قسمة مزدوجة.
        val seconds = 1_770_000_000L
        assertEquals(seconds, SyncEpochs.toSeconds(seconds))
        assertFalse(SyncEpochs.isMillisLike(seconds))
        assertEquals(seconds, SyncEpochs.toSeconds(seconds * 1_000L))
        assertTrue(SyncEpochs.isMillisLike(seconds * 1_000L))
        // الغياب والصفر لا يُخمَّنان (لا تلفيق قيمة).
        assertNull(SyncEpochs.toSeconds(null))
        assertEquals(0L, SyncEpochs.toSeconds(0L))
    }
}
