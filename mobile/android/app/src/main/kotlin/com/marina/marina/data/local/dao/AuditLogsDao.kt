package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.AuditLogEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AuditLogsDao {
    @Query("SELECT * FROM audit_logs WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<AuditLogEntity>>

    @Query("SELECT * FROM audit_logs WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<AuditLogEntity>

    @Query("SELECT * FROM audit_logs WHERE id = :id")
    suspend fun getById(id: Long): AuditLogEntity?

    @Query("SELECT * FROM audit_logs WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): AuditLogEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: AuditLogEntity): Long

    @Update
    suspend fun update(entity: AuditLogEntity)

    @Query("UPDATE audit_logs SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM audit_logs WHERE id = :id")
    suspend fun delete(id: Long)
}
