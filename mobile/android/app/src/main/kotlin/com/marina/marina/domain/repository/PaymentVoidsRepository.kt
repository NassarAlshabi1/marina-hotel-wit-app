package com.marina.marina.domain.repository

import com.marina.marina.domain.model.PaymentVoid
import kotlinx.coroutines.flow.Flow

interface PaymentVoidsRepository {
    fun getAll(): Flow<List<PaymentVoid>>
    suspend fun getByBooking(bookingUuid: String): List<PaymentVoid>
    suspend fun voidPayment(void: PaymentVoid): Long
}
