package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.model.PaymentUserHotelDaySummary
import kotlinx.coroutines.flow.Flow

interface PaymentsRepository {
    fun getAll(): Flow<List<Payment>>
    fun getByBooking(bookingId: Long): Flow<List<Payment>>
    suspend fun insert(payment: Payment): Long
    suspend fun update(payment: Payment)
    suspend fun void(id: Long, voidedBy: String, voidReason: String)

    /**
     * Live total of non-voided payments for the given hotel day
     * (`yyyy-MM-dd` key). Feeds the Dashboard "مدفوعات اليوم" card.
     */
    fun watchTotalByHotelDayKey(hotelDayKey: String): Flow<Double>

    /**
     * Live total received by the current user within the active payment
     * session. Feeds the Dashboard "إجمالي استلاماتي خلال النوبة" card.
     * Emits 0 when no session is active.
     */
    fun watchTotalByCurrentPaymentSession(): Flow<Double>

    /**
     * Per-user receipt summaries for the given hotel day, excluding the
     * current user's own rows. Feeds the Dashboard
     * "استلامات المستخدمين الآخرين" card.
     */
    fun watchPaymentUserHotelDaySummaries(
        hotelDayKey: String,
        excludedUserId: Long?,
        excludedUserName: String?,
        excludedUserCloudId: String?
    ): Flow<List<PaymentUserHotelDaySummary>>
}
