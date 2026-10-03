package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Expense
import kotlinx.coroutines.flow.Flow

interface ExpensesRepository {
    fun getAll(): Flow<List<Expense>>
    suspend fun insert(expense: Expense): Long
    suspend fun update(expense: Expense)
    suspend fun softDelete(id: Long)

    /** One-shot full list (non-deleted), newest first. */
    suspend fun getAllOnce(): List<Expense>

    /**
     * Report query (Dart `ExpensesDao.listFilteredByHotelDay`): hotel-day
     * range with legacy `date` fallback. When [expenseType] is a salary
     * contract type ('رواتب' family), the query matches all derived salary
     * types like Dart does. [search] filters description/type LIKE (Dart
     * expenses_dao.dart l.163-166).
     */
    suspend fun listFilteredByHotelDay(
        fromHotelDay: String?,
        toHotelDay: String?,
        expenseType: String? = null,
        search: String? = null
    ): List<Expense>

    /**
     * Live total of expenses for the given hotel day (`yyyy-MM-dd` key).
     * Feeds the Dashboard "المصروفات" card. Salary-advance cash-outs are
     * included (Flutter contract parity).
     */
    fun watchTotalByHotelDayKey(hotelDayKey: String): Flow<Double>
}
