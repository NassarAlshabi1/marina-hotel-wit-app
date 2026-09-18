package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(
    tableName = "rooms",
    indices = [
        Index("idx_rooms_status", "status, cleaning_status"),
        Index("idx_rooms_maintenance", "requires_maintenance")
    ]
)
data class RoomEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    override val id: Long = 0,

    @SerializedName("room_number")
    val roomNumber: String,

    @SerializedName("type")
    val type: String,

    @SerializedName("price")
    val price: Double,

    @SerializedName("status")
    val status: String,

    @SerializedName("image_url")
    val imageUrl: String? = null,

    @SerializedName("cleaning_status")
    val cleaningStatus: String = "clean",

    @SerializedName("last_cleaned_hotel_day")
    val lastCleanedHotelDay: String? = null,

    @SerializedName("last_occupied_hotel_day")
    val lastOccupiedHotelDay: String? = null,

    @SerializedName("requires_maintenance")
    val requiresMaintenance: Boolean = false,

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
