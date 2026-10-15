package com.marina.marina.data.sync

import android.util.Log
import androidx.room.withTransaction
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.dao.BookingNightsDao
import com.marina.marina.data.local.dao.BookingNotesDao
import com.marina.marina.data.repository.OutboxRepository
import com.marina.marina.di.EncryptedSharedPreferencesManager
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton

/**
 * نظير `BookingChildUuidBackfillService` في الفرع المرجعي
 * (`mobile/lib/services/booking_child_uuid_backfill_service.dart` على
 * `feat/cloudflare-sync-execution`).
 *
 * الأجهزة الأخرى تحلّ الليالي والملاحظات المسحوبة بـ UUID الحجز أولاً.
 * الصفوف المدفوعة قبل تلك القاعدة ارتفعت بلا `booking_uuid_cache` فكانت
 * تُهمل عند السحب. هذه الخدمة تختم الـ UUID على الصفوف المحلية وتدرجها
 * مرة واحدة لإعادة الرفع.
 *
 * الفرق عن Dart: Kotlin يملك عمود `booking_uuid_cache` على `booking_notes`
 * نفسها (مواءمة `nights`/`payments`/`debts`)، فتُعبّأ الملاحظات محلياً
 * أيضاً لا على السلك فقط.
 */
@Singleton
class BookingChildUuidBackfillService @Inject constructor(
    private val db: AppDatabase,
    private val nightsDao: BookingNightsDao,
    private val notesDao: BookingNotesDao,
    private val outboxRepository: OutboxRepository,
    private val preferences: EncryptedSharedPreferencesManager
) {

    /** يعمل مرة واحدة لكل جلسة؛ كل خطوة idempotent (نظير `_applied`). */
    private val applied = AtomicBoolean(false)

    suspend fun runIfNeeded() {
        if (!applied.compareAndSet(false, true)) return
        try {
            val nights = backfillNights()
            val notes = repushNotesOnce()
            if (nights > 0 || notes > 0) {
                Log.d(
                    TAG,
                    "BookingChildUuidBackfill: ليالي=$nights، ملاحظات=$notes " +
                        "أُضيفت إلى طابور الرفع"
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "BookingChildUuidBackfill تعذّر: $e")
        }
    }

    /**
     * يملأ `booking_uuid_cache` على الليالي الناقصة ويدرجها للرفع —
     * `last_modified` لا يُمس (المحتوى لم يتغير ولا يجوز أن تبدو النسخة
     * البعيدة أقدم من المحلية). نظير `backfillNights` حرفياً.
     */
    suspend fun backfillNights(): Int {
        val rows = nightsDao.listMissingBookingUuid()
        if (rows.isEmpty()) return 0
        db.withTransaction {
            for (row in rows) {
                nightsDao.setBookingUuidCache(row.id, row.bookingUuid)
                outboxRepository.enqueue(
                    entity = "booking_nights",
                    op = "update",
                    localUuid = row.localUuid,
                    payload = mapOf("localUuid" to row.localUuid)
                )
            }
        }
        return rows.size
    }

    /**
     * نظير `repushNotesOnce` خلف علم التفضيلات `booking_notes_uuid_repush_v1`:
     * كل ملاحظة حية تُعبّأ بـ UUID حجزها وتُدرج لإعادة الرفع مرة واحدة
     * لتحل محل النسخ البعيدة التي بلا UUID.
     */
    suspend fun repushNotesOnce(): Int {
        if (preferences.getBoolean(NOTES_REPUSH_PREF_KEY, false)) return 0

        val rows = notesDao.listMissingBookingUuid()
        db.withTransaction {
            for (row in rows) {
                notesDao.setBookingUuidCache(row.id, row.bookingUuid)
                outboxRepository.enqueue(
                    entity = "booking_notes",
                    op = "update",
                    localUuid = row.localUuid,
                    payload = mapOf(
                        "localUuid" to row.localUuid,
                        "booking_uuid_cache" to row.bookingUuid
                    )
                )
            }
        }
        preferences.putBoolean(NOTES_REPUSH_PREF_KEY, true)
        return rows.size
    }

    companion object {
        private const val TAG = "BookingChildUuidBackfill"

        /** نفس مفتاح Dart حرفياً. */
        const val NOTES_REPUSH_PREF_KEY = "booking_notes_uuid_repush_v1"
    }
}
