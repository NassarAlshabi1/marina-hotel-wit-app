package com.marina.marina.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface RoomsDao {
    @Query("SELECT * FROM rooms WHERE deleted_at IS NULL ORDER BY room_number")
    fun getAll(): Flow<List<Room>>

    @Query("SELECT * FROM rooms WHERE deleted_at IS NULL ORDER BY room_number")
    fun getAllOnce(): List<Room>

    @Query("SELECT * FROM rooms WHERE id = :id")
    fun getById(id: Long): Room?

    @Query("SELECT * FROM rooms WHERE room_number = :roomNumber AND deleted_at IS NULL")
    fun getByNumber(roomNumber: String): Room?

    @Query("SELECT * FROM rooms WHERE room_number = :roomNumber")
    fun getByNumberIncludingDeleted(roomNumber: String): Room?

    @Query("SELECT * FROM rooms WHERE deleted_at IS NULL AND (room_number LIKE :search OR type LIKE :search OR status LIKE :search) ORDER BY room_number")
    fun search(search: String): Flow<List<Room>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(room: Room): Long

    @Update
    suspend fun update(room: Room)

    @Query("UPDATE rooms SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM rooms WHERE id = :id")
    suspend fun delete(id: Int)
}