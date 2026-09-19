package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.repository.BookingsRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class BookingsRepositoryImpl @Inject constructor(
    private val bookingsDao: BookingsDao,
    private val outboxRepository: OutboxRepository
) : BookingsRepository {

    override fun getAll(): Flow<List<Booking>> =
        bookingsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun getById(id: Long): Booking? =
        bookingsDao.getById(id)?.toDomain()

    override suspend fun insert(booking: Booking): Long {
        val now = System.currentTimeMillis()
        val prepared = booking.copy(
            localUuid = booking.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (booking.createdAt == 0L) now else booking.createdAt,
            updatedAt = now
        )
        val id = bookingsDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("bookings", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(booking: Booking) {
        val prepared = booking.copy(updatedAt = System.currentTimeMillis())
        bookingsDao.update(prepared.toEntity())
        outboxRepository.enqueueObject("bookings", "update", prepared.localUuid, prepared)
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
}
