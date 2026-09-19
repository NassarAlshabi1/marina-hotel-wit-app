package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.DeviceInfoEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface DevicesDao {
    @Query("SELECT * FROM devices WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<DeviceInfoEntity>>

    @Query("SELECT * FROM devices WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<DeviceInfoEntity>

    @Query("SELECT * FROM devices WHERE id = :id")
    suspend fun getById(id: Long): DeviceInfoEntity?

    @Query("SELECT * FROM devices WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): DeviceInfoEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: DeviceInfoEntity): Long

    @Update
    suspend fun update(entity: DeviceInfoEntity)

    @Query("UPDATE devices SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM devices WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("SELECT * FROM devices WHERE device_id = :deviceId AND deleted_at IS NULL LIMIT 1")
    suspend fun getByDeviceId(deviceId: String): DeviceInfoEntity?
}
