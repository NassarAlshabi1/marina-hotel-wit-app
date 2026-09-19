package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "app_sessions",
)
data class AppSessionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @SerializedName("session_uuid") val sessionUuid: String,
    @SerializedName("device_id") val deviceId: String? = null,
    @SerializedName("session_start_iso") val sessionStartIso: String,
    @SerializedName("session_end_iso") val sessionEndIso: String? = null,
    @SerializedName("duration_seconds") val durationSeconds: Long = 0,
    @SerializedName("last_known_version") val lastKnownVersion: String? = null,
    @SerializedName("metadata") val metadata: String? = null,
)
