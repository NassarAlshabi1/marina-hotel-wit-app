package com.marina.marina.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

/**
 * Base interface for all Room entities that participate in Cloudflare D1 sync.
 * Mirrors the Drift `SyncFields` mixin in lib/services/local_db.dart.
 */
interface SyncFields {
    val localUuid: String
    val serverId: Int?
    val createdAt: Long
    val updatedAt: Long
    val deletedAt: Long?
    val lastModified: Long
    val createdAtIso: String?
    val updatedAtIso: String?
    val deletedAtIso: String?
    val createdAtEpoch: Long
    val lastModifiedEpoch: Long
    val version: Int
    val origin: String
    val vectorClock: String
    val deviceId: String
    val syncTimestamp: Long
    val idempotencyKey: String?
}

/**
 * Common base entity class with sync fields.
 */
open class BaseSyncEntity(
    @PrimaryKey(autoGenerate = true)
    open val id: Long = 0,
    @SerializedName("local_uuid")
    open val localUuid: String = "",
    @SerializedName("server_id")
    open val serverId: Int? = null,
    @SerializedName("created_at")
    open val createdAt: Long = 0,
    @SerializedName("updated_at")
    open val updatedAt: Long = 0,
    @SerializedName("deleted_at")
    open val deletedAt: Long? = null,
    @SerializedName("last_modified")
    open val lastModified: Long = 0,
    @SerializedName("created_at_iso")
    open val createdAtIso: String? = null,
    @SerializedName("updated_at_iso")
    open val updatedAtIso: String? = null,
    @SerializedName("deleted_at_iso")
    open val deletedAtIso: String? = null,
    @SerializedName("created_at_epoch")
    open val createdAtEpoch: Long = 0,
    @SerializedName("last_modified_epoch")
    open val lastModifiedEpoch: Long = 0,
    @SerializedName("version")
    open val version: Int = 1,
    @SerializedName("origin")
    open val origin: String = "local",
    @SerializedName("vector_clock")
    open val vectorClock: String = "{}",
    @SerializedName("device_id")
    open val deviceId: String = "",
    @SerializedName("sync_timestamp")
    open val syncTimestamp: Long = 0,
    @SerializedName("idempotency_key")
    open val idempotencyKey: String? = null
)