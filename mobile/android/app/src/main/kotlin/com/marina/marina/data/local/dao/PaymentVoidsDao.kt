package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.PaymentVoidEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PaymentVoidsDao {
    @Query("SELECT * FROM payment_voids WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<PaymentVoidEntity>>

    @Query("SELECT * FROM payment_voids WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<PaymentVoidEntity>

    @Query("SELECT * FROM payment_voids WHERE id = :id")
    suspend fun getById(id: Long): PaymentVoidEntity?

    @Query("SELECT * FROM payment_voids WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): PaymentVoidEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: PaymentVoidEntity): Long

    @Update
    suspend fun update(entity: PaymentVoidEntity)

    @Query("UPDATE payment_voids SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM payment_voids WHERE id = :id")
    suspend fun delete(id: Long)
}
