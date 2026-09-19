package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.BookingNightsDao
import com.marina.marina.data.local.dao.BookingPriceAdjustmentsDao
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
    private val nightsDao: BookingNightsDao,
    private val adjustmentsDao: BookingPriceAdjustmentsDao,
    private val ledgerDao: HotelDayLedgerDao,
    private val outboxRepository: OutboxRepository
) : BookingNightsRepository {

    override suspend fun getByBooking(bookingId: Long): List<BookingNight> =
        nightsDao.getByBooking(bookingId).map { it.toDomain() }

    override suspend fun replaceNights(bookingId: Long, nights: List<BookingNight>) {
        nightsDao.deleteByBooking(bookingId)
        nights.forEachIndexed { index, night ->
            val prepared = night.copy(
                bookingLocalId = bookingId,
                sequence = index,
                localUuid = night.localUuid.ifBlank { UUID.randomUUID().toString() }
            )
            nightsDao.insert(prepared.toEntity())
            outboxRepository.enqueueObject("booking_nights", "insert", prepared.localUuid, prepared)
        }
    }

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
