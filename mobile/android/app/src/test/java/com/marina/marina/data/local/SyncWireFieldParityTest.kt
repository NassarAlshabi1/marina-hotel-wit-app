package com.marina.marina.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.CloudflareWorkerApi
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.remote.WorkerPullResponse
import com.marina.marina.data.repository.BookingDerivedRefreshService
import com.marina.marina.data.repository.OutboxRepository
import com.marina.marina.data.repository.SyncIngestorRegistry
import com.marina.marina.data.repository.SyncManager
import com.marina.marina.data.sync.SyncOperationRunner
import com.marina.marina.di.EncryptedSharedPreferencesManager
import java.lang.reflect.Proxy
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import retrofit2.Call
import retrofit2.Response

/**
 * حماية «الحقول تُسحب فعلاً» — العطل المُبلَّغ (2026-10-06): «مزامنة delta لا
 * تسحب الجداول أو الحقول».
 *
 * القياس الذي كشفه: مقارنة آلية بين أعمدة `worker/schema.sql` (24 كياناً)
 * وأعمدة كيانات Room أظهرت **14 عموداً خادمياً بلا عمود محلي**:
 *
 * | الكيان | السلك (وFlutter Drift) | أندرويد قبل الإصلاح |
 * | --- | --- | --- |
 * | `inventory_items` | `quantity` / `is_active` | `current_quantity` / — |
 * | `inventory_transactions` | `movement_type` / `item_local_uuid` / `user_id` / `user_name` | `transaction_type` / — |
 * | `blacklist` | `guest_name` / `guest_id_number` / `guest_phone` / `is_active` / `added_by` / `added_date` | `name` / `national_id` / `phone` / `active` |
 * | `salary_withdrawals` | `expense_id` | — |
 * | `expenses` | `employee_link_cleared` | — |
 *
 * وأخطرها `inventory_transactions.transaction_type`: عمود NOT NULL محلي بلا
 * مقابل على السلك ⇒ كل صف مخزون يفشل تطبيقه ⇒ `hasFailures` ⇒ **تجميد مؤشر
 * الدلتا** ⇒ «لا تسحب الجداول ولا الحقول» بحرفها.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncWireFieldParityTest {

    private lateinit var db: AppDatabase
    private lateinit var registry: SyncIngestorRegistry

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        registry = newRegistry()
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

    private fun preferences(): SyncPreferences =
        SyncPreferences(EncryptedSharedPreferencesManager(ApplicationProvider.getApplicationContext()))

    private fun callOf(response: Response<*>): Call<*> =
        Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, method, _ ->
            check(method.name == "execute")
            response
        } as Call<*>

    private fun manager(prefs: SyncPreferences, api: CloudflareWorkerApi, scope: CoroutineScope): SyncManager {
        val service = CloudflareSyncService(api, CloudflareConfig(ApplicationProvider.getApplicationContext()), prefs)
        return SyncManager(
            OutboxRepository(db.outboxDao(), service, prefs, registry),
            service, prefs, registry, SyncOperationRunner(scope, Dispatchers.Unconfined),
            BookingDerivedRefreshService(db, db.bookingsDao(), db.roomsDao(), db.paymentsDao(), db.bookingNightsDao())
        )
    }

    /** سجل سلكي كما يُرسله Worker: `_entity` + أسماء أعمدة D1. */
    private fun wire(entity: String, vararg fields: Pair<String, Any?>): Map<String, Any> {
        val base = mutableMapOf<String, Any>("_entity" to entity)
        for ((key, value) in fields) if (value != null) base[key] = value
        return base
    }

    // ─── 1) inventory_items: الكمية والعلم النشط ─────────────────

    @Test
    fun inventoryItemPullMapsWireQuantityIntoCurrentQuantityAndKeepsActiveFlag() = runBlocking {
        val report = registry.ingestPage(
            listOf(
                wire(
                    "inventory_items",
                    "id" to 11, "local_uuid" to "item-1", "name" to "مناشف",
                    "unit" to "قطعة", "category" to "مفروشات",
                    "quantity" to 12, "minimum_quantity" to 3, "is_active" to 0,
                    "created_at" to 1_700_000_000L, "updated_at" to 1_700_000_100L,
                    "last_modified" to 1_700_000_100L
                )
            )
        )
        assertEquals(1, report.applied)
        val item = db.inventoryDao().getItemByName("مناشف")
        assertNotNull(item)
        // قبل الإصلاح: `quantity` يُهمل ⇒ 0.0 دائماً، و`is_active` لا عمود له.
        assertEquals(12.0, item!!.currentQuantity, 0.0)
        assertEquals(3.0, item.minimumQuantity, 0.0)
        assertFalse(item.isActive)
        assertEquals(11L, item.serverId?.toLong())
    }

    // ─── 2) inventory_transactions: نوع الحركة والمنفّذ ───────────

    @Test
    fun inventoryTransactionPullMapsMovementTypeAndKeepsUserFields() = runBlocking {
        registry.ingestPage(
            listOf(
                wire(
                    "inventory_items", "id" to 21, "local_uuid" to "item-7", "name" to "صابون",
                    "quantity" to 40, "created_at" to 1_700_000_000L, "updated_at" to 1_700_000_000L
                )
            )
        )
        val report = registry.ingestPage(
            listOf(
                wire(
                    "inventory_transactions",
                    "id" to 22, "local_uuid" to "tx-1", "item_local_uuid" to "item-7",
                    "item_id" to 999, // رقم محلي على جهاز آخر — يُترجم عبر uuid
                    "movement_type" to "in", "quantity" to 5, "balance_after" to 45,
                    "note" to "توريد", "user_id" to 7, "user_name" to "سالم",
                    "created_at" to 1_700_000_500L, "updated_at" to 1_700_000_500L,
                    "last_modified" to 1_700_000_500L
                )
            )
        )
        assertEquals(1, report.applied)
        val tx = db.inventoryDao().getRecentTransactions(10).first().single()
        // قبل الإصلاح: `movement_type` يُهمل و`transaction_type` NOT NULL ⇒
        // فشل التطبيق ⇒ عزل + تجميد المؤشر.
        assertEquals("in", tx.transactionType)
        assertEquals(5.0, tx.quantity, 0.0)
        assertEquals(45.0, tx.balanceAfter, 0.0)
        assertEquals(7L, tx.userId)
        assertEquals("سالم", tx.userName)
        assertEquals("item-7", tx.itemLocalUuid)
        // الوصلة المحلية الصحيحة إلى الصنف (لا الرقم الوارد من الجهاز الآخر).
        assertEquals(db.inventoryDao().getItemByName("صابون")!!.id, tx.itemId)
        // لا عمود زمني على السلك (`transaction_time`) — يُغذّى من created_at.
        assertEquals(1_700_000_500L, tx.transactionTime)
    }

    /**
     * نظير `movementType: ... ?? 'adjustment'` في `inventory_adapter.dart`
     * (الفرع المرجعي): صف حركة بلا `movement_type` على السلك يأخذ الافتراضي
     * بدل أن يُعزل — لأن العمود المحلي `transaction_type` NOT NULL.
     */
    @Test
    fun inventoryTransactionWithoutMovementTypeFallsBackToAdjustmentLikeDart() = runBlocking {
        registry.ingestPage(
            listOf(
                wire(
                    "inventory_items", "local_uuid" to "item-9", "name" to "شامبو",
                    "quantity" to 3, "created_at" to 1_700_000_000L, "updated_at" to 1_700_000_000L
                )
            )
        )
        val report = registry.ingestPage(
            listOf(
                wire(
                    "inventory_transactions",
                    "local_uuid" to "tx-9", "item_local_uuid" to "item-9",
                    "quantity" to 2, "balance_after" to 5,
                    "created_at" to 1_700_000_600L, "updated_at" to 1_700_000_600L,
                    "last_modified" to 1_700_000_600L
                )
            )
        )
        assertEquals(1, report.applied)
        assertEquals(0, report.failed)
        val tx = db.inventoryDao().getRecentTransactions(10).first().single()
        assertEquals("adjustment", tx.transactionType)
        assertEquals(2.0, tx.quantity, 0.0)
    }

    // ─── 3) blacklist: حقول الضيف ────────────────────────────────

    @Test
    fun blacklistPullMapsGuestFieldsAndKeepsAddedBy() = runBlocking {
        val report = registry.ingestPage(
            listOf(
                wire(
                    "blacklist",
                    "id" to 31, "local_uuid" to "bl-1",
                    "name" to "", // الخادم يملأ NOT NULL بـ'' حين لا يأتي من Flutter
                    "guest_name" to "أحمد صالح", "guest_phone" to "777123456",
                    "guest_id_number" to "00123456", "nationality" to "يمني",
                    "reason" to "عدم سداد", "is_active" to 0,
                    "added_by" to "الاستقبال", "added_date" to "2026-10-01",
                    "created_at" to 1_700_000_000L, "updated_at" to 1_700_000_000L,
                    "last_modified" to 1_700_000_000L
                )
            )
        )
        assertEquals(1, report.applied)
        val row = db.blacklistEntriesDao().getAllOnce().single()
        // قبل الإصلاح: صف فارغ الاسم/الهاتف/الهوية (القيم الخادمية تُهمل).
        assertEquals("أحمد صالح", row.name)
        assertEquals("777123456", row.phone)
        assertEquals("00123456", row.nationalId)
        assertFalse(row.active)
        assertEquals("الاستقبال", row.addedBy)
        assertEquals("2026-10-01", row.addedDate)
    }

    // ─── 4) salary_withdrawals: هوية المصروف المرتبط ─────────────

    @Test
    fun salaryWithdrawalPullKeepsExpenseIdAndUuid() = runBlocking {
        db.employeesDao().insert(
            com.marina.marina.data.local.entity.EmployeeEntity(
                name = "خالد", basicSalary = 0.0, status = "active",
                localUuid = "emp-1", createdAt = 1L, updatedAt = 1L
            )
        )
        val report = registry.ingestPage(
            listOf(
                wire(
                    "salary_withdrawals",
                    "id" to 41, "local_uuid" to "wd-1", "employee_uuid" to "emp-1",
                    "amount" to 500.0, "withdraw_date" to "2026-10-01",
                    "expense_id" to 77, "expense_uuid" to "exp-9",
                    "created_at" to 1_700_000_000L, "updated_at" to 1_700_000_000L,
                    "last_modified" to 1_700_000_000L
                )
            )
        )
        assertEquals(1, report.applied)
        val row = db.salaryWithdrawalsDao().getByLocalUuid("wd-1")
        assertNotNull(row)
        assertEquals(77L, row!!.expenseId)
        assertEquals("exp-9", row.expenseUuid)
    }

    // ─── 5) expenses: علم فكّ الربط لاصق ──────────────────────────

    @Test
    fun expensePullPersistsExplicitUnlinkFlagAndDoesNotRelinkLater() = runBlocking {
        db.employeesDao().insert(
            com.marina.marina.data.local.entity.EmployeeEntity(
                name = "سعيد", basicSalary = 0.0, status = "active",
                localUuid = "emp-2", createdAt = 1L, updatedAt = 1L
            )
        )
        // أولاً: مصروف مرتبط بالموظف.
        registry.ingestPage(
            listOf(
                wire(
                    "expenses", "id" to 51, "local_uuid" to "ex-1", "expense_type" to "سلفة",
                    "description" to "سلفة", "amount" to 100.0, "date" to "2026-10-01",
                    "employee_uuid" to "emp-2", "expense_kind" to "salary_advance",
                    "created_at" to 1_700_000_000L, "updated_at" to 1_700_000_000L,
                    "last_modified" to 1_700_000_000L
                )
            )
        )
        assertNotNull(db.expensesDao().getByLocalUuid("ex-1")!!.employeeUuid)

        // ثانياً: فكّ ربط صريح.
        registry.ingestPage(
            listOf(
                wire(
                    "expenses", "id" to 51, "local_uuid" to "ex-1", "expense_type" to "سلفة",
                    "description" to "سلفة", "amount" to 100.0, "date" to "2026-10-01",
                    "employee_link_cleared" to 1, "expense_kind" to "salary_advance",
                    "created_at" to 1_700_000_000L, "updated_at" to 1_700_000_100L,
                    "last_modified" to 1_700_000_100L
                )
            )
        )
        val unlinked = db.expensesDao().getByLocalUuid("ex-1")!!
        assertNull(unlinked.employeeUuid)
        assertTrue(unlinked.employeeLinkCleared)

        // ثالثاً: حمولة أحدث ولا تحمل العلم ولا ربطاً جديداً (إعادة بث بعد
        // أن فقد الخادم علم الفصل): اللاصق يمنع عودة الربط القديم.
        val restream = registry.ingestPage(
            listOf(
                wire(
                    "expenses", "id" to 51, "local_uuid" to "ex-1", "expense_type" to "سلفة",
                    "description" to "سلفة", "amount" to 100.0, "date" to "2026-10-01",
                    "expense_kind" to "salary_advance",
                    "created_at" to 1_700_000_000L, "updated_at" to 1_700_000_200L,
                    "last_modified" to 1_700_000_200L
                )
            )
        )
        assertEquals(1, restream.applied)
        val afterRestream = db.expensesDao().getByLocalUuid("ex-1")!!
        assertTrue(afterRestream.employeeLinkCleared)
        assertNull(afterRestream.employeeUuid)
        assertNull(afterRestream.relatedId)
    }

    // ─── 6) صف غير قابل للتطبيق لا يجمّد الدلتا ───────────────────

    @Test
    fun unappliableRowDoesNotFreezeDeltaCursorAndIsCountedOnce() = runBlocking {
        val prefs = preferences()
        prefs.saveAuthToken("test-worker-token")
        prefs.saveDeviceId("mapping-device")
        prefs.saveLastPullCursor(100L)
        prefs.saveSyncEpoch("parity")
        prefs.setFullReplayPending(false)
        prefs.setTombstoneSweepDone(true)

        val cursor = 1_700_000_100L
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            check(method.name == "pull")
            callOf(Response.success(WorkerPullResponse(
                changes = listOf(
                    // قيمة `expense_kind` غير مسموحة ⇒ ApplyOutcome.Failed
                    wire(
                        "expenses", "id" to 61, "local_uuid" to "ex-bad", "expense_type" to "أخرى",
                        "description" to "صف فاسد", "amount" to 10.0, "date" to "2026-10-01",
                        "expense_kind" to "bogus_kind",
                        "created_at" to cursor, "updated_at" to cursor, "last_modified" to cursor
                    )
                ),
                cursor = cursor.toString(), epoch = "parity", hasMore = false,
                remaining = null, errors = emptyList(), serverTime = null
            )))
        } as CloudflareWorkerApi

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val subject = manager(prefs, api, scope)
            // قبل الإصلاح: استثناء «فشل تطبيق 1 سجلاً» والمؤشر يبقى 100 للأبد.
            assertEquals(0, subject.pullOnly())
            assertEquals(cursor, prefs.getLastPullCursor())
            val quarantined = db.syncQuarantineDao().getAll()
            assertEquals(1, quarantined.size)
            assertEquals("expenses", quarantined.single().entity)
            assertEquals(1, quarantined.single().attempts)
            assertTrue(quarantined.single().firstSeen > 0L)

            // دورة ثانية بنفس الصف الفاسد: العدّاد يتصاعد (محاولة الشفاء ثم
            // الصفحة)، والمؤشر يظل متقدماً ولا تُجمَّد الدلتا.
            subject.pullOnly()
            assertTrue(
                "العدّاد يجب أن يتصاعد مع تكرار الفشل",
                db.syncQuarantineDao().getAll().single().attempts > 1
            )
            assertEquals(cursor, prefs.getLastPullCursor())
        } finally {
            scope.coroutineContext[Job]!!.cancelAndJoin()
        }
    }

    // ─── 7) الشفاء من الحمولة المحفوظة ───────────────────────────

    @Test
    fun quarantineHealsFromStoredPayloadOnceTheCauseDisappears() = runBlocking {
        // صف سليم تماماً لكنه موضوع في الحجر كما لو أن سبباً زائلاً (عمود
        // ناقص في نسخة أقدم / قيمة أصلحها الخادم) عزله سابقاً. دورة الشفاء
        // تُعيد تطبيقه من حمولته بلا أي إعادة سحب من الشبكة — وهذا ما يجعل
        // ترقية التطبيق (التي تضيف أعمدة/تحويلات) تُنقذ الصفوف المعزولة.
        db.syncQuarantineDao().put(
            com.marina.marina.data.local.entity.SyncQuarantineEntity(
                entity = "inventory_items",
                recordKey = "uuid:item-heal",
                payload = com.google.gson.Gson().toJson(
                    wire(
                        "inventory_items", "id" to 71, "local_uuid" to "item-heal",
                        "name" to "شامبو", "quantity" to 9,
                        "created_at" to 1_700_000_000L, "updated_at" to 1_700_000_000L
                    )
                ),
                reason = "legacy_missing_column",
                attempts = 4,
                firstSeen = 1L
            )
        )
        val healed = registry.healQuarantinedBatch()
        assertEquals(1, healed.applied)
        assertEquals(0, db.syncQuarantineDao().count())
        assertEquals(9.0, db.inventoryDao().getItemByName("شامبو")!!.currentQuantity, 0.0)
    }

    @Test
    fun quarantineCapEvictsOldestRecords() = runBlocking {
        for (index in 1..305) {
            db.syncQuarantineDao().put(
                com.marina.marina.data.local.entity.SyncQuarantineEntity(
                    entity = "rooms",
                    recordKey = "uuid:cap-$index",
                    payload = "{}",
                    reason = "test",
                    attempts = 1,
                    firstSeen = index.toLong()
                )
            )
        }
        val evicted = registry.enforceQuarantineCap()
        assertEquals(5, evicted)
        assertEquals(300, db.syncQuarantineDao().count())
        // الأقدم أولاً — البقية الأحدث عمراً.
        assertNull(db.syncQuarantineDao().getAll().firstOrNull { it.recordKey == "uuid:cap-1" })
        assertNotNull(db.syncQuarantineDao().getAll().firstOrNull { it.recordKey == "uuid:cap-305" })
    }
}
