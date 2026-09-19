package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.BookingNightEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface BookingNightsDao {
    @Query("SELECT * FROM booking_nights WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<BookingNightEntity>>

    @Query("SELECT * FROM booking_nights WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<BookingNightEntity>

    @Query("SELECT * FROM booking_nights WHERE id = :id")
    suspend fun getById(id: Long): BookingNightEntity?

    @Query("SELECT * FROM booking_nights WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): BookingNightEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: BookingNightEntity): Long

    @Update
    suspend fun update(entity: BookingNightEntity)

    @Query("UPDATE booking_nights SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM booking_nights WHERE id = :id")
    suspend fun delete(id: Long)
}
