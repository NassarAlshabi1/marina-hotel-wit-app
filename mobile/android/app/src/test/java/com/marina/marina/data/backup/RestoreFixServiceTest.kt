package com.marina.marina.data.backup

import android.app.Application
import android.content.Context
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.lifecycle.ViewModelStore
import com.marina.marina.presentation.settings.backup.BackupViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.entity.BookingEntity
import com.marina.marina.data.local.entity.RoomEntity
import java.io.File
import java.util.zip.GZIPOutputStream
import com.google.gson.Gson
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class RestoreFixServiceTest {
    private lateinit var db: AppDatabase
    private lateinit var context: Context
    private var bookingId = 0L
    private var roomId = 0L
    private lateinit var originalBooking: BookingEntity
    private lateinit var originalRoom: RoomEntity
    private val onQuery = AtomicReference<((String) -> Unit)?>(null)

    @Before
    fun setUp() = runBlocking {
        context = ApplicationProvider.getApplicationContext()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .setQueryCallback(object : RoomDatabase.QueryCallback {
                override fun onQuery(sqlQuery: String, bindArgs: List<Any?>) {
                    onQuery.get()?.invoke(sqlQuery)
                }
            }, { it.run() })
            .build()
        roomId = db.roomsDao().insert(RoomEntity(
            roomNumber = "101", type = "test", price = 100.0, status = "محجوزة", localUuid = "test-room"
        ))
        bookingId = db.bookingsDao().insert(BookingEntity(
            roomNumber = "101", guestName = "اختبار", guestPhone = "", guestNationality = "يمني",
            checkinDate = "2020-01-01T14:01:00", checkoutDate = "2020-01-03T14:01:00",
            status = "نشط", localUuid = "test-booking", calculatedNights = 0, expectedNights = 0
        ))
        originalBooking = db.bookingsDao().getById(bookingId)!!
        originalRoom = db.roomsDao().getById(roomId)!!
    }

    @After
    fun tearDown() {
        onQuery.set(null)
        db.close()
    }

    @Test
    fun successCommitsRepairsAndBothAuditRecordsTogether() = runBlocking {
        val report = RestoreFixService(db).runAutoFixAfterRestore()
        report.requireSuccess()
        assertEquals(1, report.bookingsFixed)
        assertEquals(1, report.paymentsRecalculated)
        val booking = db.bookingsDao().getById(bookingId)!!
        // Reaching 14:01 exactly starts the third billed hotel night (existing contract).
        assertEquals(3, booking.calculatedNights)
        assertEquals(3, booking.expectedNights)
        assertEquals(300.0, booking.totalDueCached, 0.001)
        assertEquals(300.0, booking.remainingBalanceCached, 0.001)
        assertEquals("شاغرة", db.roomsDao().getById(roomId)!!.status)
        val run = db.autoFixRunsDao().getAllOnce().single()
        assertEquals("completed", run.status)
        assertEquals((report.bookingsFixed + report.roomsUpdated).toLong(), run.fixesApplied)
        assertEquals(run.runUuid, db.restoreFixLogDao().getAllOnce().single().fixId)
    }

    @Test
    fun roomFailureRollsBackEarlierBookingAndDetailLogWrites() = runBlocking {
        rejectRoomUpdate()
        val report = RestoreFixService(db).runAutoFixAfterRestore()
        assertFalse(report.success)
        assertEquals(0, report.bookingsFixed)
        assertEquals(0, report.roomsUpdated)
        assertEquals(0, report.paymentsRecalculated)
        assertTrue(report.error.orEmpty().contains("room failure"))
        assertOriginalRows()
        val run = db.autoFixRunsDao().getAllOnce().single()
        assertEquals("failed", run.status)
        assertEquals(0L, run.fixesApplied)
    }

    @Test
    fun failureToWriteSuccessAuditAlsoRollsBackRepairs() = runBlocking {
        db.openHelper.writableDatabase.execSQL(
            "CREATE TRIGGER reject_success BEFORE INSERT ON auto_fix_runs " +
                "WHEN NEW.status = 'completed' BEGIN SELECT RAISE(ABORT, 'audit failure'); END"
        )
        val report = RestoreFixService(db).runAutoFixAfterRestore()
        assertFalse(report.success)
        assertOriginalRows()
        assertEquals("failed", db.autoFixRunsDao().getAllOnce().single().status)
    }

    @Test
    fun auditFailureDoesNotMaskOriginalRepairFailure() = runBlocking {
        rejectRoomUpdate()
        db.openHelper.writableDatabase.execSQL(
            "CREATE TRIGGER reject_audit BEFORE INSERT ON auto_fix_runs " +
                "BEGIN SELECT RAISE(ABORT, 'audit failure'); END"
        )
        val report = RestoreFixService(db).runAutoFixAfterRestore()
        assertFalse(report.success)
        assertTrue(report.error.orEmpty().contains("room failure"))
        assertTrue(report.error.orEmpty().contains("audit failure"))
        assertOriginalRows()
        assertTrue(db.autoFixRunsDao().getAllOnce().isEmpty())
    }

    @Test
    fun cancellationAfterBookingWriteRollsBackAndIsNotReportedAsFailure() = runBlocking {
        val reachedRooms = AtomicBoolean(false)
        val repair = async(start = CoroutineStart.LAZY) { RestoreFixService(db).runAutoFixAfterRestore() }
        onQuery.set { sql ->
            if (sql.startsWith("UPDATE rooms SET status")) {
                reachedRooms.set(true)
                repair.cancel()
            }
        }
        repair.start()
        try {
            repair.await()
            fail("Cancellation must propagate")
        } catch (_: CancellationException) {
            repair.join()
        } finally {
            onQuery.set(null)
        }
        assertTrue("Cancellation must happen after booking repair started", reachedRooms.get())
        assertOriginalRows()
        assertTrue(db.autoFixRunsDao().getAllOnce().isEmpty())
    }

    @Test
    fun rawSqliteRestoreIsRejectedWithoutChangingSourceOrLiveRows() = runBlocking {
        val backup = File(context.cacheDir, "unsafe-restore.sqlite")
        backup.writeText("not a database")
        try {
            val service = LocalBackupService(context, db, BackupSettingsStore(context))
            try {
                service.restoreFromLocalBackup(backup.absolutePath)
                fail("Raw replacement of an open database must be blocked")
            } catch (error: IllegalStateException) {
                assertTrue(error.message.orEmpty().contains("SQLite"))
            }
            assertEquals("not a database", backup.readText())
            assertOriginalRows()
        } finally {
            backup.delete()
        }
    }

    @Test
    fun generatedJsonBackupRoundTripsThroughPublicBackupAndRestoreMethods() = runBlocking {
        val service = LocalBackupService(context, db, BackupSettingsStore(context))
        val backup = File(service.createLocalBackup(BackupFormat.JSON))
        try {
            assertTrue(backup.name.endsWith(".json.gz"))
            db.roomsDao().update(originalRoom.copy(price = 999.0))
            service.restoreFromLocalBackup(backup.absolutePath)
            assertOriginalRows()
        } finally {
            backup.delete()
        }
    }

    @Test
    fun validJsonAndGzipBackupsRestoreRowsWithoutChangingOtherTables() = runBlocking {
        val service = LocalBackupService(context, db, BackupSettingsStore(context))
        for (extension in listOf("json", "json.gz")) {
            val changed = originalRoom.copy(price = 125.0, cleaningStatus = "dirty")
            // Backup JSON contains database column maps, not Room entities with inherited fields.
            val row = db.openHelper.writableDatabase.query("SELECT * FROM rooms WHERE id = $roomId").use { cursor ->
                check(cursor.moveToFirst())
                cursor.columnNames.mapIndexed { index, name ->
                    name to when (cursor.getType(index)) {
                        android.database.Cursor.FIELD_TYPE_NULL -> null
                        android.database.Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(index)
                        android.database.Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(index)
                        else -> cursor.getString(index)
                    }
                }.toMap().toMutableMap()
            }
            row["price"] = changed.price
            row["cleaning_status"] = changed.cleaningStatus
            val json = Gson().toJson(mapOf("rooms" to listOf(row)))
            val backup = File(context.cacheDir, "valid-restore.$extension")
            try {
                if (extension.endsWith("gz")) {
                    GZIPOutputStream(backup.outputStream()).use { it.write(json.toByteArray(Charsets.UTF_8)) }
                } else {
                    backup.writeText(json)
                }
                service.restoreFromLocalBackup(backup.absolutePath)
                assertEquals(changed, db.roomsDao().getById(roomId))
                assertEquals(originalBooking, db.bookingsDao().getById(bookingId))
                db.roomsDao().update(originalRoom)
            } finally {
                backup.delete()
            }
        }
    }

    @Test
    fun reportsAndMaintenancePreimagesAreRejectedWithoutChangingData() = runBlocking {
        val service = LocalBackupService(context, db, BackupSettingsStore(context))
        val backup = File(context.cacheDir, "not-a-data-backup.json")
        try {
            for (json in listOf("{}", "{\"metadata\":{}}", "{\"patches\":[]}", "{\"summary\":{}}")) {
                backup.writeText(json)
                try {
                    service.restoreFromLocalBackup(backup.absolutePath)
                    fail("Non-backup JSON must be rejected before post-restore processing")
                } catch (expected: IllegalArgumentException) {
                    assertTrue(expected.message.orEmpty().contains("نسخة بيانات"))
                }
                assertEquals(originalBooking, db.bookingsDao().getById(bookingId))
                assertEquals(originalRoom, db.roomsDao().getById(roomId))
            }
        } finally {
            backup.delete()
        }
    }

    @Test
    fun invalidJsonRowsOrTableTypesNeverSilentlyDeleteExistingData() = runBlocking {
        val service = LocalBackupService(context, db, BackupSettingsStore(context))
        val backup = File(context.cacheDir, "invalid-rows.json")
        try {
            for (json in listOf(
                """{"rooms":[42]}""", """{"rooms":null}""",
                """{"rooms":[],"bookings":[{}]}""", """{"rooms":[],"sync_state":"bad"}"""
            )) {
                backup.writeText(json)
                try {
                    service.restoreFromLocalBackup(backup.absolutePath)
                    fail("Malformed backup must be rejected: $json")
                } catch (_: IllegalArgumentException) {
                    assertOriginalRows()
                }
            }
        } finally {
            backup.delete()
        }
    }

    @Test
    fun cancellationDuringJsonImportRollsBackEarlierTableDeletion() = runBlocking {
        val backup = File(context.cacheDir, "cancel-import.json").apply {
            writeText("""{"rooms":[],"bookings":[]}""")
        }
        val service = LocalBackupService(context, db, BackupSettingsStore(context))
        val reachedDelete = AtomicBoolean(false)
        val restore = async(start = CoroutineStart.LAZY) { service.restoreFromLocalBackup(backup.absolutePath) }
        onQuery.set { sql ->
            if (sql.startsWith("DELETE FROM \"rooms\"")) {
                reachedDelete.set(true)
                restore.cancel()
            }
        }
        try {
            restore.start()
            try {
                restore.await()
                fail("Cancellation must propagate")
            } catch (_: CancellationException) {
                restore.join()
            }
            assertTrue(reachedDelete.get())
            assertOriginalRows()
        } finally {
            onQuery.set(null)
            backup.delete()
        }
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun viewModelDoesNotReportSuccessWhenPostImportRepairFails() = runBlocking {
        rejectRoomUpdate()
        val backup = File(context.cacheDir, "repair-failure.json").apply { writeText("{\"expenses\":[]}") }
        val store = ViewModelStore()
        Dispatchers.setMain(UnconfinedTestDispatcher())
        try {
            val viewModel = BackupViewModel(
                LocalBackupService(context, db, BackupSettingsStore(context)),
                RestoreFixService(db), FullDatabaseExportService(context, db)
            )
            store.put("backup", viewModel)
            withTimeout(15_000) { viewModel.state.first { !it.isWorking } }
            val snackbar = async(start = CoroutineStart.UNDISPATCHED) { viewModel.snackbars.first() }
            viewModel.restoreFromLocalBackup(backup.absolutePath)
            val state = withTimeout(15_000) { viewModel.state.first { it.status == BackupStatus.ERROR } }
            assertTrue(state.message.orEmpty().contains("فشل الإصلاح اللاحق"))
            assertEquals("فشلت الاستعادة", withTimeout(15_000) { snackbar.await() }.text)
            assertOriginalRows()
        } finally {
            store.clear()
            Dispatchers.resetMain()
            backup.delete()
        }
    }

    private fun rejectRoomUpdate() {
        db.openHelper.writableDatabase.execSQL(
            "CREATE TRIGGER reject_room BEFORE UPDATE ON rooms " +
                "BEGIN SELECT RAISE(ABORT, 'room failure'); END"
        )
    }

    private suspend fun assertOriginalRows() {
        assertEquals(originalBooking, db.bookingsDao().getById(bookingId))
        assertEquals(originalRoom, db.roomsDao().getById(roomId))
        assertTrue(db.restoreFixLogDao().getAllOnce().isEmpty())
    }
}
