package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.repository.BookingsRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class BookingsRepositoryImpl @Inject constructor(
    private val bookingsDao: BookingsDao
) : BookingsRepository {

    override fun getAll(): Flow<List<Booking>> =
        bookingsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(booking: Booking): Long = bookingsDao.insert(booking.toEntity())

    override suspend fun update(booking: Booking) = bookingsDao.update(booking.toEntity())

    override suspend fun checkout(id: Long, status: String, actualCheckout: String?) {
        val now = System.currentTimeMillis()
        bookingsDao.checkout(id, status, actualCheckout, updatedAt = now, lastModified = now)
    }

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        bookingsDao.softDelete(id, deletedAt = now, updatedAt = now, lastModified = now)
    }
}
