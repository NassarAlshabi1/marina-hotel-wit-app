package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.ExpensesDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.repository.ExpensesRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class ExpensesRepositoryImpl @Inject constructor(
    private val expensesDao: ExpensesDao
) : ExpensesRepository {

    override fun getAll(): Flow<List<Expense>> =
        expensesDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(expense: Expense): Long = expensesDao.insert(expense.toEntity())

    override suspend fun update(expense: Expense) = expensesDao.update(expense.toEntity())

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        expensesDao.softDelete(id, deletedAt = now, updatedAt = now)
    }
}
