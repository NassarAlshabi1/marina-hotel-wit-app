package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "salary_carry_over_logs",
)
data class SalaryCarryOverLogEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") override val id: Long = 0,

    @SerializedName("employee_id") @ColumnInfo(name = "employee_id") val employeeId: Long,
    @SerializedName("amount") val amount: Double,
    @SerializedName("previous_cycle_start") @ColumnInfo(name = "previous_cycle_start") val previousCycleStart: String,
    @SerializedName("previous_cycle_end") @ColumnInfo(name = "previous_cycle_end") val previousCycleEnd: String,
    @SerializedName("new_cycle_start") @ColumnInfo(name = "new_cycle_start") val newCycleStart: String,
    @SerializedName("new_cycle_end") @ColumnInfo(name = "new_cycle_end") val newCycleEnd: String,
    @SerializedName("reason") val reason: String,
    @SerializedName("carried_at") @ColumnInfo(name = "carried_at") val carriedAt: Long,
    @SerializedName("from_cycle_id") @ColumnInfo(name = "from_cycle_id") val fromCycleId: String? = null,
    @SerializedName("to_cycle_id") @ColumnInfo(name = "to_cycle_id") val toCycleId: String? = null,
    @SerializedName("carry_date") @ColumnInfo(name = "carry_date") val carryDate: String? = null,
    @SerializedName("performed_by") @ColumnInfo(name = "performed_by") val performedBy: String? = null,
    @SerializedName("hotel_day_key") @ColumnInfo(name = "hotel_day_key") val hotelDayKey: String? = null,

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
