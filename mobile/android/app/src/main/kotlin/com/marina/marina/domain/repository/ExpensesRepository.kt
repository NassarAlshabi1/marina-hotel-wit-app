package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Expense
import kotlinx.coroutines.flow.Flow

interface ExpensesRepository {
    fun getAll(): Flow<List<Expense>>
    suspend fun insert(expense: Expense): Long
    suspend fun update(expense: Expense)
    suspend fun softDelete(id: Long)
}
