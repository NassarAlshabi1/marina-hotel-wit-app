package com.marina.marina.data.local.entity

import androidx.room.Entity

/** Local-only durable inbox. Never upload this table or log its payload. */
@Entity(tableName = "pending_sync_links", primaryKeys = ["entity", "localUuid"])
data class PendingSyncLinkEntity(
    val entity: String,
    val localUuid: String,
    val payload: String
)
