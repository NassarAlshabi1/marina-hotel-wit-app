package com.marina.marina.data.local.entity

import androidx.room.Entity

/** Local-only pull evidence. Never upload this table or log its payload. */
@Entity(tableName = "sync_quarantine", primaryKeys = ["entity", "recordKey"])
data class SyncQuarantineEntity(
    val entity: String,
    val recordKey: String,
    val payload: String,
    val reason: String
)
