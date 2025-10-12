package com.marinahotel.kotlin.data.repository

import com.marinahotel.kotlin.data.db.PaymentDao
import com.marinahotel.kotlin.data.entities.PaymentEntity
import kotlinx.coroutines.flow.Flow

class PaymentsRepository(private val paymentDao: PaymentDao) {
    fun flowByBooking(bookingId: Int): Flow<List<PaymentEntity>> = paymentDao.flowByBooking(bookingId)
    fun flowRecent(): Flow<List<PaymentEntity>> = paymentDao.flowRecent()
    suspend fun getByBooking(bookingId: Int): List<PaymentEntity> = paymentDao.getByBooking(bookingId)
    suspend fun addPayment(payment: PaymentEntity) { paymentDao.insert(payment) }
}