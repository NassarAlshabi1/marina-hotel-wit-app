package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.PaymentUserHotelDaySummaryRow
import com.marina.marina.data.local.dao.PaymentVoidsDao
import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.model.PaymentUserHotelDaySummary
import com.marina.marina.domain.model.PaymentVoid
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.session.PaymentSessionContext
import com.marina.marina.domain.util.HotelTimeEngine
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

@Singleton
class PaymentsRepositoryImpl @Inject constructor(
    private val paymentsDao: PaymentsDao,
    private val paymentVoidsDao: PaymentVoidsDao,
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
        // Dart payment_void_service.dart l.64-223 — the full void contract:
        // 1) a payment_voids audit record, 2) the payment row flip
        // (isVoided + version+1 + isImmutable), 3) outbox entries for both so
        // the void propagates to the cloud and other devices.
        val now = System.currentTimeMillis()
        val entity = paymentsDao.getById(id) ?: return
        val domain = entity.toDomain()
        val voidRecord = PaymentVoid(
            originalPaymentUuid = domain.localUuid,
            originalPaymentId = domain.id,
            bookingUuid = entity.bookingUuidCache ?: "",
            voidedAmount = kotlin.math.round(domain.amount).toLong(),
            voidReason = voidReason,
            voidedBy = voidedBy,
            voidedAt = now,
            voidedAtIso = HotelTimeEngine.formatIso(now),
            hotelDayKey = domain.hotelDayKey ?: HotelTimeEngine.currentHotelDayKey(),
            localUuid = UUID.randomUUID().toString()
        )
        paymentVoidsDao.insert(voidRecord.toEntity())
        outboxRepository.enqueueObject("payment_voids", "insert", voidRecord.localUuid, voidRecord)
        paymentsDao.voidPayment(id, voidedAt = now, voidedBy = voidedBy, voidReason = voidReason, updatedAt = now)
        val voidedDomain = domain.copy(
            isVoided = true,
            voidedAt = now,
            voidedBy = voidedBy,
            voidReason = voidReason,
            version = domain.version + 1,
            updatedAt = now
        )
        outboxRepository.enqueueObject("payments", "update", voidedDomain.localUuid, voidedDomain)
    }

    override suspend fun getByBookingOnce(bookingId: Long): List<Payment> =
        paymentsDao.getByBooking(bookingId).firstOrNull()?.map { it.toDomain() } ?: emptyList()

    override suspend fun getAllIncludingVoidedOnce(): List<Payment> =
        paymentsDao.getAllIncludingVoided().map { it.toDomain() }

    override fun getAllIncludingVoided(): Flow<List<Payment>> =
        paymentsDao.watchAllIncludingVoided().map { entities -> entities.map { it.toDomain() } }

    override suspend fun listFilteredByHotelDay(
        fromHotelDay: String?,
        toHotelDay: String?,
        roomNumber: String?,
        excludeVoided: Boolean,
        excludePendingBalance: Boolean
    ): List<Payment> {
        // Dart SqlDateRange.forDay(toHotelDay).endExclusive — next calendar day.
        val toExclusive = toHotelDay?.let {
            val cal = java.util.Calendar.getInstance()
            HotelTimeEngine.parseDate("$it 00:00:00")?.let { ms ->
                cal.timeInMillis = ms
                cal.add(java.util.Calendar.DAY_OF_YEAR, 1)
                HotelTimeEngine.formatIso(cal.timeInMillis).replace("T", " ").substring(0, 10)
            }
        }
        return paymentsDao.listFilteredByHotelDay(
            fromHotelDay = fromHotelDay,
            toHotelDay = toHotelDay,
            toHotelDayExclusive = toExclusive,
            roomNumber = roomNumber,
            excludeVoided = excludeVoided,
            excludePendingBalance = excludePendingBalance
        ).map { it.toDomain() }
    }

    override suspend fun softDelete(id: Long) {
        // Dart `paymentsRepo.delete(id)` — soft delete + outbox merge so the
        // deletion propagates to the cloud.
        val now = System.currentTimeMillis()
        val entity = paymentsDao.getById(id) ?: return
        paymentsDao.softDelete(id, deletedAt = now, updatedAt = now)
        val deleted = entity.copy(deletedAt = now, updatedAt = now).toDomain()
        outboxRepository.enqueueObject("payments", "delete", deleted.localUuid, deleted)
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
