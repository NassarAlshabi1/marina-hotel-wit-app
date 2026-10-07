package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.DebtsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.data.sync.SyncEpochs
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

    override fun getByBooking(bookingId: Long): Flow<List<Debt>> =
        debtsDao.getByBooking(bookingId).map { rows -> rows.map { it.toDomain() } }

    override suspend fun getById(id: Long): Debt? =
        debtsDao.getById(id)?.toDomain()

    override suspend fun insert(debt: Debt): Long {
        val now = SyncEpochs.nowSeconds()
        val prepared = debt.copy(
            localUuid = debt.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (debt.createdAt == 0L) now else debt.createdAt,
            updatedAt = now
        )
        val id = debtsDao.insert(prepared.toEntity().copy(lastModified = now, lastModifiedEpoch = now))
        outboxRepository.enqueueObject("debts", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(debt: Debt) {
        val now = SyncEpochs.nowSeconds()
        val existing = debtsDao.getById(debt.id)
        val prepared = debt.copy(updatedAt = now)
        debtsDao.update(
            prepared.toEntity().copy(
                localUuid = prepared.localUuid.ifBlank { existing?.localUuid.orEmpty() },
                createdAt = if (prepared.createdAt == 0L) (existing?.createdAt ?: now) else prepared.createdAt,
                lastModified = now,
                lastModifiedEpoch = now,
                version = (existing?.version ?: prepared.version) + 1
            )
        )
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
        val now = SyncEpochs.nowSeconds()
        debtsDao.updateSettlement(
            id, paidAmount = paidAmount, remainingAmount = 0.0, isSettled = 1,
            paymentDate = today, updatedAt = now, lastModified = now
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
        val now = SyncEpochs.nowSeconds()
        val entity = debtsDao.getById(id) ?: return
        debtsDao.softDelete(id, deletedAt = now, updatedAt = now, lastModified = now)
        val deleted = entity.toDomain().copy(deletedAt = now, updatedAt = now)
        outboxRepository.enqueueObject("debts", "delete", deleted.localUuid, deleted)
    }
}
