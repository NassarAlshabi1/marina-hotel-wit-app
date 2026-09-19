package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.util.HotelTimeEngine
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class PaymentsRepositoryImpl @Inject constructor(
    private val paymentsDao: PaymentsDao,
    private val outboxRepository: OutboxRepository
) : PaymentsRepository {

    override fun getAll(): Flow<List<Payment>> =
        paymentsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override fun getByBooking(bookingId: Long): Flow<List<Payment>> =
        paymentsDao.getByBooking(bookingId).map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(payment: Payment): Long {
        val now = System.currentTimeMillis()
        val prepared = payment.copy(
            localUuid = payment.localUuid.ifBlank { UUID.randomUUID().toString() },
            paymentDate = payment.paymentDate.ifBlank { HotelTimeEngine.formatIso(now) },
            hotelDayKey = payment.hotelDayKey ?: HotelTimeEngine.currentHotelDayKey(),
            createdAt = if (payment.createdAt == 0L) now else payment.createdAt,
            updatedAt = now
        )
        val id = paymentsDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("payments", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(payment: Payment) {
        val prepared = payment.copy(updatedAt = System.currentTimeMillis())
        paymentsDao.update(prepared.toEntity())
        outboxRepository.enqueueObject("payments", "update", prepared.localUuid, prepared)
    }

    override suspend fun void(id: Long, voidedBy: String, voidReason: String) {
        val now = System.currentTimeMillis()
        paymentsDao.void(id, voidedAt = now, voidedBy = voidedBy, voidReason = voidReason, updatedAt = now)
    }
}
