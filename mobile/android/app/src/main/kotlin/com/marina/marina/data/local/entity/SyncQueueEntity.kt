package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "sync_queue",
)
data class SyncQueueEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @SerializedName("uuid") val uuid: String,
    @SerializedName("table_name") val targetTable: String,
    @SerializedName("operation") val operation: String,
    @SerializedName("payload") val payload: String,
    @SerializedName("updated_at") val updatedAt: String,
    @SerializedName("device_id") val deviceId: String,
    @SerializedName("status") val status: String = "pending",
    @SerializedName("created_at") val createdAt: String,
)
