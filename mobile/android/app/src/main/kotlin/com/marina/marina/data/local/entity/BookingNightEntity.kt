package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "booking_nights",
    indices = [Index(value = ["booking_local_id"], name = "idx_booking_nights_booking")],
)
data class BookingNightEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") override val id: Long = 0,

    @SerializedName("booking_local_id") @ColumnInfo(name = "booking_local_id") val bookingLocalId: Long,
    @SerializedName("hotel_day_key") @ColumnInfo(name = "hotel_day_key") val hotelDayKey: String,
    @SerializedName("night_start") @ColumnInfo(name = "night_start") val nightStart: String,
    @SerializedName("night_end") @ColumnInfo(name = "night_end") val nightEnd: String,
    @SerializedName("nightly_rate") @ColumnInfo(name = "nightly_rate") val nightlyRate: Double = 0.0,
    @SerializedName("sequence") val sequence: Int = 0,
    @SerializedName("is_processed_by_auto_fix") @ColumnInfo(name = "is_processed_by_auto_fix") val isProcessedByAutoFix: Boolean = false,
    @SerializedName("base_rate") @ColumnInfo(name = "base_rate") val baseRate: Double = 0.0,
    @SerializedName("adjustment") val adjustment: Double = 0.0,
    @SerializedName("final_rate") @ColumnInfo(name = "final_rate") val finalRate: Double = 0.0,
    @SerializedName("applied_adjustment_uuid") @ColumnInfo(name = "applied_adjustment_uuid") val appliedAdjustmentUuid: String? = null,
    @SerializedName("applied_adjustments_json") @ColumnInfo(name = "applied_adjustments_json") val appliedAdjustmentsJson: String? = null,
    @SerializedName("booking_uuid_cache") @ColumnInfo(name = "booking_uuid_cache") val bookingUuidCache: String? = null,
    @SerializedName("server_booking_id") @ColumnInfo(name = "server_booking_id") val serverBookingId: Int? = null,

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
