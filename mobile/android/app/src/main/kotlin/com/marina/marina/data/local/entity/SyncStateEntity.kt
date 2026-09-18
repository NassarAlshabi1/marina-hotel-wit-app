package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

/** Singleton row (id is always 1) tracking the local sync cursor. */
@Entity(tableName = "sync_state")
data class SyncStateEntity(
    @PrimaryKey
    @SerializedName("id")
    val id: Int = 1,

    @SerializedName("last_server_ts")
    val lastServerTs: Long = 0,

    @SerializedName("last_pull_ts")
    val lastPullTs: Long = 0,

    @SerializedName("last_push_ts")
    val lastPushTs: Long = 0,

    @SerializedName("is_syncing")
    val isSyncing: Int = 0,

    @SerializedName("version")
    val version: Int = 1,

    @SerializedName("full_sync_complete")
    val fullSyncComplete: Int = 0
)
