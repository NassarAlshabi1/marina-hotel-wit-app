package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.DebtsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.DebtsRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class DebtsRepositoryImpl @Inject constructor(
    private val debtsDao: DebtsDao
) : DebtsRepository {

    override fun getUnsettled(): Flow<List<Debt>> =
        debtsDao.getUnsettled().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(debt: Debt): Long = debtsDao.insert(debt.toEntity())

    override suspend fun update(debt: Debt) = debtsDao.update(debt.toEntity())

    override suspend fun markSettled(id: Long, paidAmount: Double) {
        debtsDao.updateSettlement(id, paidAmount = paidAmount, remainingAmount = 0.0, isSettled = 1)
    }
}
