package com.marina.marina.data.repository

import androidx.room.withTransaction
import com.marina.marina.data.local.AppDatabase
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
import com.marina.marina.data.sync.SyncEpochs
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
    private val outboxRepository: OutboxRepository,
    private val db: AppDatabase,
    private val bookingsRepository: BookingsRepositoryImpl
) : PaymentsRepository {

    override fun getAll(): Flow<List<Payment>> =
        paymentsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override fun getByBooking(bookingId: Long): Flow<List<Payment>> =
        paymentsDao.getByBooking(bookingId).map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(payment: Payment): Long {
        val nowMillis = System.currentTimeMillis()
        val now = SyncEpochs.nowSeconds()
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
            paymentDate = payment.paymentDate.ifBlank { HotelTimeEngine.formatIso(nowMillis) },
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
        val id = paymentsDao.insert(prepared.toEntity().copy(lastModified = now, lastModifiedEpoch = now))
        outboxRepository.enqueueObject("payments", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(payment: Payment) {
        db.withTransaction {
            val old = requireNotNull(paymentsDao.getById(payment.id)) { "الدفعة غير موجودة" }
            val moved = old.bookingLocalId != payment.bookingLocalId
            val newBooking = if (moved && payment.bookingLocalId != null) {
                requireNotNull(db.bookingsDao().getById(payment.bookingLocalId)) { "الحجز غير موجود" }
            } else null
            val nowSeconds = SyncEpochs.nowSeconds()
            val prepared = payment.copy(localUuid = old.localUuid, serverId = old.serverId,
                createdAt = old.createdAt, updatedAt = nowSeconds)
            // Keep fields absent from the domain model (UUID caches, audit and sync metadata).
            paymentsDao.update(old.copy(
                lastModified = nowSeconds,
                lastModifiedEpoch = nowSeconds,
                bookingLocalId = prepared.bookingLocalId, roomNumber = prepared.roomNumber,
                bookingUuidCache = if (moved) newBooking?.localUuid else old.bookingUuidCache,
                serverBookingId = if (moved) newBooking?.serverBookingId else old.serverBookingId,
                amount = prepared.amount, paymentDate = prepared.paymentDate,
                paymentMethod = prepared.paymentMethod, revenueType = prepared.revenueType,
                notes = prepared.notes, referenceNumber = prepared.referenceNumber,
                hotelDayKey = prepared.hotelDayKey, isPendingBalance = prepared.isPendingBalance,
                isVoided = prepared.isVoided, voidedAt = prepared.voidedAt,
                voidedBy = prepared.voidedBy, voidReason = prepared.voidReason,
                receivedByName = prepared.receivedByName, receivedByUserId = prepared.receivedByUserId,
                receivedSessionUuid = prepared.receivedSessionUuid, receivedByCloudId = prepared.receivedByCloudId,
                updatedAt = prepared.updatedAt, deletedAt = prepared.deletedAt, version = old.version + 1
            ))
            outboxRepository.enqueueObject("payments", "update", prepared.localUuid, prepared)
            // Refresh both sides if the payment was moved; never add a second payment.
            setOfNotNull(old.bookingLocalId, prepared.bookingLocalId).forEach {
                bookingsRepository.refreshFinancialCache(it)
            }
        }
    }

    override suspend fun void(id: Long, voidedBy: String, voidReason: String) {
        // Dart payment_void_service.dart l.64-223 — the full void contract:
        // 1) a payment_voids audit record, 2) the payment row flip
        // (isVoided + version+1 + isImmutable), 3) outbox entries for both so
        // the void propagates to the cloud and other devices.
        val nowMillis = System.currentTimeMillis()
        val now = SyncEpochs.nowSeconds()
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
            voidedAtIso = HotelTimeEngine.formatIso(nowMillis),
            hotelDayKey = domain.hotelDayKey ?: HotelTimeEngine.currentHotelDayKey(),
            localUuid = UUID.randomUUID().toString()
        )
        // نظير Dart (`payment_void_service.dart` l.132-152): سجل الإلغاء نفسه
        // يُختم `createdAt/updatedAt/lastModified = nowEpoch` — كان `toEntity()`
        // يكتبها أصفاراً (نموذج المجال بلا حقول مزامنة).
        paymentVoidsDao.insert(
            voidRecord.toEntity().copy(
                createdAt = now,
                updatedAt = now,
                lastModified = now,
                lastModifiedEpoch = now
            )
        )
        outboxRepository.enqueueObject("payment_voids", "insert", voidRecord.localUuid, voidRecord)
        paymentsDao.voidPayment(id, voidedAt = now, voidedBy = voidedBy, voidReason = voidReason, updatedAt = now, lastModified = now)
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
        val now = SyncEpochs.nowSeconds()
        val entity = paymentsDao.getById(id) ?: return
        paymentsDao.softDelete(id, deletedAt = now, updatedAt = now, lastModified = now)
        val deleted = entity.copy(deletedAt = now, updatedAt = now, lastModified = now).toDomain()
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
