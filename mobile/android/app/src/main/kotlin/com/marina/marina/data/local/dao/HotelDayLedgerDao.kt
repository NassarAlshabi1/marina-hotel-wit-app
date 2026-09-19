package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.HotelDayLedgerEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface HotelDayLedgerDao {
    @Query("SELECT * FROM hotel_day_ledger WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<HotelDayLedgerEntity>>

    @Query("SELECT * FROM hotel_day_ledger WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<HotelDayLedgerEntity>

    @Query("SELECT * FROM hotel_day_ledger WHERE id = :id")
    suspend fun getById(id: Long): HotelDayLedgerEntity?

    @Query("SELECT * FROM hotel_day_ledger WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): HotelDayLedgerEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: HotelDayLedgerEntity): Long

    @Update
    suspend fun update(entity: HotelDayLedgerEntity)

    @Query("UPDATE hotel_day_ledger SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM hotel_day_ledger WHERE id = :id")
    suspend fun delete(id: Long)
}
