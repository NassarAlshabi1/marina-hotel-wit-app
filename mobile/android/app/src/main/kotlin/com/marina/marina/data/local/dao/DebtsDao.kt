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
    // Dart debts_dao.dart l.56-63 — every list query excludes soft-deleted rows.
    @Query("SELECT * FROM debts WHERE is_settled = 0 AND deleted_at IS NULL ORDER BY date_recorded DESC")
    fun getUnsettled(): Flow<List<DebtEntity>>

    @Query("SELECT * FROM debts WHERE deleted_at IS NULL ORDER BY date_recorded DESC")
    fun getAll(): Flow<List<DebtEntity>>

    @Query("SELECT * FROM debts WHERE id = :id")
    suspend fun getById(id: Long): DebtEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(debt: DebtEntity): Long

    @Update
    suspend fun update(debt: DebtEntity)

    @Query("UPDATE debts SET paid_amount = :paidAmount, remaining_amount = :remainingAmount, is_settled = :isSettled, payment_date = :paymentDate, updated_at = :updatedAt WHERE id = :id")
    suspend fun updateSettlement(id: Long, paidAmount: Double, remainingAmount: Double, isSettled: Int, paymentDate: String, updatedAt: Long): Int

    @Query("UPDATE debts SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
    @Query("SELECT * FROM debts WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): DebtEntity?

    /** البحث الشامل — كل الصفوف بما فيها المحذوفة ناعمياً (تدقيق المدير). */
    @Query("SELECT * FROM debts")
    suspend fun listAllIncludingDeleted(): List<DebtEntity>
}
