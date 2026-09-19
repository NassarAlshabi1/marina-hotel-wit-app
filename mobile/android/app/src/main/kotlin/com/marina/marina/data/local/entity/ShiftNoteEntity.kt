package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.ColumnInfo
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(
    tableName = "shift_notes",
    indices = [
        Index(value = ["created_by"], name = "idx_shift_notes_created_by"),
        Index(value = ["created_at"], name = "idx_shift_notes_date"),
        Index(value = ["is_read"], name = "idx_shift_notes_read"),
        Index(value = ["priority"], name = "idx_shift_notes_priority"),
        Index(value = ["shift_type"], name = "idx_shift_notes_shift_type")
    ]
)
data class ShiftNoteEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    override val id: Long = 0,

    @SerializedName("title")
    val title: String,

    @SerializedName("content")
    val content: String,

    @SerializedName("priority")
    val priority: String = "medium",

    @SerializedName("shift_type")
    @ColumnInfo(name = "shift_type")
    val shiftType: String = "all",

    @SerializedName("is_read")
    @ColumnInfo(name = "is_read")
    val isRead: Int = 0,

    @SerializedName("expires_at")
    @ColumnInfo(name = "expires_at")
    val expiresAt: String? = null,

    @SerializedName("created_by")
    @ColumnInfo(name = "created_by")
    val createdBy: String = "user",

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
