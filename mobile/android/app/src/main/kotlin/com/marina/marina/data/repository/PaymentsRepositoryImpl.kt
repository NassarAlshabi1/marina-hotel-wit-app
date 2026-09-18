package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.PaymentsRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class PaymentsRepositoryImpl @Inject constructor(
    private val paymentsDao: PaymentsDao
) : PaymentsRepository {

    override fun getAll(): Flow<List<Payment>> =
        paymentsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override fun getByBooking(bookingId: Long): Flow<List<Payment>> =
        paymentsDao.getByBooking(bookingId).map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(payment: Payment): Long = paymentsDao.insert(payment.toEntity())

    override suspend fun update(payment: Payment) = paymentsDao.update(payment.toEntity())

    override suspend fun void(id: Long, voidedBy: String, voidReason: String) {
        val now = System.currentTimeMillis()
        paymentsDao.void(id, voidedAt = now, voidedBy = voidedBy, voidReason = voidReason, updatedAt = now)
    }
}
