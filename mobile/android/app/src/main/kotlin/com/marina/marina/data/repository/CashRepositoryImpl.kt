package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.CashTransactionsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.CashTransaction
import com.marina.marina.domain.repository.CashRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class CashRepositoryImpl @Inject constructor(
    private val dao: CashTransactionsDao,
    private val outboxRepository: OutboxRepository
) : CashRepository {

    override fun getAll(): Flow<List<CashTransaction>> =
        dao.getAll().map { list -> list.map { it.toDomain() } }

    override fun getByType(type: String): Flow<List<CashTransaction>> =
        dao.getByType(type).map { list -> list.map { it.toDomain() } }

    override suspend fun sumByType(type: String): Double = dao.sumByType(type)

    override suspend fun insert(transaction: CashTransaction): Long {
        val now = System.currentTimeMillis()
        val prepared = transaction.copy(
            localUuid = transaction.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (transaction.createdAt == 0L) now else transaction.createdAt,
            updatedAt = now
        )
        val id = dao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("cash_transactions", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        dao.softDelete(id, deletedAt = now, updatedAt = now, lastModified = now)
    }
}
