package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Payment
import kotlinx.coroutines.flow.Flow

interface PaymentsRepository {
    fun getAll(): Flow<List<Payment>>
    fun getByBooking(bookingId: Long): Flow<List<Payment>>
    suspend fun insert(payment: Payment): Long
    suspend fun update(payment: Payment)
    suspend fun void(id: Long, voidedBy: String, voidReason: String)
}
