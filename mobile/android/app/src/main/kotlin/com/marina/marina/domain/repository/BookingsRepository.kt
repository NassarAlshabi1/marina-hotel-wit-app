package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Booking
import kotlinx.coroutines.flow.Flow

interface BookingsRepository {
    fun getAll(): Flow<List<Booking>>
    suspend fun getById(id: Long): Booking?
    suspend fun insert(booking: Booking): Long
    suspend fun update(booking: Booking)
    suspend fun checkout(id: Long, status: String, actualCheckout: String? = null)
    suspend fun softDelete(id: Long)
}
