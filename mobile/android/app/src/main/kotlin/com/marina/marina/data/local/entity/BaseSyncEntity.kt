package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

/**
 * Contract for every Room entity that participates in Cloudflare D1 sync.
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
 * Common base entity class carrying the sync bookkeeping columns shared by
 * every synced table. Room supports entity inheritance: a subclass annotated
 * with `@Entity` inherits these fields as ordinary columns.
 */
open class BaseSyncEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    open val id: Long = 0,
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
) : SyncFields
