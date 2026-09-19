package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "price_adjustments",
    indices = [Index(value = ["target_type", "target_uuid"], name = "idx_price_adj_target"), Index(value = ["hotel_day_key"], name = "idx_price_adj_day")],
)
data class PriceAdjustmentEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") override val id: Long = 0,

    @SerializedName("target_type") @ColumnInfo(name = "target_type") val targetType: String,
    @SerializedName("target_uuid") @ColumnInfo(name = "target_uuid") val targetUuid: String,
    @SerializedName("adjustment_type") @ColumnInfo(name = "adjustment_type") val adjustmentType: String,
    @SerializedName("previous_value") @ColumnInfo(name = "previous_value") val previousValue: Double = 0.0,
    @SerializedName("new_value") @ColumnInfo(name = "new_value") val newValue: Double = 0.0,
    @SerializedName("reason") val reason: String? = null,
    @SerializedName("effective_date") @ColumnInfo(name = "effective_date") val effectiveDate: String,
    @SerializedName("applied_by") @ColumnInfo(name = "applied_by") val appliedBy: String,
    @SerializedName("hotel_day_key") @ColumnInfo(name = "hotel_day_key") val hotelDayKey: String? = null,
    @SerializedName("adjustment_mode") @ColumnInfo(name = "adjustment_mode") val adjustmentMode: String = "per_night",
    @SerializedName("booking_uuid") @ColumnInfo(name = "booking_uuid") val bookingUuid: String? = null,
    @SerializedName("applied_at") @ColumnInfo(name = "applied_at") val appliedAt: Long? = null,
    @SerializedName("is_reversed") @ColumnInfo(name = "is_reversed") val isReversed: Boolean = false,
    @SerializedName("reversed_at") @ColumnInfo(name = "reversed_at") val reversedAt: String? = null,
    @SerializedName("reversed_by") @ColumnInfo(name = "reversed_by") val reversedBy: String? = null,

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
