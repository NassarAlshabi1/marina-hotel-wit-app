package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.DebtEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface DebtsDao {
    @Query("SELECT * FROM debts WHERE is_settled = 0 ORDER BY date_recorded DESC")
    fun getUnsettled(): Flow<List<DebtEntity>>

    @Query("SELECT * FROM debts ORDER BY date_recorded DESC")
    fun getAll(): Flow<List<DebtEntity>>

    @Query("SELECT * FROM debts WHERE id = :id")
    suspend fun getById(id: Long): DebtEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(debt: DebtEntity): Long

    @Update
    suspend fun update(debt: DebtEntity)

    @Query("UPDATE debts SET paid_amount = :paidAmount, remaining_amount = :remainingAmount, is_settled = :isSettled WHERE id = :id")
    suspend fun updateSettlement(id: Long, paidAmount: Double, remainingAmount: Double, isSettled: Int): Int

    @Query("UPDATE debts SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
    @Query("SELECT * FROM debts WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): DebtEntity?

}
