package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.SyncQuarantineEntity

@Dao
interface SyncQuarantineDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun put(row: SyncQuarantineEntity)

    @Query("SELECT * FROM sync_quarantine ORDER BY entity, recordKey")
    suspend fun getAll(): List<SyncQuarantineEntity>

    @Query("SELECT COUNT(*) FROM sync_quarantine")
    suspend fun count(): Int

    /**
     * محاولات الشفاء في الدورة: الأقدم-أولاً وبسقف صريح
     * (نظير `collectHealCandidates()` في `pull_quarantine.dart`).
     */
    @Query("SELECT * FROM sync_quarantine ORDER BY firstSeen ASC, entity ASC, recordKey ASC LIMIT :limit")
    suspend fun listForHeal(limit: Int): List<SyncQuarantineEntity>

    /**
     * الأقدم-أولاً — أساس إخلاء السقف في Kotlin (لا استعلام حذف بمركّب
     * صفوف: صيغة `(a, b) NOT IN (SELECT …)` تحتاج SQLite 3.15+ ولا تعمل
     * على أندرويد 7). الجدول صغير (سقف 300) فالقراءة ثم الحذف المفرد كافية.
     */
    @Query("SELECT * FROM sync_quarantine ORDER BY firstSeen ASC, entity ASC, recordKey ASC")
    suspend fun oldestFirst(): List<SyncQuarantineEntity>

    @Query("DELETE FROM sync_quarantine WHERE entity = :entity AND recordKey = :recordKey")
    suspend fun remove(entity: String, recordKey: String)
}
