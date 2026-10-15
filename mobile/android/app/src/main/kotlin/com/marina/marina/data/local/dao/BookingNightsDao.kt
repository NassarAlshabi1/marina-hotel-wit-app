package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.BookingNightEntity
import kotlinx.coroutines.flow.Flow

/**
 * صف تعبئة UUID الحجز — نظير استعلامي `backfillNights`/`repushNotesOnce`
 * في `booking_child_uuid_backfill_service.dart` على الفرع المرجعي.
 */
data class UuidBackfillRow(
    val id: Long,
    val localUuid: String,
    val bookingUuid: String
)

@Dao
interface BookingNightsDao {
    @Query("SELECT * FROM booking_nights WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<BookingNightEntity>>

    @Query("SELECT * FROM booking_nights WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<BookingNightEntity>

    @Query("SELECT * FROM booking_nights WHERE id = :id")
    suspend fun getById(id: Long): BookingNightEntity?

    @Query("SELECT * FROM booking_nights WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): BookingNightEntity?

    @Query("SELECT * FROM booking_nights WHERE booking_local_id = :bookingId AND deleted_at IS NULL ORDER BY sequence ASC")
    suspend fun getByBooking(bookingId: Long): List<BookingNightEntity>

    /**
     * Nights of a booking from a hotel day onward — ported 1:1 from the Dart
     * PriceAdjustmentService queries (price_adjustment_service.dart l.143-152
     * and l.250-259): `hotel_day_key >= effectiveHotelDay AND deleted_at IS NULL`.
     * Used by the room price-change preview/apply flow.
     */
    @Query(
        """
        SELECT * FROM booking_nights
        WHERE booking_local_id = :bookingId
          AND deleted_at IS NULL
          AND hotel_day_key >= :hotelDayKey
        ORDER BY sequence ASC
        """
    )
    suspend fun getByBookingFromDay(bookingId: Long, hotelDayKey: String): List<BookingNightEntity>

    @Query("DELETE FROM booking_nights WHERE booking_local_id = :bookingId")
    suspend fun deleteByBooking(bookingId: Long)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: BookingNightEntity): Long

    @Update
    suspend fun update(entity: BookingNightEntity)

    @Query("UPDATE booking_nights SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM booking_nights WHERE id = :id")
    suspend fun delete(id: Long)

    /**
     * ✅ (2026-09-25) المفتاح الطبيعي الفريد لليلة — (booking_local_id,
     * hotel_day_key) نفس عقد _naturalUniqueKeys في Dart (إصلاح تجميد
     * 398 ليلة): صف خادمي يصل بـ local_uuid جديد لكن بنفس المفتاح
     * الطبيعي = نسخة مكررة منطقياً تُدمج LWW بدل إدراج صف ثانٍ.
     */
    @Query(
        """
        SELECT * FROM booking_nights
        WHERE booking_local_id = :bookingLocalId AND hotel_day_key = :hotelDayKey
        LIMIT 1
        """
    )
    suspend fun getByNaturalKey(bookingLocalId: Long, hotelDayKey: String): BookingNightEntity?

    /** الليالي الناقصة UUID حجزها — نفس استعلام Dart حرفياً (JOIN على bookings). */
    @Query(
        "SELECT n.id AS id, n.local_uuid AS localUuid, b.local_uuid AS bookingUuid " +
            "FROM booking_nights n JOIN bookings b ON b.id = n.booking_local_id " +
            "WHERE (n.booking_uuid_cache IS NULL OR n.booking_uuid_cache = '') " +
            "AND n.deleted_at IS NULL AND b.local_uuid IS NOT NULL AND b.local_uuid <> ''"
    )
    suspend fun listMissingBookingUuid(): List<UuidBackfillRow>

    /** كتابة العمود فقط — بلا لمس last_modified ولا بيانات المزامنة. */
    @Query("UPDATE booking_nights SET booking_uuid_cache = :uuid WHERE id = :id")
    suspend fun setBookingUuidCache(id: Long, uuid: String): Int
}
