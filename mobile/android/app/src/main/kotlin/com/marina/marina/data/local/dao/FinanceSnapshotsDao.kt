package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.FinanceSnapshotEntity
import kotlinx.coroutines.flow.Flow

/**
 * Append-only DAO for finance_snapshots — local mirror of the B2
 * worker `/api/finance/snapshots` route. Read-only from API; INSERT
 * is called only by the sync ingestor when pulling a new snapshot
 * from D1 (no UPDATE/DELETE for governance integrity).
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
