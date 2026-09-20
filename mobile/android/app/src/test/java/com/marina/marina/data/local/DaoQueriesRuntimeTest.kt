package com.marina.marina.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
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
 * Targeted runtime coverage for the DAO surface added while making the Kotlin
 * port compile again:
 *
 *  - `fc8e30c6` removed the duplicate trailing comma in AppUserEntity/DeviceInfoEntity.
 *  - `4c910564` pointed the sync_log indices at real columns (kapt/Room failure).
 *  - `ddc8f2ba` declared 12 DAO methods the repositories were already calling.
 *
 * Compile-time Room verification only proves the SQL parses and refers to
 * existing columns. This test opens the REAL schema on SQLite and executes
 * every newly added query, which also pins the `SUM(...)`/`COALESCE` return
 * contract (`sumByType` must return 0.0 — never null — on an empty table).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DaoQueriesRuntimeTest {

    private lateinit var db: AppDatabase

    @Before
    fun openInMemoryDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
    }

    @After
    fun closeDatabase() {
        db.close()
    }

    /** Schema-level assertions for the two porting bugs fixed on this branch. */
    @Test
    fun schemaExposesFixedColumnsAndSyncLogIndices() {
        // 4c910564 — Room rejects @Index columns that do not exist in the entity.
        db.openHelper.writableDatabase
            .query("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_sync_log_created'")
            .use { cursor -> assertEquals(1, cursor.count) }

        db.openHelper.writableDatabase
            .query("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_sync_log_sync_id'")
            .use { cursor -> assertEquals(1, cursor.count) }

        db.openHelper.writableDatabase
            .query("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_sync_log_device_id'")
            .use { cursor -> assertEquals(1, cursor.count) }

        // fc8e30c6 — the fields whose `,,` broke compilation, addressed by column.
        db.openHelper.writableDatabase.query("SELECT role FROM app_users LIMIT 0").use { }
        db.openHelper.writableDatabase.query("SELECT last_active FROM devices LIMIT 0").use { }
    }

    /** Every DAO method added in ddc8f2ba must execute against real SQLite. */
    @Test
    fun addedQueriesExecuteOnEmptyDatabase() {
        runBlocking {
            // BlacklistEntriesDao
            assertTrue(db.blacklistEntriesDao().getActive().first().isEmpty())
            assertTrue(db.blacklistEntriesDao().searchActive("%علي%").first().isEmpty())

            // BookingNightsDao
            assertTrue(db.bookingNightsDao().getByBooking(bookingId = 1L).isEmpty())
            db.bookingNightsDao().deleteByBooking(bookingId = 1L)

            // BookingPriceAdjustmentsDao
            assertTrue(
                db.bookingPriceAdjustmentsDao().getActiveByBooking(bookingUuid = "missing-uuid").isEmpty()
            )

            // CashTransactionsDao — sumByType must be non-null (COALESCE contract).
            assertTrue(db.cashTransactionsDao().getByType(type = "income").first().isEmpty())
            assertEquals(0.0, db.cashTransactionsDao().sumByType(type = "income"), 0.0001)

            // GuestInfosDao
            assertTrue(db.guestInfosDao().search(pattern = "%101%").first().isEmpty())
            assertTrue(db.guestInfosDao().getByRoom(roomNumber = "101").isEmpty())

            // PaymentVoidsDao
            assertTrue(db.paymentVoidsDao().getByBooking(bookingUuid = "missing-uuid").isEmpty())

            // SalaryCyclesDao / SalaryPaymentsDao
            assertNull(db.salaryCyclesDao().getByKey(cycleKey = "2026-09"))
            assertTrue(db.salaryPaymentsDao().getByCycle(cycleId = 1L).isEmpty())
        }
    }
}
