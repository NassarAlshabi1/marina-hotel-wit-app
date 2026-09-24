package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.BookingEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface BookingsDao {
    @Query("SELECT * FROM bookings WHERE deleted_at IS NULL ORDER BY checkin_date DESC")
    fun getAll(): Flow<List<BookingEntity>>

    @Query("SELECT * FROM bookings WHERE deleted_at IS NULL ORDER BY checkin_date DESC")
    suspend fun getAllOnce(): List<BookingEntity>

    @Query("SELECT * FROM bookings WHERE id = :id AND deleted_at IS NULL")
    suspend fun getById(id: Long): BookingEntity?

    @Query("SELECT * FROM bookings WHERE room_number = :roomNumber AND deleted_at IS NULL ORDER BY checkin_date DESC")
    fun getByRoom(roomNumber: String): Flow<List<BookingEntity>>

    @Query("SELECT * FROM bookings WHERE status = :status AND deleted_at IS NULL ORDER BY checkin_date DESC")
    fun getByStatus(status: String): Flow<List<BookingEntity>>

    @Query("SELECT * FROM bookings WHERE (guest_name LIKE :search OR guest_phone LIKE :search) AND deleted_at IS NULL ORDER BY checkin_date DESC")
    fun search(search: String): Flow<List<BookingEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(booking: BookingEntity): Long

    @Update
    suspend fun update(booking: BookingEntity)

    @Query("UPDATE bookings SET status = :status, actual_checkout = :actualCheckout, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun checkout(id: Long, status: String, actualCheckout: String?, updatedAt: Long, lastModified: Long): Int

    @Query("UPDATE bookings SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM bookings WHERE id = :id")
    suspend fun delete(id: Long)
    @Query("SELECT * FROM bookings WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): BookingEntity?

    /**
     * Any active booking for a room — checks every active booking status
     * (ported 1:1 from the Flutter repo: ordered by check-in date desc, limit 1).
     */
    @Query(
        """
        SELECT * FROM bookings
        WHERE room_number = :roomNumber
          AND deleted_at IS NULL
          AND status IN ('محجوزة', 'محجوز', 'نشط', 'active', 'confirmed', 'قيد الحجز', 'in_progress', 'مؤقت', 'provisional')
        ORDER BY checkin_date DESC
        LIMIT 1
        """
    )
    suspend fun getActiveBookingForRoom(roomNumber: String): BookingEntity?

    /**
     * ALL in-stay bookings of a room — ported 1:1 from the Dart
     * PriceAdjustmentService._getActiveBookingsForRoom
     * (price_adjustment_service.dart l.204-218): the room price-change
     * preview/apply flow uses a WIDER status list than the occupancy query
     * ('مؤكد','confirmed','نشط','active','مسجل دخول','checked_in') plus
     * actual_checkout IS NULL.
     */
    @Query(
        """
        SELECT * FROM bookings
        WHERE room_number = :roomNumber
          AND deleted_at IS NULL
          AND actual_checkout IS NULL
          AND status IN ('مؤكد', 'confirmed', 'نشط', 'active', 'مسجل دخول', 'checked_in')
        ORDER BY checkin_date DESC
        """
    )
    suspend fun getInStayBookingsForRoom(roomNumber: String): List<BookingEntity>

    /** البحث الشامل — كل الصفوف بما فيها المحذوفة ناعمياً (تدقيق المدير). */
    @Query("SELECT * FROM bookings")
    suspend fun listAllIncludingDeleted(): List<BookingEntity>
}
