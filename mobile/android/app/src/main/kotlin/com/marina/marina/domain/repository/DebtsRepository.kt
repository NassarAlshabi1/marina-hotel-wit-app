package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Debt
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

interface DebtsRepository {
    fun getUnsettled(): Flow<List<Debt>>
    fun getAll(): Flow<List<Debt>>
    fun getByBooking(bookingId: Long): Flow<List<Debt>> =
        getAll().map { rows -> rows.filter { it.bookingLocalId == bookingId } }
    suspend fun getById(id: Long): Debt?
    suspend fun insert(debt: Debt): Long
    suspend fun update(debt: Debt)
    suspend fun markSettled(id: Long, paidAmount: Double)
    suspend fun softDelete(id: Long)
}
