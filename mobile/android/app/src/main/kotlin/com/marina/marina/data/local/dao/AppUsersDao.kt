package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.AppUserEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AppUsersDao {
    @Query("SELECT * FROM app_users WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<AppUserEntity>>

    @Query("SELECT * FROM app_users WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<AppUserEntity>

    @Query("SELECT * FROM app_users WHERE id = :id")
    suspend fun getById(id: Long): AppUserEntity?

    @Query("SELECT * FROM app_users WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): AppUserEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: AppUserEntity): Long

    @Update
    suspend fun update(entity: AppUserEntity)

    @Query("UPDATE app_users SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM app_users WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("SELECT * FROM app_users WHERE username = :username AND deleted_at IS NULL LIMIT 1")
    suspend fun getByUsername(username: String): AppUserEntity?
}
