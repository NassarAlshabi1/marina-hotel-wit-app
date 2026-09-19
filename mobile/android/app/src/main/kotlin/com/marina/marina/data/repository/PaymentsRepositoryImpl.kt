package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.PaymentUserHotelDaySummaryRow
import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.model.PaymentUserHotelDaySummary
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.session.PaymentSessionContext
import com.marina.marina.domain.util.HotelTimeEngine
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
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
        // Session stamping — ported from the Flutter `PaymentsRepository.create`
        // contract: a payment requires an active user session and is attributed
        // to it (received_by_user_id / received_by_name / received_session_uuid /
        // received_by_cloud_id). This attribution is what feeds the Dashboard
        // "My shift receipts" and "Other users' receipts" cards.
        val sessionUserId = PaymentSessionContext.userId
        val sessionUserName = PaymentSessionContext.userName
        val sessionUuid = PaymentSessionContext.sessionUuid
        val prepared = payment.copy(
            localUuid = payment.localUuid.ifBlank { UUID.randomUUID().toString() },
            paymentDate = payment.paymentDate.ifBlank { HotelTimeEngine.formatIso(now) },
            hotelDayKey = payment.hotelDayKey
                ?: payment.paymentDate.takeIf { it.isNotBlank() }
                    ?.let { HotelTimeEngine.parseDate(it) }
                    ?.let { HotelTimeEngine.hotelDayKey(it) }
                ?: HotelTimeEngine.currentHotelDayKey(),
            receivedByUserId = payment.receivedByUserId ?: sessionUserId,
            receivedByName = payment.receivedByName ?: sessionUserName,
            receivedSessionUuid = payment.receivedSessionUuid ?: sessionUuid,
            receivedByCloudId = payment.receivedByCloudId ?: PaymentSessionContext.cloudUserId,
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
        paymentsDao.voidPayment(id, voidedAt = now, voidedBy = voidedBy, voidReason = voidReason, updatedAt = now)
    }

    override fun watchTotalByHotelDayKey(hotelDayKey: String): Flow<Double> =
        paymentsDao.watchTotalByHotelDayKey(hotelDayKey, "$hotelDayKey%")

    override fun watchTotalByCurrentPaymentSession(): Flow<Double> {
        val userId = PaymentSessionContext.userId ?: return flowOf(0.0)
        val sessionUuid = PaymentSessionContext.sessionUuid ?: return flowOf(0.0)
        return paymentsDao.watchTotalByCurrentPaymentSession(userId, sessionUuid)
    }

    override fun watchPaymentUserHotelDaySummaries(
        hotelDayKey: String,
        excludedUserId: Long?,
        excludedUserName: String?,
        excludedUserCloudId: String?
    ): Flow<List<PaymentUserHotelDaySummary>> =
        paymentsDao
            .watchPaymentUserHotelDaySummaries(
                hotelDayKey = hotelDayKey,
                hotelDayKeyPrefix = "$hotelDayKey%",
                excludedUserId = excludedUserId,
                excludedUserName = excludedUserName,
                excludedCloudId = excludedUserCloudId
            )
            .map { rows ->
                rows.map { row ->
                    PaymentUserHotelDaySummary(
                        userId = row.userId,
                        userName = row.userName ?: "مستخدم غير معروف",
                        totalAmount = row.totalAmount ?: 0.0,
                        paymentCount = row.paymentCount
                    )
                }
            }
}
