package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.BookingPriceAdjustmentEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface BookingPriceAdjustmentsDao {
    @Query("SELECT * FROM booking_price_adjustments WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<BookingPriceAdjustmentEntity>>

    @Query("SELECT * FROM booking_price_adjustments WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<BookingPriceAdjustmentEntity>

    @Query("SELECT * FROM booking_price_adjustments WHERE id = :id")
    suspend fun getById(id: Long): BookingPriceAdjustmentEntity?

    @Query("SELECT * FROM booking_price_adjustments WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): BookingPriceAdjustmentEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: BookingPriceAdjustmentEntity): Long

    @Update
    suspend fun update(entity: BookingPriceAdjustmentEntity)

    @Query("UPDATE booking_price_adjustments SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM booking_price_adjustments WHERE id = :id")
    suspend fun delete(id: Long)
}
