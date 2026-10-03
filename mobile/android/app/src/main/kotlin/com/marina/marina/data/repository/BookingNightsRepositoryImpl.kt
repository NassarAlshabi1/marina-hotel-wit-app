package com.marina.marina.data.repository

import androidx.room.withTransaction
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.dao.BookingNightsDao
import com.marina.marina.data.local.dao.BookingPriceAdjustmentsDao
import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.HotelDayLedgerDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.BookingNight
import com.marina.marina.domain.model.BookingPriceAdjustment
import com.marina.marina.domain.model.HotelDayLedger
import com.marina.marina.domain.repository.BookingNightsRepository
import com.marina.marina.data.local.entity.HotelDayLedgerEntity
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class BookingNightsRepositoryImpl @Inject constructor(
    private val db: AppDatabase,
    private val bookingsDao: BookingsDao,
    private val nightsDao: BookingNightsDao,
    private val adjustmentsDao: BookingPriceAdjustmentsDao,
    private val ledgerDao: HotelDayLedgerDao,
    private val outboxRepository: OutboxRepository
) : BookingNightsRepository {

    override suspend fun getByBooking(bookingId: Long): List<BookingNight> =
        nightsDao.getByBooking(bookingId).map { it.toDomain() }

    /**
     * Replace a booking's nights as a sync-safe diff rather than deleting and
     * recreating every row. The parent UUID is part of every wire payload so
     * the Worker can translate the device-local booking id into its D1 id.
     */
    override suspend fun replaceNights(bookingId: Long, nights: List<BookingNight>) {
        val normalizedNights = nights.map { it.copy(hotelDayKey = it.hotelDayKey.trim()) }
        val dayKeys = normalizedNights.map { it.hotelDayKey }
        require(dayKeys.all { it.isNotEmpty() }) { "كل ليلة تحتاج مفتاح يوم فندقي صالحاً" }
        require(dayKeys.size == dayKeys.toSet().size) { "يوجد أكثر من سجل لليلة الحجز نفسها" }

        db.withTransaction {
            val booking = bookingsDao.getById(bookingId)
                ?: throw IllegalArgumentException("لا يمكن مزامنة الليالي: الحجز $bookingId غير موجود")
            val bookingUuid = booking.localUuid.trim()
            require(bookingUuid.isNotEmpty()) {
                "لا يمكن مزامنة ليالي الحجز $bookingId قبل تثبيت local_uuid للحجز"
            }

            val now = System.currentTimeMillis()
            val currentRows = nightsDao.getByBooking(bookingId)
            val currentByDay = currentRows.groupBy { it.hotelDayKey }
            require(currentByDay.values.none { it.size > 1 }) {
                "توجد ليالٍ مكررة محلياً لهذا الحجز؛ أوقف الاستبدال إلى حين مراجعتها"
            }
            val desiredDays = dayKeys.toSet()

            // Deletions must be tombstones in the Outbox; a physical local
            // delete would leave the old D1 nights alive on other devices.
            currentRows.filter { it.hotelDayKey !in desiredDays }.forEach { current ->
                val deleted = current.copy(
                    deletedAt = now,
                    updatedAt = now,
                    lastModified = now,
                    version = nextVersion(current.version),
                    origin = "local"
                )
                nightsDao.update(deleted)
                outboxRepository.enqueueObject(
                    "booking_nights",
                    "delete",
                    deleted.localUuid,
                    deleted.toDomain()
                )
            }

            normalizedNights.forEachIndexed { index, night ->
                val existing = currentByDay[night.hotelDayKey]?.singleOrNull()
                    ?: nightsDao.getByNaturalKey(bookingId, night.hotelDayKey)
                check(existing?.deletedAt == null) {
                    "الليلة ${night.hotelDayKey} محذوفة سابقاً ولا يمكن إحياؤها ضمن سياسة حذف المزامنة الحالية"
                }

                val stableLocalUuid = existing?.localUuid
                    ?: night.localUuid.takeIf { it.isNotBlank() }
                    ?: UUID.randomUUID().toString()
                val prepared = night.copy(
                    id = existing?.id ?: 0L,
                    bookingLocalId = bookingId,
                    sequence = index,
                    bookingUuidCache = bookingUuid,
                    serverBookingId = booking.serverBookingId ?: night.serverBookingId,
                    localUuid = stableLocalUuid
                )
                val baseEntity = prepared.toEntity()
                val entity = if (existing == null) {
                    baseEntity.copy(
                        id = 0,
                        createdAt = now,
                        updatedAt = now,
                        deletedAt = null,
                        lastModified = now,
                        version = 1,
                        origin = "local"
                    )
                } else {
                    baseEntity.copy(
                        id = existing.id,
                        serverId = existing.serverId,
                        createdAt = existing.createdAt,
                        updatedAt = now,
                        deletedAt = null,
                        lastModified = now,
                        createdAtIso = existing.createdAtIso,
                        updatedAtIso = null,
                        deletedAtIso = null,
                        createdAtEpoch = existing.createdAtEpoch,
                        lastModifiedEpoch = existing.lastModifiedEpoch,
                        version = nextVersion(existing.version),
                        origin = "local",
                        vectorClock = existing.vectorClock,
                        deviceId = existing.deviceId,
                        syncTimestamp = existing.syncTimestamp,
                        idempotencyKey = existing.idempotencyKey
                    )
                }

                if (existing == null) {
                    nightsDao.insert(entity)
                } else {
                    nightsDao.update(entity)
                }
                outboxRepository.enqueueObject(
                    "booking_nights",
                    if (existing == null) "insert" else "update",
                    entity.localUuid,
                    entity.toDomain()
                )
            }
        }
    }

    private fun nextVersion(version: Int): Int =
        if (version < Int.MAX_VALUE) version + 1 else Int.MAX_VALUE

    override suspend fun getActiveAdjustments(bookingUuid: String): List<BookingPriceAdjustment> =
        adjustmentsDao.getActiveByBooking(bookingUuid).map { it.toDomain() }

    override suspend fun upsertAdjustment(adjustment: BookingPriceAdjustment): Long {
        val prepared = adjustment.copy(
            localUuid = adjustment.localUuid.ifBlank { UUID.randomUUID().toString() }
        )
        val id = adjustmentsDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("booking_price_adjustments", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun deactivateAdjustment(id: Long) {
        val current = adjustmentsDao.getById(id) ?: return
        adjustmentsDao.update(current.copy(isActive = false, updatedAt = System.currentTimeMillis()))
    }

    override fun watchLedger(): Flow<List<HotelDayLedger>> =
        ledgerDao.getAll().map { list -> list.map { it.toDomain() } }

    override suspend fun upsertLedger(entry: HotelDayLedger) {
        val prepared = entry.copy(localUuid = entry.localUuid.ifBlank { UUID.randomUUID().toString() })
        ledgerDao.insert(
            HotelDayLedgerEntity(
                hotelDayKey = prepared.hotelDayKey,
                totalIncome = prepared.totalIncome,
                totalExpenses = prepared.totalExpenses,
                pendingBalances = prepared.pendingBalances,
                occupancyRate = prepared.occupancyRate,
                status = prepared.status
            ).copy(id = prepared.id, localUuid = prepared.localUuid)
        )
    }
}
