package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(
    tableName = "bookings",
    indices = [
        Index("idx_bookings_status_day", "status, hotel_day_checkin"),
        Index("idx_bookings_room", "room_number"),
        Index("idx_bookings_guest", "guest_name"),
        Index("idx_bookings_deleted", "deleted_at"),
        Index("idx_bookings_checkin", "checkin_date"),
        Index("idx_bookings_active_checkin", "checkin_date DESC", "deleted_at IS NULL")
    ]
)
data class BookingEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    override val id: Long = 0,

    @SerializedName("server_booking_id")
    val serverBookingId: Int? = null,

    @SerializedName("room_number")
    val roomNumber: String,

    @SerializedName("guest_name")
    val guestName: String,

    @SerializedName("guest_phone")
    val guestPhone: String,

    @SerializedName("guest_id_type")
    val guestIdType: String = "بطاقة شخصية",

    @SerializedName("guest_id_number")
    val guestIdNumber: String = "",

    @SerializedName("guest_id_issue_date")
    val guestIdIssueDate: String? = null,

    @SerializedName("guest_id_issue_place")
    val guestIdIssuePlace: String? = null,

    @SerializedName("guest_nationality")
    val guestNationality: String,

    @SerializedName("guest_email")
    val guestEmail: String? = null,

    @SerializedName("guest_address")
    val guestAddress: String? = null,

    @SerializedName("checkin_date")
    val checkinDate: String,

    @SerializedName("checkout_date")
    val checkoutDate: String? = null,

    @SerializedName("actual_checkout")
    val actualCheckout: String? = null,

    @SerializedName("status")
    val status: String,

    @SerializedName("notes")
    val notes: String? = null,

    @SerializedName("discount")
    val discount: Double = 0.0,

    @SerializedName("discount_type")
    val discountType: String = "per_night",

    @SerializedName("discount_start_date")
    val discountStartDate: String? = null,

    @SerializedName("expected_nights")
    val expectedNights: Int = 1,

    @SerializedName("calculated_nights")
    val calculatedNights: Int = 1,

    @SerializedName("total_nights_cached")
    val totalNightsCached: Int = 0,

    @SerializedName("stay_duration_iso")
    val stayDurationIso: String? = null,

    @SerializedName("last_night_epoch")
    val lastNightEpoch: Int? = null,

    @SerializedName("is_overdue")
    val isOverdue: Boolean = false,

    @SerializedName("needs_checkout_review")
    val needsCheckoutReview: Boolean = false,

    @SerializedName("total_due_cached")
    val totalDueCached: Double = 0.0,

    @SerializedName("total_paid_cached")
    val totalPaidCached: Double = 0.0,

    @SerializedName("remaining_balance_cached")
    val remainingBalanceCached: Double = 0.0,

    @SerializedName("is_fully_paid")
    val isFullyPaid: Boolean = false,

    @SerializedName("hotel_day_checkin")
    val hotelDayCheckin: String? = null,

    @SerializedName("hotel_day_checkout")
    val hotelDayCheckout: String? = null,

    @SerializedName("financial_frozen_at")
    val financialFrozenAt: Long? = null,

    @SerializedName("financial_hash")
    val financialHash: String? = null,

    @SerializedName("local_uuid")
    override val localUuid: String = "",

    @SerializedName("server_id")
    override val serverId: Int? = null,

    @SerializedName("created_at")
    override val createdAt: Long = 0,

    @SerializedName("updated_at")
    override val updatedAt: Long = 0,

    @SerializedName("deleted_at")
    override val deletedAt: Long? = null,

    @SerializedName("last_modified")
    override val lastModified: Long = 0,

    @SerializedName("created_at_iso")
    override val createdAtIso: String? = null,

    @SerializedName("updated_at_iso")
    override val updatedAtIso: String? = null,

    @SerializedName("deleted_at_iso")
    override val deletedAtIso: String? = null,

    @SerializedName("created_at_epoch")
    override val createdAtEpoch: Long = 0,

    @SerializedName("last_modified_epoch")
    override val lastModifiedEpoch: Long = 0,

    @SerializedName("version")
    override val version: Int = 1,

    @SerializedName("origin")
    override val origin: String = "local",

    @SerializedName("vector_clock")
    override val vectorClock: String = "{}",

    @SerializedName("device_id")
    override val deviceId: String = "",

    @SerializedName("sync_timestamp")
    override val syncTimestamp: Long = 0,

    @SerializedName("idempotency_key")
    override val idempotencyKey: String? = null
) : BaseSyncEntity(
    id = id,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    lastModified = lastModified,
    createdAtIso = createdAtIso,
    updatedAtIso = updatedAtIso,
    deletedAtIso = deletedAtIso,
    createdAtEpoch = createdAtEpoch,
    lastModifiedEpoch = lastModifiedEpoch,
    version = version,
    origin = origin,
    vectorClock = vectorClock,
    deviceId = deviceId,
    syncTimestamp = syncTimestamp,
    idempotencyKey = idempotencyKey
)
