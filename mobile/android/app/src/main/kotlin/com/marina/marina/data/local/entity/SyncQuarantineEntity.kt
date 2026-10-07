package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity

/**
 * Local-only pull evidence. Never upload this table or log its payload.
 *
 * ✅ (2026-10-06) أُضيف [attempts] و[firstSeen]: كان الحجر بلا عدّاد
 * وبلا عمر — فلا يُعرف صفٌ عُزل مرة عن صفٍ يتكرر فشله كل دورة، ولا يُمكن
 * إخلاء الأقدم عند بلوغ السقف ([com.marina.marina.data.repository.PULL_QUARANTINE_CAP]).
 * العدّاد هو نظير `cf_pull_orphan_block_counts` في Dart، والعمر نظير
 * `first_seen` (يُستعمل للإخلاء الأقدم-أولاً).
 */
@Entity(tableName = "sync_quarantine", primaryKeys = ["entity", "recordKey"])
data class SyncQuarantineEntity(
    val entity: String,
    val recordKey: String,
    val payload: String,
    val reason: String,
    /** عدد الدورات التي فشل فيها تطبيق هذا السجل (يُحدَّث من دورة السحب). */
    @ColumnInfo(name = "attempts", defaultValue = "1")
    val attempts: Int = 1,
    /** طابع أول عزل بالثواني — أساس إخلاء السقف الأقدم-أولاً. */
    @ColumnInfo(name = "firstSeen", defaultValue = "0")
    val firstSeen: Long = 0
)
