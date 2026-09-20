package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.CashTransactionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface CashTransactionsDao {
    @Query("SELECT * FROM cash_transactions WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<CashTransactionEntity>>

    @Query("SELECT * FROM cash_transactions WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<CashTransactionEntity>

    @Query("SELECT * FROM cash_transactions WHERE id = :id")
    suspend fun getById(id: Long): CashTransactionEntity?

    @Query("SELECT * FROM cash_transactions WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): CashTransactionEntity?

    @Query("SELECT * FROM cash_transactions WHERE transaction_type = :type AND deleted_at IS NULL ORDER BY id DESC")
    fun getByType(type: String): Flow<List<CashTransactionEntity>>

    @Query("SELECT COALESCE(SUM(amount), 0) FROM cash_transactions WHERE transaction_type = :type AND deleted_at IS NULL")
    suspend fun sumByType(type: String): Double

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: CashTransactionEntity): Long

    @Update
    suspend fun update(entity: CashTransactionEntity)

    @Query("UPDATE cash_transactions SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM cash_transactions WHERE id = :id")
    suspend fun delete(id: Long)
}
