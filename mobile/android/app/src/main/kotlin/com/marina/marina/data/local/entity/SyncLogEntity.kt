package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "sync_log",
    indices = [Index(value = ["created_at"], name = "idx_sync_log_created"), Index(value = ["sync_id"], name = "idx_sync_log_sync_id"), Index(value = ["device_id"], name = "idx_sync_log_device_id")],
)
data class SyncLogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @SerializedName("sync_id") val syncId: String,
    @SerializedName("direction") val direction: String,
    @SerializedName("device_id") val deviceId: String,
    @SerializedName("metadata") val metadata: String,
    @SerializedName("operations") val operations: String = "[]",
    @SerializedName("checksum_matched") val checksumMatched: Long = 0,
    @SerializedName("status") val status: String = "success",
    @SerializedName("created_at") val createdAt: String,
    @SerializedName("completed_at") val completedAt: String? = null,
)
