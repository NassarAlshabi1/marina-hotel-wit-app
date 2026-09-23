package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.DebtsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.util.HotelTimeEngine
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

    /**
     * Dart settle flow (debts_list l.797-846): isSettled=1, paid=total,
     * remaining=0, paymentDate=today — AND the change syncs to the cloud
     * (repo update + outbox).
     */
    override suspend fun markSettled(id: Long, paidAmount: Double) {
        val entity = debtsDao.getById(id) ?: return
        val today = HotelTimeEngine.currentHotelDayKey()
        val now = System.currentTimeMillis()
        debtsDao.updateSettlement(
            id, paidAmount = paidAmount, remainingAmount = 0.0, isSettled = 1,
            paymentDate = today, updatedAt = now
        )
        val settled = entity.toDomain().copy(
            paidAmount = paidAmount,
            remainingAmount = 0.0,
            isSettled = true,
            paymentDate = today,
            updatedAt = now
        )
        outboxRepository.enqueueObject("debts", "update", settled.localUuid, settled)
    }

    override suspend fun softDelete(id: Long) {
        // Dart debts_dao l.169-180 — delete is soft AND syncs to the cloud.
        val now = System.currentTimeMillis()
        val entity = debtsDao.getById(id) ?: return
        debtsDao.softDelete(id, deletedAt = now, updatedAt = now)
        val deleted = entity.toDomain().copy(deletedAt = now, updatedAt = now)
        outboxRepository.enqueueObject("debts", "delete", deleted.localUuid, deleted)
    }
}
