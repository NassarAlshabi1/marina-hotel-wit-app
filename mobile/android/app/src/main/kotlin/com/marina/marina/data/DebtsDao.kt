package com.marina.marina.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface DebtsDao {
    @Query("SELECT * FROM debts WHERE is_settled = 0 ORDER BY date_recorded DESC")
    fun getUnsettled(): Flow<List<Debt>>

    @Query("SELECT * FROM debts ORDER BY date_recorded DESC")
    fun getAll(): Flow<List<Debt>>

    @Query("SELECT * FROM debts WHERE id = :id")
    fun getById(id: Long): Debt?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(debt: Debt): Long

    @Update
    suspend fun update(debt: Debt)

    @Query("UPDATE debts SET paid_amount = :paidAmount, remaining_amount = :remainingAmount, is_settled = :isSettled WHERE id = :id")
    suspend fun updateSettlement(id: Long, paidAmount: Double, remainingAmount: Double, isSettled: Int): Int
}