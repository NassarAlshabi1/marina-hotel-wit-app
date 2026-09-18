package com.marina.marina.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface PaymentsDao {
    @Query("SELECT * FROM payments WHERE deleted_at IS NULL AND is_voided = 0 ORDER BY payment_date DESC")
    fun getAll(): Flow<List<Payment>>

    @Query("SELECT * FROM payments WHERE deleted_at IS NULL AND is_voided = 0 ORDER BY payment_date DESC")
    fun getAllOnce(): List<Payment>

    @Query("SELECT * FROM payments WHERE id = :id AND deleted_at IS NULL")
    fun getById(id: Long): Payment?

    @Query("SELECT * FROM payments WHERE booking_local_id = :bookingId AND deleted_at IS NULL ORDER BY payment_date DESC")
    fun getByBooking(bookingId: Long): Flow<List<Payment>>

    @Query("SELECT * FROM payments WHERE room_number = :roomNumber AND deleted_at IS NULL ORDER BY payment_date DESC")
    fun getByRoom(roomNumber: String): Flow<List<Payment>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(payment: Payment): Long

    @Update
    suspend fun update(payment: Payment)

    @Query("UPDATE payments SET is_voided = 1, voided_at = :voidedAt, voided_by = :voidedBy, void_reason = :voidReason, updated_at = :updatedAt WHERE id = :id")
    suspend fun void(id: Long, voidedAt: Long, voidedBy: String, voidReason: String, updatedAt: Long): Int

    @Query("UPDATE payments SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
}