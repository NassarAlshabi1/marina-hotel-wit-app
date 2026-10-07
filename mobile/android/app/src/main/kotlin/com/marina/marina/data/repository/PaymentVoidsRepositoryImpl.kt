package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.PaymentVoidsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.PaymentVoid
import com.marina.marina.domain.repository.PaymentVoidsRepository
import com.marina.marina.data.sync.SyncEpochs
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class PaymentVoidsRepositoryImpl @Inject constructor(
    private val dao: PaymentVoidsDao,
    private val outboxRepository: OutboxRepository
) : PaymentVoidsRepository {

    override fun getAll(): Flow<List<PaymentVoid>> =
        dao.getAll().map { list -> list.map { it.toDomain() } }

    override suspend fun getByBooking(bookingUuid: String): List<PaymentVoid> =
        dao.getByBooking(bookingUuid).map { it.toDomain() }

    override suspend fun voidPayment(void: PaymentVoid): Long {
        // نظير Dart (`payment_void_service.dart` l.132-152): الصف الجديد
        // بـ`createdAt/updatedAt/lastModified = nowEpoch` (ثوانٍ).
        val now = SyncEpochs.nowSeconds()
        val prepared = void.copy(
            localUuid = void.localUuid.ifBlank { UUID.randomUUID().toString() }
        )
        // نموذج المجال لا يحمل حقول المزامنة (created/updated/last_modified)
        // فتُختم على الصف نفسه — نظير Companion Dart أعلاه.
        val id = dao.insert(
            prepared.toEntity().copy(
                createdAt = now,
                updatedAt = now,
                lastModified = now,
                lastModifiedEpoch = now
            )
        )
        outboxRepository.enqueueObject("payment_voids", "insert", prepared.localUuid, prepared)
        return id
    }
}
