package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.PaymentVoidsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.PaymentVoid
import com.marina.marina.domain.repository.PaymentVoidsRepository
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
        val prepared = void.copy(
            localUuid = void.localUuid.ifBlank { UUID.randomUUID().toString() }
        )
        val id = dao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("payment_voids", "insert", prepared.localUuid, prepared)
        return id
    }
}
