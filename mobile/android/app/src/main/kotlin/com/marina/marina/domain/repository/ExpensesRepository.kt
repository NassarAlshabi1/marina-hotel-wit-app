package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Expense
import kotlinx.coroutines.flow.Flow

interface ExpensesRepository {
    fun getAll(): Flow<List<Expense>>
    suspend fun insert(expense: Expense): Long
    suspend fun update(expense: Expense)
    suspend fun softDelete(id: Long)

    /**
     * Live total of expenses for the given hotel day (`yyyy-MM-dd` key).
     * Feeds the Dashboard "المصروفات" card. Salary-advance cash-outs are
     * included (Flutter contract parity).
     */
    fun watchTotalByHotelDayKey(hotelDayKey: String): Flow<Double>
}
