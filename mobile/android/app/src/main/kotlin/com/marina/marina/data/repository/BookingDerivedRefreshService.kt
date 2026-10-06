package com.marina.marina.data.repository

import android.util.Log
import androidx.room.withTransaction
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.dao.BookingNightsDao
import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.util.BookingFinancials
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException

/**
 * إعادة بناء الحقول المشتقة للحجوزات («الإجماليات المخزَّنة») بعد السحب —
 * نظير `BookingDerivedFieldsService` في Flutter عند استدعائه من
 * `CloudflareSyncManager._refreshDerivedAfterPull`
 * (`booking_derived_fields_service.dart` + `cloudflare_sync_manager.dart`
 * l.3780 في فرع `feat/cloudflare-sync-execution`).
 *
 * **لماذا بعد كل سحب:** الليالي (`booking_nights`) والإجماليات المخزَّنة
 * (`calculated_nights` / `total_due_cached` / `total_paid_cached` /
 * `remaining_balance_cached` / `is_fully_paid`) تُحسب محلياً على كل جهاز.
 * فسحب `payments` أو `booking_nights` أو `booking_price_adjustments` من جهاز
 * آخر دون إعادة حساب يترك هذا الجهاز بأرقام قديمة (شاشة الدفعات وقائمة
 * الحجوزات والبحث الشامل تقرأ المخزَّن).
 *
 * **بلا رفع:** الحقول المشتقة لا تُرفع ولا تُسجَّل في الـoutbox —
 * وإلا حلقة سحب/رفع لا نهائية (نظير `enqueueOutbox: false` في Dart). الكتابة
 * هنا عبر [BookingsDao.updateFinancialCache] التي لا تمس بيانات المزامنة
 * (`last_modified` / `updated_at`) ولا تدرج في الـoutbox.
 *
 * **شبكة الكيانات المؤثرة** [DERIVED_REFRESH_ENTITIES] منقولة حرفياً من
 * `_derivedRefreshEntities` في Dart، والبوابة [`affectsDerived`] تناظر شرط
 * `pulledDerivedEntities.isNotEmpty && totalPulled > 0`.
 *
 * الفرق المقصود الوحيد: Dart يعيد الحساب لكل **الحقول المشتقة** الاثني عشر
 * (منها `isOverdue` و`needsCheckoutReview` و`hotel_day_checkin/out`)، وأندرويد
 * يعيد الحساب للأعمدة المخزَّنة الخمسة التي تقرأها واجهاته فعلاً (تحقّق بحثاً
 * في طبقة `presentation`: لا قارئ لـ`isOverdue`/`needsCheckoutReview` في الحجز).
 * التوسيع لاحقاً لا يغيّر هذا العقد — يُضاف عمود لاستعلام [BookingsDao.updateFinancialCache].
 */
@Singleton
class BookingDerivedRefreshService @Inject constructor(
    private val db: AppDatabase,
    private val bookingsDao: BookingsDao,
    private val roomsDao: RoomsDao,
    private val paymentsDao: PaymentsDao,
    private val nightsDao: BookingNightsDao
) {

    /**
     * حارس إعادة الدخول — نظير `_derivedRefreshRunning` في Dart: دورة سحب لا
     * تنتظر أخرى في إعادة البناء (لا طابور تراكمي عند دورات متلاحقة).
     */
    private val running = AtomicBoolean(false)

    /**
     * إعادة بناء الحقول المشتقة لكل الحجوزات النشطة — نظير
     * `refreshAllActiveBookings` (Dart l.172).
     *
     * المعاملة واحدة لكل الدفعة (فلسفة Dart الصريحة: «معالجة جميع الحجوزات
     * داخل معاملة واحدة لتفادي SQLITE_BUSY»)، وفشل حجز واحد لا يُسقط البقية
     * (يُسجَّل ويُتابع — نفس `try/catch` الداخلي في Dart).
     *
     * @return عدد الحجوزات التي أُعيد بناؤها فعلاً.
     */
    suspend fun refreshAllActiveBookings(): Int {
        if (!running.compareAndSet(false, true)) return 0
        try {
            val moment = System.currentTimeMillis()
            val active = bookingsDao.listDerivedRefreshCandidates()
                .filter { StatusUtils.isBookingActive(it.status) }
                .map { it.toDomain() }
            var refreshed = 0
            db.withTransaction {
                for (booking in active) {
                    try {
                        refreshInTransaction(booking, moment)
                        refreshed++
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (error: Exception) {
                        Log.w(TAG, "تعذّر تحديث الحقول المشتقة للحجز ${booking.id}", error)
                    }
                }
            }
            if (refreshed > 0) {
                Log.d(TAG, "أُعيد بناء الحقول المشتقة لـ$refreshed حجز نشط بعد السحب")
            }
            return refreshed
        } finally {
            running.set(false)
        }
    }

    /**
     * إعادة بناء حجز واحد بمعرّفه المحلي — نظير `refreshForBookingId`
     * (Dart l.18). يُستدعى بعد تغييرات محلية على الدفعات (نظير
     * `PaymentsRepositoryImpl` الحالي).
     *
     * @return true إذا أُعيد البناء فعلاً (الحجز موجود وغير محذوف ناعمياً).
     */
    suspend fun refreshForBookingId(id: Long): Boolean {
        val booking = bookingsDao.getById(id)?.toDomain() ?: return false
        val moment = System.currentTimeMillis()
        db.withTransaction { refreshInTransaction(booking, moment) }
        return true
    }

    /**
     * الحساب داخل معاملة قائمة: إجماليات الليالي والإجماليات المخزَّنة من
     * الدفعات والليالي وسعر الغرفة الحاليين.
     *
     * ملاحظة حجز نشط بلا `actual_checkout`: عدد الليالي ينمو مع الزمن
     * («الليلة الجارية تُحسب») — `nightsWithCutoff(checkin, null)` يستخدم
     * `moment` نفسه لتطابق `EnhancedBookingCalculationService(now: moment)` في Dart.
     */
    private suspend fun refreshInTransaction(booking: Booking, moment: Long) {
        val roomRate = roomsDao.getByNumber(booking.roomNumber)?.price ?: 0.0
        val payments = paymentsDao.getByBookingOnce(booking.id).map { it.toDomain() }
        val nights = nightsDao.getByBooking(booking.id).map { it.toDomain() }
        val checkin = HotelTimeEngine.parseDate(booking.checkinDate)
        val liveNights = if (checkin != null) {
            HotelTimeEngine.nightsWithCutoff(
                checkin,
                HotelTimeEngine.parseDate(booking.actualCheckout) ?: moment
            )
        } else {
            booking.calculatedNights
        }
        val summary = BookingFinancials.calculate(
            booking = booking.copy(calculatedNights = liveNights),
            roomRate = roomRate,
            payments = payments,
            nights = nights,
            nowMillis = moment
        )
        bookingsDao.updateFinancialCache(
            id = booking.id,
            nights = liveNights,
            due = summary.totalAmount,
            paid = summary.paidAmount,
            remaining = summary.remainingAmount,
            fullyPaid = summary.isFullyPaid
        )
    }

    companion object {
        private const val TAG = "BookingDerivedRefresh"

        /**
         * الكيانات التي يؤثر صفها المسحوب على الحقول المشتقة للحجوزات —
         * منقولة حرفياً من `CloudflareSyncManager._derivedRefreshEntities`.
         */
        val DERIVED_REFRESH_ENTITIES: Set<String> = setOf(
            "bookings",
            "booking_nights",
            "payments",
            "price_adjustments",
            "booking_price_adjustments",
            "payment_voids"
        )

        /** بوابة القرار: هل يستدعي ما سُحب إعادة بناء؟ (Dart l.2591). */
        fun affectsDerived(pulledEntities: Set<String>): Boolean =
            pulledEntities.any { it in DERIVED_REFRESH_ENTITIES }
    }
}
