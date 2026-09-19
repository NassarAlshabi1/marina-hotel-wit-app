package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.GuestInfoEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface GuestInfosDao {
    @Query("SELECT * FROM guest_infos WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<GuestInfoEntity>>

    @Query("SELECT * FROM guest_infos WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<GuestInfoEntity>

    @Query("SELECT * FROM guest_infos WHERE id = :id")
    suspend fun getById(id: Long): GuestInfoEntity?

    @Query("SELECT * FROM guest_infos WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): GuestInfoEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: GuestInfoEntity): Long

    @Update
    suspend fun update(entity: GuestInfoEntity)

    @Query("UPDATE guest_infos SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM guest_infos WHERE id = :id")
    suspend fun delete(id: Long)
}
