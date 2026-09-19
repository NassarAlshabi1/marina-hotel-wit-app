package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "integrity_violations",
)
data class IntegrityViolationEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @SerializedName("run_id") val runId: Long,
    @SerializedName("affected_table_name") val affectedTableName: String,
    @SerializedName("record_uuid") val recordUuid: String? = null,
    @SerializedName("violation_type") val violationType: String,
    @SerializedName("details") val details: String,
    @SerializedName("is_critical") val isCritical: Boolean = false,
    @SerializedName("created_at_iso") val createdAtIso: String,
    @SerializedName("created_at_epoch") val createdAtEpoch: Long,
)
