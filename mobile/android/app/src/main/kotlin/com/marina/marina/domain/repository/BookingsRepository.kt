package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Booking
import kotlinx.coroutines.flow.Flow

interface BookingsRepository {
    fun getAll(): Flow<List<Booking>>
    suspend fun getById(id: Long): Booking?
    suspend fun insert(booking: Booking): Long
    suspend fun update(booking: Booking)

    /**
     * Dart derived-fields refresh with `enqueueOutbox:false` — updates the
     * booking row (cached financials) WITHOUT enqueueing an outbox change.
     * Used by the payment screen's display-only refresh.
     */
    suspend fun updateComputedFields(booking: Booking)
    suspend fun checkout(id: Long, status: String, actualCheckout: String? = null)
    suspend fun softDelete(id: Long)

    /** Any active booking bound to a room (latest check-in wins), or null. */
    suspend fun getActiveBookingForRoom(roomNumber: String): Booking?
}
