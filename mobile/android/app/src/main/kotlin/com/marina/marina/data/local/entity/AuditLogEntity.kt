package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "audit_logs",
)
data class AuditLogEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") override val id: Long = 0,

    @SerializedName("operation_type") @ColumnInfo(name = "operation_type") val operationType: String,
    @SerializedName("entity_type") @ColumnInfo(name = "entity_type") val entityType: String,
    @SerializedName("entity_uuid") @ColumnInfo(name = "entity_uuid") val entityUuid: String,
    @SerializedName("entity_id") @ColumnInfo(name = "entity_id") val entityId: Long? = null,
    @SerializedName("previous_state") @ColumnInfo(name = "previous_state") val previousState: String? = null,
    @SerializedName("new_state") @ColumnInfo(name = "new_state") val newState: String? = null,
    @SerializedName("changed_fields") @ColumnInfo(name = "changed_fields") val changedFields: String? = null,
    @SerializedName("performed_by") @ColumnInfo(name = "performed_by") val performedBy: String,
    @SerializedName("ip_address") @ColumnInfo(name = "ip_address") val ipAddress: String? = null,
    @SerializedName("hotel_day_key") @ColumnInfo(name = "hotel_day_key") val hotelDayKey: String,
    @SerializedName("timestamp") val timestamp: Long,
    @SerializedName("timestamp_iso") @ColumnInfo(name = "timestamp_iso") val timestampIso: String,
    @SerializedName("is_financial") @ColumnInfo(name = "is_financial") val isFinancial: Boolean = false,
    @SerializedName("amount_impact") @ColumnInfo(name = "amount_impact") val amountImpact: Long? = null,

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
