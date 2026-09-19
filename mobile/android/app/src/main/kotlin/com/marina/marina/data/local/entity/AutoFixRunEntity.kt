package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "auto_fix_runs",
)
data class AutoFixRunEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @SerializedName("run_uuid") val runUuid: String,
    @SerializedName("source") val source: String = "unknown",
    @SerializedName("status") val status: String = "pending",
    @SerializedName("started_at_epoch") val startedAtEpoch: Long,
    @SerializedName("started_at_iso") val startedAtIso: String,
    @SerializedName("completed_at_epoch") val completedAtEpoch: Long? = null,
    @SerializedName("completed_at_iso") val completedAtIso: String? = null,
    @SerializedName("fixes_applied") val fixesApplied: Long = 0,
    @SerializedName("error_message") val errorMessage: String? = null,
    @SerializedName("metadata") val metadata: String? = null,
)
