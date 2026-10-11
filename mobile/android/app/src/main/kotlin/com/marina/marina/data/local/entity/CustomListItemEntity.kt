package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

/**
 * Mirrors Flutter `CustomListItem` (custom_list_providers.dart l.46-73) and
 * the server `custom_list_items` table.
 * Stores dynamic catalogs (expense_type, id_type, payment_method, etc.)
 * that can be edited at runtime and synced across devices.
 */
@Entity(
    tableName = "custom_list_items",
    indices = [
        Index(value = ["list_key", "sort_order"], name = "idx_custom_list_key_order"),
        Index(value = ["list_key", "name"], name = "idx_custom_list_key_name", unique = true),
    ]
)
data class CustomListItemEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    override val id: Long = 0,

    @SerializedName("list_key")
    @ColumnInfo(name = "list_key")
    val listKey: String,

    @SerializedName("name")
    val name: String,

    @SerializedName("sort_order")
    @ColumnInfo(name = "sort_order")
    val sortOrder: Int = 0,

    @SerializedName("is_active")
    @ColumnInfo(name = "is_active")
    val isActive: Boolean = true,

    @SerializedName("is_system")
    @ColumnInfo(name = "is_system")
    val isSystem: Boolean = false,

    // Sync fields (BaseSyncEntity)
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