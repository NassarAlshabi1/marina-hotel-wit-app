package com.marina.marina.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface OutboxDao {
    @Query("SELECT * FROM outbox WHERE processing_status = 'pending' AND delivered_to_primary = 0 ORDER BY client_ts ASC")
    fun getPendingPrimary(): Flow<List<Outbox>>

    @Query("SELECT * FROM outbox WHERE processing_status = 'pending' AND delivered_to_secondary = 0 ORDER BY client_ts ASC")
    fun getPendingSecondary(): Flow<List<Outbox>>

    @Query("SELECT * FROM outbox WHERE id = :id")
    suspend fun getById(id: Long): Outbox?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(outbox: Outbox): Long

    @Update
    suspend fun update(outbox: Outbox)

    @Query("UPDATE outbox SET processing_status = :status, processing_started_at = :startedAt, processing_worker = :worker, attempts = attempts + 1 WHERE id = :id")
    suspend fun markProcessing(id: Long, status: String, startedAt: Long, worker: String): Int

    @Query("UPDATE outbox SET delivered_to_primary = 1, primary_processing_status = 'completed' WHERE id = :id")
    suspend fun markDeliveredPrimary(id: Long): Int

    @Query("UPDATE outbox SET delivered_to_secondary = 1, secondary_processing_status = 'completed' WHERE id = :id")
    suspend fun markDeliveredSecondary(id: Long): Int

    @Query("UPDATE outbox SET primary_processing_status = 'failed', primary_attempts = primary_attempts + 1, primary_last_error = :error WHERE id = :id")
    suspend fun markFailedPrimary(id: Long, error: String): Int

    @Query("DELETE FROM outbox WHERE delivered_to_primary = 1 AND delivered_to_secondary = 1")
    suspend fun cleanupDelivered(): Int

    @Query("SELECT COUNT(*) FROM outbox WHERE processing_status = 'pending' AND delivered_to_primary = 0")
    fun pendingCount(): Flow<Int>
}