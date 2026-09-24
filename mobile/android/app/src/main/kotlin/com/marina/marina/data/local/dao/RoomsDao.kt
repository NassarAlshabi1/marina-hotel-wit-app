package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.RoomEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface RoomsDao {
    @Query("SELECT * FROM rooms WHERE deleted_at IS NULL ORDER BY room_number")
    fun getAll(): Flow<List<RoomEntity>>

    @Query("SELECT * FROM rooms WHERE deleted_at IS NULL ORDER BY room_number")
    suspend fun getAllOnce(): List<RoomEntity>

    @Query("SELECT * FROM rooms WHERE id = :id")
    suspend fun getById(id: Long): RoomEntity?

    @Query("SELECT * FROM rooms WHERE room_number = :roomNumber AND deleted_at IS NULL")
    suspend fun getByNumber(roomNumber: String): RoomEntity?

    @Query("SELECT * FROM rooms WHERE room_number = :roomNumber")
    suspend fun getByNumberIncludingDeleted(roomNumber: String): RoomEntity?

    @Query("SELECT * FROM rooms WHERE deleted_at IS NULL AND (room_number LIKE :search OR type LIKE :search OR status LIKE :search) ORDER BY room_number")
    fun search(search: String): Flow<List<RoomEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(room: RoomEntity): Long

    @Update
    suspend fun update(room: RoomEntity)

    @Query("UPDATE rooms SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM rooms WHERE id = :id")
    suspend fun delete(id: Long)
    @Query("SELECT * FROM rooms WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): RoomEntity?

    /** Targeted status update used by the Dashboard room-options dialog. */
    @Query(
        "UPDATE rooms SET status = :status, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id"
    )
    suspend fun updateStatus(id: Long, status: String, updatedAt: Long, lastModified: Long): Int

    /** البحث الشامل — كل الصفوف بما فيها المحذوفة ناعمياً (تدقيق المدير). */
    @Query("SELECT * FROM rooms")
    suspend fun listAllIncludingDeleted(): List<RoomEntity>
}
