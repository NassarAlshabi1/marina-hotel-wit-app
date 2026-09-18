package com.marina.marina.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface BookingsDao {
    @Query("SELECT * FROM bookings WHERE deleted_at IS NULL ORDER BY checkin_date DESC")
    fun getAll(): Flow<List<Booking>>

    @Query("SELECT * FROM bookings WHERE deleted_at IS NULL ORDER BY checkin_date DESC")
    fun getAllOnce(): List<Booking>

    @Query("SELECT * FROM bookings WHERE id = :id AND deleted_at IS NULL")
    fun getById(id: Long): Booking?

    @Query("SELECT * FROM bookings WHERE room_number = :roomNumber AND deleted_at IS NULL ORDER BY checkin_date DESC")
    fun getByRoom(roomNumber: String): Flow<List<Booking>>

    @Query("SELECT * FROM bookings WHERE status = :status AND deleted_at IS NULL ORDER BY checkin_date DESC")
    fun getByStatus(status: String): Flow<List<Booking>>

    @Query("SELECT * FROM bookings WHERE (guest_name LIKE :search OR guest_phone LIKE :search) AND deleted_at IS NULL ORDER BY checkin_date DESC")
    fun search(search: String): Flow<List<Booking>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(booking: Booking): Long

    @Update
    suspend fun update(booking: Booking)

    @Query("UPDATE bookings SET status = :status, actual_checkout = :actualCheckout, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun checkout(id: Long, status: String, actualCheckout: String?, updatedAt: Long, lastModified: Long): Int

    @Query("UPDATE bookings SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM bookings WHERE id = :id")
    suspend fun delete(id: Int)
}