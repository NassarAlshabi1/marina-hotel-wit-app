package com.marina.marina.domain.repository

import com.marina.marina.domain.model.CashTransaction
import kotlinx.coroutines.flow.Flow

interface CashRepository {
    fun getAll(): Flow<List<CashTransaction>>
    fun getByType(type: String): Flow<List<CashTransaction>>
    suspend fun sumByType(type: String): Double
    suspend fun insert(transaction: CashTransaction): Long
    suspend fun softDelete(id: Long)
}
