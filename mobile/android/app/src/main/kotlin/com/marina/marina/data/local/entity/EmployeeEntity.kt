package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(
    tableName = "employees",
    indices = [
        Index("idx_employees_name", "name"),
        Index("idx_employees_status", "status")
    ]
)
data class EmployeeEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    override val id: Long = 0,

    @SerializedName("name")
    val name: String,

    @SerializedName("basic_salary")
    val basicSalary: Double,

    @SerializedName("position")
    val position: String = "-employed",

    @SerializedName("phone")
    val phone: String = "",

    @SerializedName("hire_date")
    val hireDate: String = "",

    @SerializedName("status")
    val status: String,

    @SerializedName("termination_date")
    val terminationDate: String? = null,

    @SerializedName("termination_reason")
    val terminationReason: String? = null,

    @SerializedName("employee_id")
    val employeeID: String? = null,

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
