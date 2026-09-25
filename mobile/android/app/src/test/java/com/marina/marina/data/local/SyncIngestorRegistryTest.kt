package com.marina.marina.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.local.entity.BookingEntity
import com.marina.marina.data.local.entity.BookingNightEntity
import com.marina.marina.data.repository.SyncIngestorRegistry
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
}
