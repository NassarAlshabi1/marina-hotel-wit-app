package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "sync_remote_meta", primaryKeys = ["collection", "doc_id"])
data class SyncRemoteMetaEntity(
    @SerializedName("collection") val collection: String,
    @SerializedName("doc_id") @ColumnInfo(name = "doc_id") val docId: String,
    @SerializedName("remote_updated_at_sec") @ColumnInfo(name = "remote_updated_at_sec") val remoteUpdatedAtSec: Long
)
