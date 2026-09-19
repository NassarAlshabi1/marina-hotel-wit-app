package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.ColumnInfo
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(
    tableName = "bookings",
    indices = [
        Index(value = ["status", "hotel_day_checkin"], name = "idx_bookings_status_day"),
        Index(value = ["room_number"], name = "idx_bookings_room"),
        Index(value = ["guest_name"], name = "idx_bookings_guest"),
        Index(value = ["deleted_at"], name = "idx_bookings_deleted"),
        Index(value = ["checkin_date"], name = "idx_bookings_checkin"),
        Index(value = ["checkin_date"], orders = [androidx.room.Index.Order.DESC], name = "idx_bookings_active_checkin")
    ]
)
data class BookingEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    override val id: Long = 0,

    @SerializedName("server_booking_id")
    @ColumnInfo(name = "server_booking_id")
    val serverBookingId: Int? = null,

    @SerializedName("room_number")
    @ColumnInfo(name = "room_number")
    val roomNumber: String,

    @SerializedName("guest_name")
    @ColumnInfo(name = "guest_name")
    val guestName: String,

    @SerializedName("guest_phone")
    @ColumnInfo(name = "guest_phone")
    val guestPhone: String,

    @SerializedName("guest_id_type")
    @ColumnInfo(name = "guest_id_type")
    val guestIdType: String = "بطاقة شخصية",

    @SerializedName("guest_id_number")
    @ColumnInfo(name = "guest_id_number")
    val guestIdNumber: String = "",

    @SerializedName("guest_id_issue_date")
    @ColumnInfo(name = "guest_id_issue_date")
    val guestIdIssueDate: String? = null,

    @SerializedName("guest_id_issue_place")
    @ColumnInfo(name = "guest_id_issue_place")
    val guestIdIssuePlace: String? = null,

    @SerializedName("guest_nationality")
    @ColumnInfo(name = "guest_nationality")
    val guestNationality: String,

    @SerializedName("guest_email")
    @ColumnInfo(name = "guest_email")
    val guestEmail: String? = null,

    @SerializedName("guest_address")
    @ColumnInfo(name = "guest_address")
    val guestAddress: String? = null,

    @SerializedName("checkin_date")
    @ColumnInfo(name = "checkin_date")
    val checkinDate: String,

    @SerializedName("checkout_date")
    @ColumnInfo(name = "checkout_date")
    val checkoutDate: String? = null,

    @SerializedName("actual_checkout")
    @ColumnInfo(name = "actual_checkout")
    val actualCheckout: String? = null,

    @SerializedName("status")
    val status: String,

    @SerializedName("notes")
    val notes: String? = null,

    @SerializedName("discount")
    val discount: Double = 0.0,

    @SerializedName("discount_type")
    @ColumnInfo(name = "discount_type")
    val discountType: String = "per_night",

    @SerializedName("discount_start_date")
    @ColumnInfo(name = "discount_start_date")
    val discountStartDate: String? = null,

    @SerializedName("expected_nights")
    @ColumnInfo(name = "expected_nights")
    val expectedNights: Int = 1,

    @SerializedName("calculated_nights")
    @ColumnInfo(name = "calculated_nights")
    val calculatedNights: Int = 1,

    @SerializedName("total_nights_cached")
    @ColumnInfo(name = "total_nights_cached")
    val totalNightsCached: Int = 0,

    @SerializedName("stay_duration_iso")
    @ColumnInfo(name = "stay_duration_iso")
    val stayDurationIso: String? = null,

    @SerializedName("last_night_epoch")
    @ColumnInfo(name = "last_night_epoch")
    val lastNightEpoch: Int? = null,

    @SerializedName("is_overdue")
    @ColumnInfo(name = "is_overdue")
    val isOverdue: Boolean = false,

    @SerializedName("needs_checkout_review")
    @ColumnInfo(name = "needs_checkout_review")
    val needsCheckoutReview: Boolean = false,

    @SerializedName("total_due_cached")
    @ColumnInfo(name = "total_due_cached")
    val totalDueCached: Double = 0.0,

    @SerializedName("total_paid_cached")
    @ColumnInfo(name = "total_paid_cached")
    val totalPaidCached: Double = 0.0,

    @SerializedName("remaining_balance_cached")
    @ColumnInfo(name = "remaining_balance_cached")
    val remainingBalanceCached: Double = 0.0,

    @SerializedName("is_fully_paid")
    @ColumnInfo(name = "is_fully_paid")
    val isFullyPaid: Boolean = false,

    @SerializedName("hotel_day_checkin")
    @ColumnInfo(name = "hotel_day_checkin")
    val hotelDayCheckin: String? = null,

    @SerializedName("hotel_day_checkout")
    @ColumnInfo(name = "hotel_day_checkout")
    val hotelDayCheckout: String? = null,

    @SerializedName("financial_frozen_at")
    @ColumnInfo(name = "financial_frozen_at")
    val financialFrozenAt: Long? = null,

    @SerializedName("financial_hash")
    @ColumnInfo(name = "financial_hash")
    val financialHash: String? = null,

    @SerializedName("local_uuid")
    @ColumnInfo(name = "local_uuid")
    override val localUuid: String = "",

    @SerializedName("server_id")
    @ColumnInfo(name = "server_id")
    override val serverId: Int? = null,

    @SerializedName("created_at")
    @ColumnInfo(name = "created_at")
    override val createdAt: Long = 0,

    @SerializedName("updated_at")
    @ColumnInfo(name = "updated_at")
    override val updatedAt: Long = 0,

    @SerializedName("deleted_at")
    @ColumnInfo(name = "deleted_at")
    override val deletedAt: Long? = null,

    @SerializedName("last_modified")
    @ColumnInfo(name = "last_modified")
    override val lastModified: Long = 0,

    @SerializedName("created_at_iso")
    @ColumnInfo(name = "created_at_iso")
    override val createdAtIso: String? = null,

    @SerializedName("updated_at_iso")
    @ColumnInfo(name = "updated_at_iso")
    override val updatedAtIso: String? = null,

    @SerializedName("deleted_at_iso")
    @ColumnInfo(name = "deleted_at_iso")
    override val deletedAtIso: String? = null,

    @SerializedName("created_at_epoch")
    @ColumnInfo(name = "created_at_epoch")
    override val createdAtEpoch: Long = 0,

    @SerializedName("last_modified_epoch")
    @ColumnInfo(name = "last_modified_epoch")
    override val lastModifiedEpoch: Long = 0,

    @SerializedName("version")
    override val version: Int = 1,

    @SerializedName("origin")
    override val origin: String = "local",

    @SerializedName("vector_clock")
    @ColumnInfo(name = "vector_clock")
    override val vectorClock: String = "{}",

    @SerializedName("device_id")
    @ColumnInfo(name = "device_id")
    override val deviceId: String = "",

    @SerializedName("sync_timestamp")
    @ColumnInfo(name = "sync_timestamp")
    override val syncTimestamp: Long = 0,

    @SerializedName("idempotency_key")
    @ColumnInfo(name = "idempotency_key")
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
