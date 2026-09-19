package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "sync_conflicts",
)
data class SyncConflictEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @SerializedName("log_id") val logId: Long,
    @SerializedName("table_name") val targetTable: String,
    @SerializedName("uuid") val uuid: String,
    @SerializedName("resolution") val resolution: String,
    @SerializedName("local_payload") val localPayload: String,
    @SerializedName("remote_payload") val remotePayload: String,
    @SerializedName("created_at") val createdAt: String,
)
