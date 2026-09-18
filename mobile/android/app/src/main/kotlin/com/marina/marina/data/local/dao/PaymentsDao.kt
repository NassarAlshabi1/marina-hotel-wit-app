package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.PaymentEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PaymentsDao {
    @Query("SELECT * FROM payments WHERE deleted_at IS NULL AND is_voided = 0 ORDER BY payment_date DESC")
    fun getAll(): Flow<List<PaymentEntity>>

    @Query("SELECT * FROM payments WHERE deleted_at IS NULL AND is_voided = 0 ORDER BY payment_date DESC")
    suspend fun getAllOnce(): List<PaymentEntity>

    @Query("SELECT * FROM payments WHERE id = :id AND deleted_at IS NULL")
    suspend fun getById(id: Long): PaymentEntity?

    @Query("SELECT * FROM payments WHERE booking_local_id = :bookingId AND deleted_at IS NULL ORDER BY payment_date DESC")
    fun getByBooking(bookingId: Long): Flow<List<PaymentEntity>>

    @Query("SELECT * FROM payments WHERE room_number = :roomNumber AND deleted_at IS NULL ORDER BY payment_date DESC")
    fun getByRoom(roomNumber: String): Flow<List<PaymentEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(payment: PaymentEntity): Long

    @Update
    suspend fun update(payment: PaymentEntity)

    @Query("UPDATE payments SET is_voided = 1, voided_at = :voidedAt, voided_by = :voidedBy, void_reason = :voidReason, updated_at = :updatedAt WHERE id = :id")
    suspend fun void(id: Long, voidedAt: Long, voidedBy: String, voidReason: String, updatedAt: Long): Int

    @Query("UPDATE payments SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
}
