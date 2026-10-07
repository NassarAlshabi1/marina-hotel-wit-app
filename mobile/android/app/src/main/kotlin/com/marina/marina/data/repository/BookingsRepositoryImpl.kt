package com.marina.marina.data.repository

import androidx.room.withTransaction
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.data.sync.SyncEpochs
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.repository.BookingsRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class BookingsRepositoryImpl @Inject constructor(
    private val db: AppDatabase,
    private val bookingsDao: BookingsDao,
    private val outboxRepository: OutboxRepository,
    private val derivedRefresh: BookingDerivedRefreshService
) : BookingsRepository {

    override fun getAll(): Flow<List<Booking>> =
        bookingsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override fun watchById(id: Long): Flow<Booking?> =
        bookingsDao.watchById(id).map { it?.toDomain() }

    override suspend fun getById(id: Long): Booking? =
        bookingsDao.getById(id)?.toDomain()

    override suspend fun insert(booking: Booking): Long {
        // Dart bookings_repository.dart l.56-65 — reject a second active booking
        // for a room that already has one.
        assertNoConflictingActiveBooking(booking.roomNumber, excludeId = null)
        // ✅ (2026-10-06) الطوابع بالثواني — نظير `bookings_dao.dart:insertOne`
        // (`createdAt/updatedAt/lastModified = Time.nowEpoch()`)، ونموذج
        // المجال لا يحمل `last_modified` أصلاً فكان يُكتب صفراً ⇒ يفوز صف
        // الخادم الأقدم على تعديلنا في «آخر كتابة تفوز».
        val now = SyncEpochs.nowSeconds()
        val prepared = booking.copy(
            localUuid = booking.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (booking.createdAt == 0L) now else booking.createdAt,
            updatedAt = now
        )
        // معاملة واحدة: الصف + outbox + الحقول المشتقة. Dart يفعل الثلاثة داخل
        // `db.transaction` (bookings_repository.dart create l.78-99) — والتجزئة
        // إلى كتابتين منفصلتين تُظهر للمراقبين (Flow) لحظةً تكون فيها الحقول
        // المشتقة قديمة قبل تحديثها.
        return db.withTransaction {
            val id = bookingsDao.insert(
                prepared.toEntity().copy(lastModified = now, lastModifiedEpoch = now)
            )
            outboxRepository.enqueueObject("bookings", "insert", prepared.localUuid, stripComputed(prepared))
            // نفس خدمة إعادة البناء التي يستدعيها السحب بعد الدورة — مصدر وحيد
            // للحقيقة في الحساب (لا نسخة ثانية قابلة للانحراف).
            derivedRefresh.refreshForBookingId(id)
            id
        }
    }

    override suspend fun update(booking: Booking) {
        // Dart bookings_repository.dart l.147-156 — the same guard applies when a
        // booking is moved onto a room that already hosts another active booking.
        assertNoConflictingActiveBooking(booking.roomNumber, excludeId = booking.id)
        // ✅ نظير `bookings_dao.dart:updateById`: updatedAt/lastModified = ثوانٍ
        // و`version = existing.version + 1` (كاسر التعادل في الـ Worker عند
        // تساوي updated_at). هذا هو مسار «إنهاء الحجز (مكتمل)» في التطبيق.
        val now = SyncEpochs.nowSeconds()
        val existing = bookingsDao.getById(booking.id)
        val prepared = booking.copy(updatedAt = now)
        // نفس عقد create: كتابة + outbox + إعادة بناء المشتقات في معاملة واحدة
        // (bookings_repository.dart update l.205-227).
        db.withTransaction {
            bookingsDao.update(
                prepared.toEntity().copy(
                    localUuid = prepared.localUuid.ifBlank { existing?.localUuid.orEmpty() },
                    createdAt = if (prepared.createdAt == 0L) (existing?.createdAt ?: now) else prepared.createdAt,
                    lastModified = now,
                    lastModifiedEpoch = now,
                    version = (existing?.version ?: prepared.version) + 1
                )
            )
            outboxRepository.enqueueObject("bookings", "update", prepared.localUuid, stripComputed(prepared))
            derivedRefresh.refreshForBookingId(prepared.id)
        }
    }

    /**
     * Dart derived-fields refresh with `enqueueOutbox: false`
     * (booking_payment_screen.dart l.210-219): opening a payment screen must
     * refresh the cached financials WITHOUT enqueueing a cloud change.
     */
    override suspend fun updateComputedFields(booking: Booking) {
        val prepared = booking.copy(updatedAt = System.currentTimeMillis())
        bookingsDao.update(prepared.toEntity())
    }

    override suspend fun checkout(id: Long, status: String, actualCheckout: String?) {
        val now = System.currentTimeMillis()
        bookingsDao.checkout(id, status, actualCheckout, updatedAt = now, lastModified = now)
    }

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        bookingsDao.softDelete(id, deletedAt = now, updatedAt = now, lastModified = now)
    }

    override suspend fun getActiveBookingForRoom(roomNumber: String): Booking? =
        bookingsDao.getActiveBookingForRoom(roomNumber)?.toDomain()

    // ---------------------------------------------------------------------------
    // Dart behavioural contracts
    // ---------------------------------------------------------------------------

    /**
     * Dart StateError text: `يوجد حجز نشط بالفعل للغرفة N (الضيف: X)` — surfaces
     * as a red snackbar in the booking editor.
     */
    private suspend fun assertNoConflictingActiveBooking(roomNumber: String, excludeId: Long?) {
        if (roomNumber.isBlank()) return
        val active = bookingsDao.getActiveBookingForRoom(roomNumber) ?: return
        if (excludeId != null && active.id == excludeId) return
        val guest = active.guestName.ifBlank { "غير معروف" }
        error("يوجد حجز نشط بالفعل للغرفة $roomNumber (الضيف: $guest)")
    }

    /**
     * إعادة بناء الحقول المشتقة لحجز واحد — مُفوَّض إلى
     * [BookingDerivedRefreshService] (نفس ما ينفّذه السحب بعد الدورة،
     * ونفس ما ينفّذه `BookingDerivedFieldsService.refreshForBookingId` في Dart).
     *
     * كان حساباً داخلياً هنا؛ نُقل ليكون مصدراً وحيداً يمنع انحراف نسختين
     * (فخ يعرفه المشروع: نفس المنطق في مكانين).
     */
    internal suspend fun refreshFinancialCache(id: Long) {
        derivedRefresh.refreshForBookingId(id)
    }

    /**
     * Dart `HotelTimeEngine.stripComputedFields` (hotel_time_engine.dart
     * l.319-346): the 12 cached/computed booking fields are LOCAL caches and
     * must never be pushed to the cloud (each device recomputes its own).
     */
    private fun stripComputed(booking: Booking): Booking = booking.copy(
        calculatedNights = 1,
        totalNightsCached = 0,
        isOverdue = false,
        needsCheckoutReview = false,
        totalDueCached = 0.0,
        totalPaidCached = 0.0,
        remainingBalanceCached = 0.0,
        isFullyPaid = false,
        hotelDayCheckin = null,
        hotelDayCheckout = null
    )
}
