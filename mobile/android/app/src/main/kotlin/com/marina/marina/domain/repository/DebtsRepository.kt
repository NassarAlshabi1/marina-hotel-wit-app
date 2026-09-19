package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Debt
import kotlinx.coroutines.flow.Flow

interface DebtsRepository {
    fun getUnsettled(): Flow<List<Debt>>
    fun getAll(): Flow<List<Debt>>
    suspend fun getById(id: Long): Debt?
    suspend fun insert(debt: Debt): Long
    suspend fun update(debt: Debt)
    suspend fun markSettled(id: Long, paidAmount: Double)
    suspend fun softDelete(id: Long)
}
