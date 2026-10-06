package com.marina.marina.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.CloudflareWorkerApi
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.remote.WorkerPullResponse
import com.marina.marina.data.repository.OutboxRepository
import com.marina.marina.data.repository.SyncIngestorRegistry
import com.marina.marina.data.repository.SyncManager
import com.marina.marina.data.sync.SyncOperationRunner
import com.marina.marina.di.EncryptedSharedPreferencesManager
import java.io.IOException
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.flow.first
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.Call
import retrofit2.Response

/**
 * تكافؤ مسار السحب مع تطبيق Flutter
 * (`mobile/lib/services/cloudflare_sync_manager.dart`، فرع
 * feat/cloudflare-sync-execution) — العقود الأربعة التي كانت غائبة عن
 * محرك Kotlin:
 *
 * 1. **مسح الحذفيات التاريخي لمرة واحدة** (`tombstones_only=1`، مؤشر
 *    مستقل قابل للاستئناف، بلا مساس بالمؤشر الرئيسي).
 * 2. **حارس الإقلاع ضد المؤشر المسموم** (طوابع ميلي/sentinel ≥2e9).
 * 3. **حارس أثناء التشغيل**: مؤشر خادم يتجاوز `server_time` المُعلن بأكثر
 *    من هامش سنة لا يُطبَّق ولا يتقدم.
 * 4. **حارس التثبيت النهائي**: مؤشر فوق الحد الثابت لا يُخزَّن أبداً.
 * 5. **السحب المُشغَّل بحدث Realtime**: دلتا فقط، بلا رفع، ويتخطى بصمت
 *    عند انشغال مزامنة أخرى (عقد `realtimeTriggeredPull`).
 *
 * كل الشبكة مصطنعة عبر Proxy لواجهة الـ API — لا خادم ولا D1 حقيقي.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncPullParityTest {

    private lateinit var db: AppDatabase
    private lateinit var registry: SyncIngestorRegistry

    @Before
    fun openInMemoryDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
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

    private fun preferences(): SyncPreferences {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return SyncPreferences(EncryptedSharedPreferencesManager(context))
    }

    private fun callOf(response: Response<*>): Call<*> =
        Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, method, _ ->
            check(method.name == "execute")
            response
        } as Call<*>

    /** طلب سحب مُسجَّل: (المؤشر، استبعاد الجهاز، tombstones_only). */
    private data class PullRequest(val cursor: Long, val excludeDevice: String?, val tombstonesOnly: String?)

    private fun manager(
        prefs: SyncPreferences,
        api: CloudflareWorkerApi,
        scope: CoroutineScope
    ): SyncManager {
        val service = CloudflareSyncService(api, CloudflareConfig(ApplicationProvider.getApplicationContext()), prefs)
        return SyncManager(
            OutboxRepository(db.outboxDao(), service, prefs, registry),
            service, prefs, registry, SyncOperationRunner(scope, Dispatchers.Unconfined)
        )
    }

    private fun roomPayload(uuid: String, number: String, updatedAt: Long, deletedAt: Long? = null): Map<String, Any> {
        val base = mutableMapOf<String, Any>(
            "_entity" to "rooms", "local_uuid" to uuid, "room_number" to number,
            "type" to "single", "price" to 100.0, "status" to "available",
            "cleaning_status" to "clean", "updated_at" to updatedAt
        )
        if (deletedAt != null) base["deleted_at"] = deletedAt
        return base
    }

    // ─── 1) مسح الحذفيات التاريخي ────────────────────────────────

    @Test
    fun tombstoneSweepAppliesHistoricalDeletesOnceWithoutTouchingDeltaCursor() = runBlocking {
        registry.ingestPage(listOf(roomPayload("sweep-room", "SW-1", updatedAt = 100L)))
        assertNull(db.roomsDao().getByLocalUuid("sweep-room")!!.deletedAt)

        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("sweep-device")
        prefs.saveLastPullCursor(1_000L)
        prefs.saveSyncEpoch("parity")
        prefs.setFullReplayPending(false)

        val requests = mutableListOf<PullRequest>()
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, args ->
            check(method.name == "pull") { "مسار السحب لا يدفع: ${method.name}" }
            val request = PullRequest(args!![0] as Long, args[2] as String?, args[5] as String?)
            requests.add(request)
            val response = if (request.tombstonesOnly == "1") {
                WorkerPullResponse(
                    changes = listOf(roomPayload("sweep-room", "SW-1", updatedAt = 2_000L, deletedAt = 1_999L)),
                    cursor = "555", epoch = "parity", hasMore = false,
                    remaining = null, errors = emptyList(), serverTime = null
                )
            } else {
                WorkerPullResponse(
                    changes = emptyList(), cursor = "1001", epoch = "parity", hasMore = false,
                    remaining = null, errors = emptyList(), serverTime = null
                )
            }
            callOf(Response.success(response))
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val subject = manager(prefs, api, scope)
            assertEquals(0, subject.pullOnly())

            // الحذف التاريخي طُبّق محلياً.
            assertNotNull(db.roomsDao().getByLocalUuid("sweep-room")!!.deletedAt)
            // المؤشر الرئيسي تقدم بمؤشر الدلتا فقط (555 مؤشر المسح — لا يلمسه).
            assertEquals(1_001L, prefs.getLastPullCursor())
            assertTrue(prefs.isTombstoneSweepDone())
            assertEquals(
                listOf(PullRequest(0L, "sweep-device", "1"), PullRequest(1_000L, "sweep-device", null)),
                requests
            )

            // دورة ثانية: المسح لا يُعاد إطلاقاً.
            assertEquals(0, subject.pullOnly())
            assertEquals(1, requests.count { it.tombstonesOnly == "1" })
            assertEquals(1_001L, requests.last().cursor)
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    @Test
    fun tombstoneSweepFailureKeepsGateOpenAndDeltaCycleSucceeds() = runBlocking {
        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("sweep-device")
        prefs.saveLastPullCursor(777L)
        prefs.saveSyncEpoch("parity")
        prefs.setFullReplayPending(false)

        var sweepCalls = 0
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, args ->
            check(method.name == "pull")
            val tombstonesOnly = args!![5] as String?
            if (tombstonesOnly == "1") {
                sweepCalls++
                callOf(Response.error<Unit>(500, "boom".toResponseBody(null)))
            } else {
                callOf(Response.success(WorkerPullResponse(
                    changes = emptyList(), cursor = "778", epoch = "parity", hasMore = false,
                    remaining = null, errors = emptyList(), serverTime = null
                )))
            }
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val subject = manager(prefs, api, scope)
            assertEquals(0, subject.pullOnly())
            assertEquals(1, sweepCalls)
            // فشل المسح لا يضبط العلم — يُعاد في الدورة القادمة...
            assertFalse(prefs.isTombstoneSweepDone())
            // ...ولا يمسّ نتيجة دورة الدلتا ولا مؤشرها.
            assertEquals(778L, prefs.getLastPullCursor())
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    @Test
    fun tombstoneSweepResumesFromSavedCursorAfterNetworkFailure() = runBlocking {
        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("sweep-device")
        prefs.saveLastPullCursor(900L)
        prefs.saveSyncEpoch("parity")
        prefs.setFullReplayPending(false)

        var sweepCalls = 0
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, args ->
            check(method.name == "pull")
            if (args!![5] as String? == "1") {
                sweepCalls++
                if (sweepCalls == 1) {
                    callOf(Response.success(WorkerPullResponse(
                        changes = listOf(roomPayload("sweep-partial", "SW-9", updatedAt = 5L, deletedAt = 4L)),
                        cursor = "300", epoch = "parity", hasMore = true,
                        remaining = null, errors = emptyList(), serverTime = null
                    )))
                } else {
                    throw IOException("synthetic network outage")
                }
            } else {
                callOf(Response.success(WorkerPullResponse(
                    changes = emptyList(), cursor = "901", epoch = "parity", hasMore = false,
                    remaining = null, errors = emptyList(), serverTime = null
                )))
            }
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val subject = manager(prefs, api, scope)
            assertEquals(0, subject.pullOnly())
            // تقدم الصفحة الأولى حُفظ للاستئناف، والعلم ما زال مفتوحاً.
            assertEquals(300L, prefs.getTombstoneSweepCursor())
            assertFalse(prefs.isTombstoneSweepDone())
            assertEquals(901L, prefs.getLastPullCursor())
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    @Test
    fun sweepPageCapKeepsTheGateOpenAndResumesNextCycle() = runBlocking {
        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("sweep-device")
        prefs.saveLastPullCursor(4_000L)
        prefs.saveSyncEpoch("parity")
        prefs.setFullReplayPending(false)

        var sweepCalls = 0
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, args ->
            check(method.name == "pull")
            if (args!![5] as String? == "1") {
                sweepCalls++
                callOf(Response.success(WorkerPullResponse(
                    changes = listOf(roomPayload("sweep-$sweepCalls", "SW-$sweepCalls", updatedAt = 10L, deletedAt = 9L)),
                    cursor = (sweepCalls * 10).toString(), epoch = "parity", hasMore = true,
                    remaining = null, errors = emptyList(), serverTime = null
                )))
            } else {
                callOf(Response.success(WorkerPullResponse(
                    changes = emptyList(), cursor = "4001", epoch = "parity", hasMore = false,
                    remaining = null, errors = emptyList(), serverTime = null
                )))
            }
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            manager(prefs, api, scope).pullOnly()
            // 20 صفحة كاملة في الدورة الواحدة ثم توقف نظيف.
            assertEquals(20, sweepCalls)
            assertEquals(200L, prefs.getTombstoneSweepCursor())
            assertFalse(prefs.isTombstoneSweepDone())
            // دورة الدلتا نفسها لم تتأثر: المؤشر الرئيسي تقدم عادياً.
            assertEquals(4_001L, prefs.getLastPullCursor())
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    @Test
    fun freshDeviceSkipsTombstoneSweepEntirely() = runBlocking {
        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("fresh-device")
        prefs.saveLastPullCursor(0L)
        prefs.saveSyncEpoch("parity")
        prefs.setFullReplayPending(true)

        val requests = mutableListOf<PullRequest>()
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, args ->
            check(method.name == "pull")
            requests.add(PullRequest(args!![0] as Long, args[2] as String?, args[5] as String?))
            callOf(Response.success(WorkerPullResponse(
                changes = emptyList(), cursor = "10", epoch = "parity", hasMore = false,
                remaining = null, errors = emptyList(), serverTime = null
            )))
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            manager(prefs, api, scope).pullOnly()
            assertTrue(requests.none { it.tombstonesOnly == "1" })
            assertFalse(prefs.isTombstoneSweepDone())
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    // ─── 2) حراس المؤشر المسموم ──────────────────────────────────

    @Test
    fun poisonedStoredCursorIsResetToZeroBeforePulling() = runBlocking {
        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("poison-device")
        prefs.saveLastPullCursor(3_000_000_000L)
        prefs.setFullSyncComplete(true)
        prefs.setFullReplayPending(false)

        val requestedCursors = mutableListOf<Long>()
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, args ->
            check(method.name == "pull")
            requestedCursors.add(args!![0] as Long)
            callOf(Response.success(WorkerPullResponse(
                changes = emptyList(), cursor = "1799999999", epoch = "parity", hasMore = false,
                remaining = null, errors = emptyList(), serverTime = 1_800_000_000.0
            )))
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val subject = manager(prefs, api, scope)
            assertTrue(subject.sanitizeStoredCursorIfNeeded())
            assertTrue(subject.pullOnly() >= 0)
            // السحب بدأ من الصفر بعد التصفير — لا من المؤشر المسموم.
            assertEquals(0L, requestedCursors.first())
            assertEquals(1_799_999_999L, prefs.getLastPullCursor())
            assertTrue(prefs.getSyncErrorHistory().any { it.operation == "pull_cursor_poisoned" })
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    @Test
    fun serverCursorAheadOfServerTimeIsRejectedWithoutApplyingThePage() = runBlocking {
        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("guard-device")
        prefs.saveLastPullCursor(1_000L)
        prefs.saveSyncEpoch("parity")
        prefs.setFullReplayPending(false)
        prefs.setTombstoneSweepDone(true)

        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            check(method.name == "pull")
            callOf(Response.success(WorkerPullResponse(
                changes = listOf(roomPayload("poisoned-page", "PZ-1", updatedAt = 99_999_999_999L)),
                cursor = "99999999999", epoch = "parity", hasMore = false,
                remaining = null, errors = emptyList(), serverTime = 1_800_000_000.0
            )))
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val subject = manager(prefs, api, scope)
            assertEquals(-1, subject.pullOnly())
            // لا تقدم للمؤشر ولا تطبيق لصفوف الصفحة المسمومة.
            assertEquals(1_000L, prefs.getLastPullCursor())
            assertNull(db.roomsDao().getByLocalUuid("poisoned-page"))
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    @Test
    fun pendingCursorAboveFixedBoundIsNeverInstalledWhenWorkerOmitsServerTime() = runBlocking {
        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("guard-device")
        prefs.saveLastPullCursor(500L)
        prefs.saveSyncEpoch("parity")
        prefs.setFullReplayPending(false)
        prefs.setTombstoneSweepDone(true)

        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            check(method.name == "pull")
            callOf(Response.success(WorkerPullResponse(
                changes = emptyList(), cursor = "3000000000", epoch = "parity", hasMore = false,
                remaining = null, errors = emptyList(), serverTime = null
            )))
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val subject = manager(prefs, api, scope)
            subject.pullOnly()
            // حارس التثبيت النهائي: لا يُخزَّن مؤشر فوق الحد الثابت أبداً.
            assertEquals(0L, prefs.getLastPullCursor())
            assertTrue(prefs.isFullReplayPending())
            assertTrue(prefs.getSyncErrorHistory().any { it.operation == "pull_cursor_install_blocked" })
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    // ─── 3) السحب المُشغَّل بحدث Realtime ─────────────────────────

    @Test
    fun realtimeTriggeredPullIsDeltaOnlyAndNeverPushes() = runBlocking {
        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("realtime-device")
        prefs.saveLastPullCursor(2_000L)
        prefs.saveSyncEpoch("parity")
        prefs.setFullReplayPending(false)
        prefs.setTombstoneSweepDone(true)

        val requests = mutableListOf<PullRequest>()
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, args ->
            check(method.name == "pull") { "حدث Realtime يجب ألا يدفع/يستخدم مساراً آخر: ${method.name}" }
            requests.add(PullRequest(args!![0] as Long, args[2] as String?, args[5] as String?))
            callOf(Response.success(WorkerPullResponse(
                changes = emptyList(), cursor = "2001", epoch = "parity", hasMore = false,
                remaining = null, errors = emptyList(), serverTime = null
            )))
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val subject = manager(prefs, api, scope)
            assertTrue(subject.pullOnRealtimeEvent())
            assertEquals(1, requests.size)
            assertEquals(2_000L, requests.single().cursor)
            assertEquals("realtime-device", requests.single().excludeDevice)
            assertEquals(2_001L, prefs.getLastPullCursor())
            assertTrue(prefs.getLastPullTs() > 0L)
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    @Test
    fun realtimeTriggeredPullSkipsSilentlyWhileAnotherSyncRuns() = runBlocking {
        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("realtime-device")
        prefs.saveLastPullCursor(0L)
        prefs.saveSyncEpoch("parity")
        prefs.setFullReplayPending(false)

        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        var pulls = 0
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            check(method.name == "pull")
            pulls++
            Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, callMethod, _ ->
                check(callMethod.name == "execute")
                started.countDown()
                check(release.await(15, TimeUnit.SECONDS)) { "لم يُحرَّر السحب الجاري" }
                Response.success(WorkerPullResponse(
                    changes = emptyList(), cursor = "10", epoch = "parity", hasMore = false,
                    remaining = null, errors = emptyList(), serverTime = null
                ))
            } as Call<*>
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val subject = manager(prefs, api, scope)
        val running = launch(start = CoroutineStart.UNDISPATCHED) { subject.pullOnly() }
        try {
            assertTrue("وصل السحب الجاري للشبكة", started.await(15, TimeUnit.SECONDS))
            // مزامنة جارية → الحدث يتخطى بصمت بلا انتظار ولا طلب ثانٍ.
            assertFalse(subject.pullOnRealtimeEvent())
            assertEquals(1, pulls)
        } finally {
            release.countDown()
            running.cancelAndJoin()
            withTimeout(15_000) { subject.syncState.first { !it.isSyncing } }
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }
}
