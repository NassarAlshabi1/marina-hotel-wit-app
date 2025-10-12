package com.marinahotel.kotlin.data.repository

import com.marinahotel.kotlin.data.db.ExpenseDao
import com.marinahotel.kotlin.data.db.ExpenseLogDao
import com.marinahotel.kotlin.data.entities.ExpenseEntity
import com.marinahotel.kotlin.data.entities.ExpenseLogEntity
import kotlinx.coroutines.flow.Flow

class ExpensesRepository(
    private val expenseDao: ExpenseDao,
    private val expenseLogDao: ExpenseLogDao
) {
    fun flowAllExpenses(): Flow<List<ExpenseEntity>> = expenseDao.flowAll()
    fun sumBetween(from: String, to: String): Flow<Double?> = expenseDao.sumBetween(from, to)
    suspend fun getAll(): List<ExpenseEntity> = expenseDao.getAll()

    suspend fun save(expense: ExpenseEntity) {
        expenseDao.insert(expense)
        expenseLogDao.insert(
            ExpenseLogEntity(
                expenseId = expense.id,
                action = "save",
                details = expense.description,
                userId = null,
                createdAt = expense.createdAt
            )
        )
    }
}