package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "booking_price_adjustments",
    indices = [Index(value = ["booking_local_uuid", "is_active"], name = "idx_booking_price_adj_booking"), Index(value = ["effective_hotel_day", "end_hotel_day"], name = "idx_booking_price_adj_dates")],
)
data class BookingPriceAdjustmentEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") override val id: Long = 0,

    @SerializedName("booking_local_uuid") @ColumnInfo(name = "booking_local_uuid") val bookingLocalUuid: String,
    @SerializedName("booking_local_id") @ColumnInfo(name = "booking_local_id") val bookingLocalId: Long? = null,
    @SerializedName("room_number") @ColumnInfo(name = "room_number") val roomNumber: String? = null,
    @SerializedName("amount") val amount: Double = 0.0,
    @SerializedName("effective_hotel_day") @ColumnInfo(name = "effective_hotel_day") val effectiveHotelDay: String,
    @SerializedName("end_hotel_day") @ColumnInfo(name = "end_hotel_day") val endHotelDay: String? = null,
    @SerializedName("is_active") @ColumnInfo(name = "is_active") val isActive: Boolean = true,
    @SerializedName("reason") val reason: String? = null,
    @SerializedName("applied_by") @ColumnInfo(name = "applied_by") val appliedBy: String? = null,
    @SerializedName("cancelled_at") @ColumnInfo(name = "cancelled_at") val cancelledAt: String? = null,
    @SerializedName("cancelled_by") @ColumnInfo(name = "cancelled_by") val cancelledBy: String? = null,
    @SerializedName("booking_uuid") @ColumnInfo(name = "booking_uuid") val bookingUuid: String? = null,
    @SerializedName("adjustment_type") @ColumnInfo(name = "adjustment_type") val adjustmentType: Int? = null,
    @SerializedName("adjustment_mode") @ColumnInfo(name = "adjustment_mode") val adjustmentMode: String? = null,
    @SerializedName("applied_at") @ColumnInfo(name = "applied_at") val appliedAt: Long? = null,

    @SerializedName("local_uuid") @ColumnInfo(name = "local_uuid") override val localUuid: String = "",
    @SerializedName("server_id") @ColumnInfo(name = "server_id") override val serverId: Int? = null,
    @SerializedName("created_at") @ColumnInfo(name = "created_at") override val createdAt: Long = 0,
    @SerializedName("updated_at") @ColumnInfo(name = "updated_at") override val updatedAt: Long = 0,
    @SerializedName("deleted_at") @ColumnInfo(name = "deleted_at") override val deletedAt: Long? = null,
    @SerializedName("last_modified") @ColumnInfo(name = "last_modified") override val lastModified: Long = 0,
    @SerializedName("created_at_iso") @ColumnInfo(name = "created_at_iso") override val createdAtIso: String? = null,
    @SerializedName("updated_at_iso") @ColumnInfo(name = "updated_at_iso") override val updatedAtIso: String? = null,
    @SerializedName("deleted_at_iso") @ColumnInfo(name = "deleted_at_iso") override val deletedAtIso: String? = null,
    @SerializedName("created_at_epoch") @ColumnInfo(name = "created_at_epoch") override val createdAtEpoch: Long = 0,
    @SerializedName("last_modified_epoch") @ColumnInfo(name = "last_modified_epoch") override val lastModifiedEpoch: Long = 0,
    @SerializedName("version") override val version: Int = 1,
    @SerializedName("origin") override val origin: String = "local",
    @SerializedName("vector_clock") @ColumnInfo(name = "vector_clock") override val vectorClock: String = "{}",
    @SerializedName("device_id") @ColumnInfo(name = "device_id") override val deviceId: String = "",
    @SerializedName("sync_timestamp") @ColumnInfo(name = "sync_timestamp") override val syncTimestamp: Long = 0,
    @SerializedName("idempotency_key") @ColumnInfo(name = "idempotency_key") override val idempotencyKey: String? = null
) : BaseSyncEntity(id = id, localUuid = localUuid, serverId = serverId, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt, lastModified = lastModified, createdAtIso = createdAtIso, updatedAtIso = updatedAtIso, deletedAtIso = deletedAtIso, createdAtEpoch = createdAtEpoch, lastModifiedEpoch = lastModifiedEpoch, version = version, origin = origin, vectorClock = vectorClock, deviceId = deviceId, syncTimestamp = syncTimestamp, idempotencyKey = idempotencyKey)
