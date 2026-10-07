package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.FinanceSnapshotEntity
import kotlinx.coroutines.flow.Flow

/**
 * Append-only DAO for finance_snapshots — schema mirror of the D1 table
 * (`worker/migrations/0009_finance_snapshots.sql`). Read-only from API;
 * no UPDATE/DELETE for governance integrity.
 *
 * ⚠️ تصحيح (2026-10-07، فحص الالتزام `4df4118` — `docs/merge-4df4118-review.md`
 * F-1): **لا مسار بيانات لهذا الـDAO اليوم** — الكيان ليس في نطاق السحب
 * (`ENTITY_TABLES`)، وغير مُسجَّل في `SyncIngestorRegistry`، و`upsert`/`upsertAll`
 * لا يُستدعيان من أي مكان (ولا `observeAll`/`listAll`/`latest`). وجوده اليوم
 * لتطابق المخطط مع الفرع المرجعي فقط.
 */
@Dao
interface FinanceSnapshotsDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(snapshot: FinanceSnapshotEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(snapshots: List<FinanceSnapshotEntity>)

    @Query("SELECT * FROM finance_snapshots ORDER BY approved_at DESC")
    fun observeAll(): Flow<List<FinanceSnapshotEntity>>

    @Query("SELECT * FROM finance_snapshots ORDER BY approved_at DESC")
    suspend fun listAll(): List<FinanceSnapshotEntity>

    @Query("SELECT * FROM finance_snapshots WHERE scenario_key = :scenarioKey ORDER BY approved_at DESC LIMIT :limit")
    suspend fun listByScenario(
        scenarioKey: String,
        limit: Int = 10,
    ): List<FinanceSnapshotEntity>

    @Query("SELECT * FROM finance_snapshots WHERE id = :id")
    suspend fun getById(id: Long): FinanceSnapshotEntity?

    @Query("SELECT * FROM finance_snapshots ORDER BY approved_at DESC LIMIT 1")
    suspend fun latest(): FinanceSnapshotEntity?

    @Query("SELECT COUNT(*) FROM finance_snapshots")
    suspend fun count(): Int
}
