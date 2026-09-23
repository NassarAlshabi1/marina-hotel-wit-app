package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.PaymentEntity
import kotlinx.coroutines.flow.Flow

/** Projection row for the per-user hotel-day receipts aggregation. */
data class PaymentUserHotelDaySummaryRow(
    val userId: Long?,
    val userName: String?,
    val totalAmount: Double?,
    val paymentCount: Int
)

@Dao
interface PaymentsDao {
    @Query("SELECT * FROM payments WHERE deleted_at IS NULL AND is_voided = 0 ORDER BY payment_date DESC")
    fun getAll(): Flow<List<PaymentEntity>>

    @Query("SELECT * FROM payments WHERE deleted_at IS NULL AND is_voided = 0 ORDER BY payment_date DESC")
    suspend fun getAllOnce(): List<PaymentEntity>

    /** Dart `PaymentsDao.watchAll()` parity — includes voided rows. */
    @Query("SELECT * FROM payments WHERE deleted_at IS NULL ORDER BY payment_date DESC")
    suspend fun getAllIncludingVoided(): List<PaymentEntity>

    /** Dart `watchAll()` — live variant including voided rows. */
    @Query("SELECT * FROM payments WHERE deleted_at IS NULL ORDER BY payment_date DESC")
    fun watchAllIncludingVoided(): Flow<List<PaymentEntity>>

    /**
     * Canonical report query, ported 1:1 from the Dart
     * `PaymentsDao.listFilteredByHotelDay` (payments_dao.dart:194-245):
     * hotel-day range on `hotel_day_key` with a legacy fallback to
     * `payment_date` (from >= , to < next-day-start via prefix bound).
     */
    @Query(
        """
        SELECT * FROM payments
        WHERE deleted_at IS NULL
          AND (:excludeVoided = 0 OR is_voided = 0)
          AND (:excludePendingBalance = 0 OR is_pending_balance = 0)
          AND (:fromHotelDay IS NULL
               OR hotel_day_key IS NOT NULL AND hotel_day_key >= :fromHotelDay
               OR hotel_day_key IS NULL AND payment_date >= :fromHotelDay)
          AND (:toHotelDay IS NULL
               OR hotel_day_key IS NOT NULL AND hotel_day_key <= :toHotelDay
               OR hotel_day_key IS NULL AND payment_date < :toHotelDayExclusive)
          AND (:roomNumber IS NULL OR room_number = :roomNumber)
        ORDER BY payment_date DESC
        """
    )
    suspend fun listFilteredByHotelDay(
        fromHotelDay: String?,
        toHotelDay: String?,
        toHotelDayExclusive: String?,
        roomNumber: String?,
        excludeVoided: Boolean,
        excludePendingBalance: Boolean
    ): List<PaymentEntity>

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

    @Query("UPDATE payments SET is_voided = 1, voided_at = :voidedAt, voided_by = :voidedBy, void_reason = :voidReason, is_immutable = 1, version = version + 1, updated_at = :updatedAt WHERE id = :id")
    suspend fun voidPayment(id: Long, voidedAt: Long, voidedBy: String, voidReason: String, updatedAt: Long): Int

    @Query("UPDATE payments SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
    @Query("SELECT * FROM payments WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): PaymentEntity?

    // ---------------------------------------------------------------------------
    // Financial aggregates — ported 1:1 from the Flutter app's payments repo.
    // ---------------------------------------------------------------------------

    /**
     * Live total of non-voided payments for a hotel day. Legacy rows without
     * `hotel_day_key` fall back to matching `payment_date LIKE 'yyyy-MM-dd%'`.
     */
    @Query(
        """
        SELECT COALESCE(SUM(amount), 0.0) FROM payments
        WHERE deleted_at IS NULL AND is_voided = 0
          AND (hotel_day_key = :hotelDayKey
               OR (hotel_day_key IS NULL AND payment_date LIKE :hotelDayKeyPrefix))
        """
    )
    fun watchTotalByHotelDayKey(hotelDayKey: String, hotelDayKeyPrefix: String): Flow<Double>

    /**
     * Live total received by the current user within the active payment
     * session (login session — Option A). No hotel-day filter: a shift may
     * cross the 14:01 boundary. Pending-balance records are excluded.
     */
    @Query(
        """
        SELECT COALESCE(SUM(amount), 0.0) FROM payments
        WHERE deleted_at IS NULL AND is_voided = 0
          AND is_pending_balance = 0
          AND received_by_user_id = :userId
          AND received_session_uuid = :sessionUuid
        """
    )
    fun watchTotalByCurrentPaymentSession(userId: Long, sessionUuid: String): Flow<Double>

    /**
     * Per-user receipt summaries for a hotel day, grouped by a stable receiver
     * identity (cloud id when present, else `legacy:<user_id>`), ordered by
     * total amount descending.
     *
     * Exclusion mirrors the Dart contract: rows bound to the excluded local
     * user id / name are skipped unless they carry a cloud identity that
     * differs from [excludedCloudId] (a NULL [excludedCloudId] disables the
     * cloud filter entirely, matching the Dart conditional assembly).
     */
    @Query(
        """
        SELECT MIN(received_by_user_id) AS userId,
               COALESCE(NULLIF(TRIM(MAX(received_by_name)), ''), 'مستخدم غير معروف') AS userName,
               COALESCE(SUM(amount), 0.0) AS totalAmount,
               COUNT(*) AS paymentCount
        FROM payments
        WHERE deleted_at IS NULL AND is_voided = 0
          AND is_pending_balance = 0
          AND received_by_user_id IS NOT NULL
          AND (received_by_cloud_id IS NOT NULL OR received_by_name IS NOT NULL)
          AND (:excludedUserId IS NULL
               OR received_by_cloud_id IS NOT NULL
               OR received_by_user_id != :excludedUserId)
          AND (:excludedUserName IS NULL
               OR received_by_cloud_id IS NOT NULL
               OR COALESCE(NULLIF(TRIM(received_by_name), ''), 'مستخدم غير معروف') != :excludedUserName)
          AND (:excludedCloudId IS NULL
               OR received_by_cloud_id IS NULL
               OR received_by_cloud_id != :excludedCloudId)
          AND (hotel_day_key = :hotelDayKey
               OR (hotel_day_key IS NULL AND payment_date LIKE :hotelDayKeyPrefix))
        GROUP BY COALESCE(received_by_cloud_id, 'legacy:' || received_by_user_id)
        ORDER BY totalAmount DESC
        """
    )
    fun watchPaymentUserHotelDaySummaries(
        hotelDayKey: String,
        hotelDayKeyPrefix: String,
        excludedUserId: Long?,
        excludedUserName: String?,
        excludedCloudId: String?
    ): Flow<List<PaymentUserHotelDaySummaryRow>>
}
