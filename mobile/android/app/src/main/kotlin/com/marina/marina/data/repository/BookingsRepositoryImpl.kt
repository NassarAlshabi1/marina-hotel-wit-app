package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.BookingNightsDao
import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.util.BookingFinancials
import com.marina.marina.domain.util.HotelTimeEngine
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

@Singleton
class BookingsRepositoryImpl @Inject constructor(
    private val bookingsDao: BookingsDao,
    private val roomsDao: RoomsDao,
    private val paymentsDao: PaymentsDao,
    private val nightsDao: BookingNightsDao,
    private val outboxRepository: OutboxRepository
) : BookingsRepository {

    override fun getAll(): Flow<List<Booking>> =
        bookingsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun getById(id: Long): Booking? =
        bookingsDao.getById(id)?.toDomain()

    override suspend fun insert(booking: Booking): Long {
        // Dart bookings_repository.dart l.56-65 — reject a second active booking
        // for a room that already has one.
        assertNoConflictingActiveBooking(booking.roomNumber, excludeId = null)
        val now = System.currentTimeMillis()
        val prepared = booking.copy(
            localUuid = booking.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (booking.createdAt == 0L) now else booking.createdAt,
            updatedAt = now
        )
        val withDerived = refreshDerivedFields(prepared)
        val id = bookingsDao.insert(withDerived.toEntity())
        outboxRepository.enqueueObject("bookings", "insert", withDerived.localUuid, stripComputed(withDerived))
        return id
    }

    override suspend fun update(booking: Booking) {
        // Dart bookings_repository.dart l.147-156 — the same guard applies when a
        // booking is moved onto a room that already hosts another active booking.
        assertNoConflictingActiveBooking(booking.roomNumber, excludeId = booking.id)
        val now = System.currentTimeMillis()
        val prepared = booking.copy(updatedAt = now)
        val withDerived = refreshDerivedFields(prepared)
        bookingsDao.update(withDerived.toEntity())
        outboxRepository.enqueueObject("bookings", "update", withDerived.localUuid, stripComputed(withDerived))
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
        throw IllegalStateException("يوجد حجز نشط بالفعل للغرفة $roomNumber (الضيف: $guest)")
    }

    /**
     * Dart derived-fields service (refreshForBookingId) — totalDueCached /
     * totalPaidCached / remainingBalanceCached / isFullyPaid / calculatedNights
     * are recomputed on every create/update so the bookings list shows live
     * financials without opening the payment screen.
     */
    private suspend fun refreshDerivedFields(booking: Booking): Booking {
        val room = roomsDao.getByNumber(booking.roomNumber)
        val roomRate = room?.price ?: 0.0
        val payments = paymentsDao.getByBooking(booking.id).first().map { it.toDomain() }
        val nights = nightsDao.getByBooking(booking.id).map { it.toDomain() }
        val summary = BookingFinancials.calculate(booking, roomRate, payments, nights)
        val checkin = HotelTimeEngine.parseDate(booking.checkinDate)
        val liveNights = if (checkin != null) {
            val checkout = HotelTimeEngine.parseDate(booking.actualCheckout)
            HotelTimeEngine.nightsWithCutoff(checkin, checkout)
        } else booking.calculatedNights
        return booking.copy(
            calculatedNights = liveNights,
            totalDueCached = summary.totalAmount,
            totalPaidCached = summary.paidAmount,
            remainingBalanceCached = summary.remainingAmount,
            isFullyPaid = summary.isFullyPaid
        )
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
