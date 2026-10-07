package com.marina.marina.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.diagnostics.SyncHealthRepository
import com.marina.marina.data.local.entity.SyncQuarantineEntity
import com.marina.marina.data.repository.SyncIngestorRegistry
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
 * عطل مُبلَّغ (2026-10-06): «في شاشة الإعدادات حالة المزامنة لا تُظهر جميع
 * الجداول المزامنة».
 *
 * السبب: `SyncHealthRepository` كانت تسأل قائمة ثابتة من **8** جداول
 * (`rooms, bookings, payments, expenses, debts, employees,
 * salary_withdrawals, inventory_items`) بينما المحرك يسحب **24** كياناً —
 * فبقية الجداول (الليالي، الحجوزات المساعدة، الرواتب كلها، المخزون،
 * المستخدمون، الأجهزة، القائمة السوداء …) لا تظهر إطلاقاً في الشاشة.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncHealthTablesTest {

    private lateinit var db: AppDatabase
    private lateinit var repository: SyncHealthRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = SyncHealthRepository(db)
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun reportListsEverySyncedEntityNotAHandPickedSubset() = runBlocking {
        val report = repository.read()
        val expected = SyncIngestorRegistry.SYNC_ENTITY_TABLES.keys
        assertEquals(expected, report.tables.keys)
        assertEquals(24, report.tables.size)
        // الجداول التي كانت غائبة تماماً عن الشاشة قبل الإصلاح:
        for (missingBefore in listOf(
            "booking_nights", "salary_cycles", "salary_payments", "salary_carry_over_logs",
            "inventory_transactions", "blacklist", "app_users", "devices", "audit_logs"
        )) {
            assertTrue("جدول مفقود من الحالة: $missingBefore", report.tables.containsKey(missingBefore))
        }
        // كل جدول مقروء فعلاً (لا -1) على مخطط سليم.
        assertTrue(report.tables.values.none { it < 0 })
        assertEquals(0L, report.tables["rooms"])
    }

    /**
     * كل جدول في [SyncIngestorRegistry.SYNC_ENTITY_TABLES] موجود فعلاً في
     * المخطط المحلي — بلا هذا الفحص يظل خطأ إملائي واحد يعني «غير متاح»
     * أبدياً في الشاشة (وهو أسوأ من العرض الناقص السابق).
     */
    @Test
    fun everySyncedEntityMapsToARealRoomTable() {
        val tables = mutableSetOf<String>()
        db.openHelper.readableDatabase
            .query("SELECT name FROM sqlite_master WHERE type='table'").use { cursor ->
                while (cursor.moveToNext()) tables += cursor.getString(0)
            }
        val missing = SyncIngestorRegistry.SYNC_ENTITY_TABLES
            .filterValues { it !in tables }
        assertEquals(emptyMap<String, String>(), missing)
    }

    @Test
    fun reportCountsRowsAcrossAllTablesAndQuarantine() = runBlocking {
        db.roomsDao().insert(
            com.marina.marina.data.local.entity.RoomEntity(
                roomNumber = "101", type = "single", price = 100.0,
                status = "شاغرة", localUuid = "room-101", createdAt = 1L, updatedAt = 1L
            )
        )
        db.syncQuarantineDao().put(
            SyncQuarantineEntity("rooms", "uuid:x", "{}", "test", attempts = 2, firstSeen = 5L)
        )
        val report = repository.read()
        assertEquals(1L, report.tables["rooms"])
        assertEquals(1L, report.quarantined)
    }
}
