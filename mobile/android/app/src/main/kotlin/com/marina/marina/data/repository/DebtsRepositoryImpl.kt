package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.DebtsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.DebtsRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class DebtsRepositoryImpl @Inject constructor(
    private val debtsDao: DebtsDao,
    private val outboxRepository: OutboxRepository
) : DebtsRepository {

    override fun getUnsettled(): Flow<List<Debt>> =
        debtsDao.getUnsettled().map { entities -> entities.map { it.toDomain() } }

    override fun getAll(): Flow<List<Debt>> =
        debtsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun getById(id: Long): Debt? =
        debtsDao.getById(id)?.toDomain()

    override suspend fun insert(debt: Debt): Long {
        val now = System.currentTimeMillis()
        val prepared = debt.copy(
            localUuid = debt.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (debt.createdAt == 0L) now else debt.createdAt,
            updatedAt = now
        )
        val id = debtsDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("debts", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(debt: Debt) {
        val prepared = debt.copy(updatedAt = System.currentTimeMillis())
        debtsDao.update(prepared.toEntity())
        outboxRepository.enqueueObject("debts", "update", prepared.localUuid, prepared)
    }

    override suspend fun markSettled(id: Long, paidAmount: Double) {
        debtsDao.updateSettlement(id, paidAmount = paidAmount, remainingAmount = 0.0, isSettled = 1)
    }

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        debtsDao.softDelete(id, deletedAt = now, updatedAt = now)
    }
}
